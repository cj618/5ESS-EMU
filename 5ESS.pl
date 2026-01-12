#!/usr/bin/perl

use strict;
use warnings;
use JSON::PP;
use Term::ReadKey;
use File::Path qw(make_path);

# -----------------------------------------------------------------------------
# 5ESS AT&T craft environment miniature emulator
# -----------------------------------------------------------------------------
# Copyright (c) 2025, 2026 C R Jervis under the terms outlined in LICENSE document.
# Based on documentation that is Copyright (c) 1984 - 1991 AT&T.
#
# 5ESS is a registered trademark of Lucent Technologies, Inc.
#
# -----------------------------------------------------------------------------

# In-memory data structures
my %lines;         # key = terminal number, value = hashref of line data
my %dns;           # key = directory number, value = terminal number
my @alarms;        # array of outstanding alarm strings
my %rcaccess;      # key = tty_name, value = permissions mask
my %clerks;        # key = clerk_id, value = password (plain ok)
my @batch_queue;   # stub batch queue
my @scc_events;    # SCC ring buffer

my $session_seq = 0;
my $scc_log_limit = 60;

# MCC pages (minimal stub index + sample pages)
my %mcc_pages = (
    '1000' => {
        title => 'MCC Page Index',
        body  => [
            '105  System Status Summary',
            '110  Switch Environment',
            '115  CM2 Status',
            '116  CM2 Alarms',
            '123  Network Overview',
            '125  Trunk Summary',
            '1800X Processor Status',
            '1850  Recent-Change Activity',
            '1851  Verification Summary',
        ],
    },
    '105' => {
        title => 'System Status Summary',
        body  => [
            'SM02  OK',
            'SM03  OK',
            'PWR   MINOR (Battery discharge 50.9 V)',
            'ALM   MAJOR (High-Bit-Error-Rate)',
        ],
    },
    '110' => {
        title => 'Switch Environment',
        body  => [
            'TEMP  72F',
            'HUM   45%',
            'PWR   53.1V',
            'FANS  OK',
        ],
    },
);

sub mcc_location_guide {
    print "\n--- MCC Page Location Guide (stub) ---\n";
    print "Use MCC:SHOW <page> to display a page.\n";
    print "Known pages: " . join(', ', sort keys %mcc_pages) . "\n";
}

sub mcc_show_page {
    my ($page) = @_;
    $page ||= '';
    $page =~ s/^\s+|\s+$//g;
    unless ($page && exists $mcc_pages{$page}) {
        print "? MCC page not found. Use MCC:GUIDE for list.\n";
        return;
    }
    my $entry = $mcc_pages{$page};
    print "\n--- MCC PAGE $page: $entry->{title} ---\n";
    print "$_\n" for @{ $entry->{body} };
}

# Helper subs ------------------------------------------------------------------
sub now_stamp {
    my @t = localtime();
    return sprintf "%04d-%02d-%02d %02d:%02d:%02d",
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0];
}

sub dmert_base_dir {
    return './rclog';
}

sub dmert_state_path {
    return dmert_base_dir() . '/state.json';
}

sub dmert_journal_path {
    return dmert_base_dir() . '/journal.log';
}

sub dmert_default_state {
    return {
        lines       => {},
        dns         => {},
        alarms      => [
            'MINOR  SM02  High-Bit-Error-Rate',
            'MAJOR  PWR   Battery discharge 53.1 V -> 50.9 V',
        ],
        rcaccess    => {
            ttyV => 'FFFFF',
            ttyW => 'FFFFF',
        },
        clerks      => {},
        batch_queue => [],
        scc_log     => [],
    };
}

sub dmert_append_journal {
    my ($line) = @_;
    my $dir = dmert_base_dir();
    make_path($dir) unless -d $dir;
    my $path = dmert_journal_path();
    open my $fh, '>>', $path or return;
    print {$fh} now_stamp() . " $line\n";
    close $fh;
}

sub dmert_save_state {
    my ($state, $reason) = @_;
    $reason ||= 'update';
    my $dir = dmert_base_dir();
    make_path($dir) unless -d $dir;
    my $path = dmert_state_path();
    my $tmp = $path . '.tmp';
    my $json = JSON::PP->new->utf8->pretty(1)->encode($state);
    open my $fh, '>', $tmp or die "Unable to write $tmp: $!";
    print {$fh} $json;
    close $fh;
    rename $tmp, $path or die "Unable to replace $path: $!";
    dmert_append_journal("$reason state saved");
}

sub dmert_load_state {
    my $dir = dmert_base_dir();
    make_path($dir) unless -d $dir;
    my $path = dmert_state_path();
    unless (-e $path) {
        my $state = dmert_default_state();
        dmert_save_state($state, 'bootstrap');
        return $state;
    }
    open my $fh, '<', $path or die "Unable to read $path: $!";
    local $/;
    my $json = <$fh>;
    close $fh;
    my $data = eval { JSON::PP->new->utf8->decode($json) };
    if (!$data || ref $data ne 'HASH') {
        my $state = dmert_default_state();
        dmert_save_state($state, 'reset');
        return $state;
    }
    return $data;
}

sub dmert_snapshot_state {
    return {
        lines       => { %lines },
        dns         => { %dns },
        alarms      => [ @alarms ],
        rcaccess    => { %rcaccess },
        clerks      => { %clerks },
        batch_queue => [ @batch_queue ],
        scc_log     => [ @scc_events ],
    };
}

sub scc_enqueue {
    my ($text) = @_;
    my $line = now_stamp() . " $text";
    push @scc_events, $line;
    shift @scc_events while @scc_events > $scc_log_limit;
}

sub rcaccess_allows_changes {
    my ($session) = @_;
    return 1 unless $session->{channel} =~ /^RCV_/;
    my $mask = $rcaccess{$session->{tty_name}} // 'FFFFF';
    return uc($mask) eq 'FFFFF';
}

sub clerk_allows_changes {
    my ($session) = @_;
    return 1 unless $session->{channel} =~ /^RCV_/;
    return defined $session->{clerk_id} && $session->{clerk_id} ne '';
}

sub channel_allows_rc_changes {
    my ($session) = @_;
    return 0 if $session->{channel} eq 'SCC';
    return 1;
}

sub allow_or_deny {
    my ($allowed, $reason) = @_;
    if (!$allowed) {
        print "NG - $reason\n";
        return 0;
    }
    return 1;
}

sub session_prompt {
    my ($session) = @_;
    return "SCC> "   if $session->{mode} eq 'SCC';
    return "RC/V> "  if $session->{mode} eq 'RCV_MENU';
    return "< ";
}

sub session_create {
    my ($channel, $clerk_id) = @_;
    $session_seq++;
    return {
        session_id       => $session_seq,
        channel          => $channel,
        mode             => ($channel eq 'SCC') ? 'SCC' : 'CRAFT',
        clerk_id         => $clerk_id,
        tty_name         => 'ttyV',
        permissions_mask => $rcaccess{'ttyV'} // 'FFFFF',
        created_at       => now_stamp(),
    };
}

sub clerk_login {
    my ($channel) = @_;
    while (1) {
        print "CLERK ID? ";
        my $clerk_id = <STDIN> // '';
        chomp $clerk_id;
        $clerk_id =~ s/^\s+|\s+$//g;
        next unless $clerk_id;

        print "PASSWORD? ";
        my $password = <STDIN> // '';
        chomp $password;

        if (exists $clerks{$clerk_id}) {
            if ($clerks{$clerk_id} eq $password) {
                return $clerk_id;
            }
            print "NG - INVALID PASSWORD\n";
            next;
        }

        if ($channel eq 'TEST') {
            $clerks{$clerk_id} = $password;
            my $state = dmert_snapshot_state();
            dmert_save_state($state, "clerk $clerk_id");
            print "NEW CLERK CREATED\n";
            return $clerk_id;
        }

        print "NG - CLERK NOT AUTHORIZED\n";
    }
}

sub select_channel {
    print "\nChannel Select:\n";
    print " 1) MCC\n";
    print " 2) RC/V Local\n";
    print " 3) RC/V Remote\n";
    print " 4) SCC\n";
    print " 5) TEST\n";
    print "Select (default RC/V Local): ";
    my $sel = <STDIN> // '';
    chomp $sel;
    $sel =~ s/^\s+|\s+$//g;
    return 'RCV_LOCAL' if $sel eq '';
    return 'MCC'        if $sel eq '1';
    return 'RCV_LOCAL'  if $sel eq '2';
    return 'RCV_REMOTE' if $sel eq '3';
    return 'SCC'        if $sel eq '4';
    return 'TEST'       if $sel eq '5';
    return 'RCV_LOCAL';
}

sub handle_alm_list {
    print "\n=== Outstanding Alarms ===\n";
    print "$_\n" for @alarms;
}

sub handle_op_rcaccess {
    my ($tty) = @_;
    my $mask = $rcaccess{$tty};
    if ($mask) {
        print "RCACCESS TTY=\"$tty\" ACCESS=H'$mask'\n";
    } else {
        print "RL - NO SUCH TTY\n";
    }
}

sub handle_set_rcaccess {
    my ($tty, $mask) = @_;
    $rcaccess{$tty} = uc $mask;
    my $state = dmert_snapshot_state();
    dmert_save_state($state, "rcaccess $tty");
    scc_enqueue("SCC RCACCESS UPDATE TTY=$tty ACCESS=H'$mask'");
    print "RCACCESS UPDATED\n";
}

sub handle_op_clerk {
    my ($session) = @_;
    my $clerk = $session->{clerk_id} // 'NONE';
    print "CLERK ID=\"$clerk\" CHANNEL=$session->{channel}\n";
}

sub dispatch_craft_command {
    my ($session, $cmd) = @_;
    if ($cmd =~ /^RCV:MENU:APPRC\b/i || $cmd =~ /^RCV\b/i) {
        return 0 unless allow_or_deny(channel_allows_rc_changes($session), 'CHANNEL RESTRICTED');
        $session->{mode} = 'RCV_MENU';
        print "\n--- 5ESS Recent-Change/Verify ---\n";
        print " 1 Line/Station  8 Directory-Number  0 Verify  Q Quit\n";
        return 1;
    }
    if ($cmd =~ /^ALM:LIST:?/i) {
        handle_alm_list();
        return 1;
    }
    if ($cmd =~ /^MCC:GUIDE:?$/i) {
        mcc_location_guide();
        return 1;
    }
    if ($cmd =~ /^MCC:SHOW\s+(\S+)$/i) {
        mcc_show_page($1);
        return 1;
    }
    if ($cmd =~ /^OP:RCACCESS,TTY="([^"]+)"\s*;?$/i) {
        handle_op_rcaccess($1);
        return 1;
    }
    if ($cmd =~ /^OP:CLERK\s*;?$/i) {
        handle_op_clerk($session);
        return 1;
    }
    if ($cmd =~ /^SET:RCACCESS,TTY="([^"]+)",ACCESS=H'([0-9A-Fa-f]{5})'\s*;?$/i) {
        handle_set_rcaccess($1, $2);
        return 1;
    }
    if ($cmd =~ /^HELP$/i) {
        print "\nAvailable commands: RCV:MENU:APPRC   ALM:LIST   MCC:GUIDE   MCC:SHOW <page>   OP:CLERK   OP:RCACCESS   SET:RCACCESS   HELP   QUIT\n";
        return 1;
    }
    print "? Unrecognised command – type HELP for options.\n";
    return 1;
}

sub line_station_menu {
    my ($session) = @_;
    return unless allow_or_deny(channel_allows_rc_changes($session), 'CHANNEL RESTRICTED');
    return unless allow_or_deny(clerk_allows_changes($session), 'CLERK LOGIN REQUIRED');
    return unless allow_or_deny(rcaccess_allows_changes($session), 'RCACCESS DENIED');

    print "\n[1.11] Line Assignment – Terminal #, Cable-Pair, COS, Type, Class, Features\n";

    print "TERMINAL? ";
    my $term = <STDIN>; chomp $term; $term =~ s/^\s+|\s+$//g;
    return unless $term;

    print "CABLE-PAIR? ";
    my $pair = <STDIN>; chomp $pair; $pair =~ s/^\s+|\s+$//g;

    print "CLASS OF SERVICE (e.g. POTS, ISDN)? ";
    my $cos = <STDIN>; chomp $cos; $cos =~ s/^\s+|\s+$//g;

    print "LINE TYPE (e.g. 1FR, 1TR, ISDN)? ";
    my $linetype = <STDIN>; chomp $linetype; $linetype =~ s/^\s+|\s+$//g;

    print "LINE CLASS (e.g. RES, BUS)? ";
    my $lineclass = <STDIN>; chomp $lineclass; $lineclass =~ s/^\s+|\s+$//g;

    print "FEATURES (comma-separated, e.g. CALLWAIT, 3WAY)? ";
    my $features = <STDIN>; chomp $features; $features =~ s/^\s+|\s+$//g;

    $lines{$term} = {
        pair     => $pair,
        cos      => $cos,
        dn       => undef,
        linetype => $linetype,
        class    => $lineclass,
        features => $features,
    };

    my $state = dmert_snapshot_state();
    dmert_save_state($state, "line $term");
    scc_enqueue("SCC LINE CREATED TERM=$term");
    print "\nRECENT CHANGE COMPLETED – terminal $term ready.\n";
}

sub directory_number_menu {
    my ($session) = @_;
    return unless allow_or_deny(channel_allows_rc_changes($session), 'CHANNEL RESTRICTED');
    return unless allow_or_deny(clerk_allows_changes($session), 'CLERK LOGIN REQUIRED');
    return unless allow_or_deny(rcaccess_allows_changes($session), 'RCACCESS DENIED');

    print "\n[8.12] Assign Directory Number – enter DN & Terminal #\n";
    print "DN? ";
    my $dn = <STDIN>; chomp $dn; $dn =~ s/^\s+|\s+$//g;
    return unless $dn;

    print "TERMINAL? ";
    my $term = <STDIN>; chomp $term; $term =~ s/^\s+|\s+$//g;

    unless (exists $lines{$term}) {
        print "? Terminal $term not yet provisioned – aborting.\n";
        return;
    }

    $lines{$term}{dn} = $dn;
    $dns{$dn} = $term;
    my $state = dmert_snapshot_state();
    dmert_save_state($state, "dn $dn");
    scc_enqueue("SCC DN ASSIGNED DN=$dn TERM=$term");
    print "\nRECENT CHANGE COMPLETED – $dn now active on terminal $term.\n";
}

sub verify_menu {
    print "\n--- Translation Database Dump ---\n";
    for my $term (sort keys %lines) {
        my $rec = $lines{$term};
        printf "TERM %-6s DN %-10s COS %-8s TYPE %-6s CLASS %-5s FEAT [%s] CABLE %s\n",
            $term,
            ($rec->{dn} // '---------'),
            ($rec->{cos} // ''),
            ($rec->{linetype} // ''),
            ($rec->{class} // ''),
            ($rec->{features} // ''),
            ($rec->{pair} // '');
    }
}

sub dispatch_rcv_menu {
    my ($session, $cmd) = @_;
    if ($cmd =~ /^RCV:MENU:SH!\b/i) {
        $session->{mode} = 'CRAFT';
        return 1;
    }
    if ($cmd =~ /^Q$/i) {
        $session->{mode} = 'CRAFT';
        return 1;
    }
    if ($cmd =~ /^1$/) {
        line_station_menu($session);
        return 1;
    }
    if ($cmd =~ /^8$/) {
        directory_number_menu($session);
        return 1;
    }
    if ($cmd =~ /^0$/) {
        verify_menu();
        return 1;
    }
    if ($cmd =~ /^ALM:LIST:?/i) {
        handle_alm_list();
        return 1;
    }
    if ($cmd =~ /^OP:RCACCESS,TTY="([^"]+)"\s*;?$/i) {
        handle_op_rcaccess($1);
        return 1;
    }
    if ($cmd =~ /^OP:CLERK\s*;?$/i) {
        handle_op_clerk($session);
        return 1;
    }
    if ($cmd =~ /^SET:RCACCESS,TTY="([^"]+)",ACCESS=H'([0-9A-Fa-f]{5})'\s*;?$/i) {
        handle_set_rcaccess($1, $2);
        return 1;
    }
    print "? Invalid selection\n";
    return 1;
}

sub scc_emit_lines {
    my $count = int(rand(4));
    $count = @scc_events if $count > @scc_events;
    for (1 .. $count) {
        my $line = shift @scc_events;
        print "$line\n" if defined $line;
    }
}

sub dispatch_scc {
    my ($session, $cmd) = @_;
    if ($cmd =~ /^ALM:LIST:?/i) {
        handle_alm_list();
        scc_emit_lines();
        return 1;
    }
    if ($cmd =~ /^OP:/i) {
        print "(stub) SCC OP response\n";
        scc_emit_lines();
        return 1;
    }
    print "(stub) SCC command ignored\n";
    scc_emit_lines();
    return 1;
}

sub main_loop {
    my ($session) = @_;
    while (1) {
        print session_prompt($session);
        my $cmd = <STDIN> // '';
        chomp $cmd;
        $cmd =~ s/^\s+|\s+$//g;
        next unless $cmd;

        if ($cmd =~ /^QUIT$/i) {
            print "Logout complete – have a good one.\n";
            last;
        }

        if ($session->{mode} eq 'CRAFT') {
            dispatch_craft_command($session, $cmd);
        } elsif ($session->{mode} eq 'RCV_MENU') {
            dispatch_rcv_menu($session, $cmd);
        } else {
            dispatch_scc($session, $cmd);
        }
    }
}

# print login motd for simulation purposes

print "\n";
open my $fh, '<', 'etc/motd.dat' or die $!;
print while <$fh>;
close $fh;

my $state = dmert_load_state();
%lines = %{ $state->{lines} // {} };
%dns = %{ $state->{dns} // {} };
@alarms = @{ $state->{alarms} // [] };
%rcaccess = %{ $state->{rcaccess} // {} };
%clerks = %{ $state->{clerks} // {} };
@batch_queue = @{ $state->{batch_queue} // [] };
@scc_events = @{ $state->{scc_log} // [] };

my $channel = select_channel();
my $clerk_id = clerk_login($channel);
my $session = session_create($channel, $clerk_id);

print "\n* * *  5ESS Craft Shell (sim)  * * *\nType HELP for command list.\n\n";

main_loop($session);
