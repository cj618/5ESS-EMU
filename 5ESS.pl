#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Digest::SHA qw(sha256_hex);
use Term::ReadKey;
use Time::HiRes qw(usleep);

use Persist;
use TermUI;
use Alarms;
use RCV;
use SCC;

# -----------------------------------------------------------------------------
# 5ESS AT&T craft environment miniature emulator
# -----------------------------------------------------------------------------
# Copyright (c) 2025, 2026 C R Jervis under the terms outlined in LICENSE document.
# Based on documentation that is Copyright (c) 1984 - 1991 AT&T.
#
# 5ESS is a registered trademark of Lucent Technologies, Inc.
# -----------------------------------------------------------------------------

my %config = (
    semicolon_required => {
        CRAFT    => 0,
        RCV_MENU => 1,
        SCC      => 0,
    },
    latency_ms => {
        ALM_LIST  => [50, 150],
        SCC_SUBMIT => [50, 150],
        RCV_COMMIT => [50, 150],
    },
    journal_size_threshold => 10_000,
    unauth_alarm_threshold => 3,
    unauth_decay_seconds   => 600,
    scc_backlog_threshold  => 3,
    auth_timeout_seconds   => 300,
    auth_uses              => 5,
);

srand($ENV{'5ESS_SEED'}) if defined $ENV{'5ESS_SEED'};

my $ui = TermUI->new(title => 'PACIFIC BELL 5ESS CRAFT ENVIRONMENT');

sub now_stamp {
    return Persist::now_stamp();
}

sub password_hash {
    my ($clerk_id, $password) = @_;
    return sha256_hex('5ess', $clerk_id // '', $password // '');
}

sub maybe_latency {
    my ($key) = @_;
    return unless exists $config{latency_ms}{$key};
    my ($min, $max) = @{ $config{latency_ms}{$key} };
    my $delay = $min + int(rand($max - $min + 1));
    usleep($delay * 1000);
}

sub apply_event {
    my ($state, $event) = @_;
    my $type = $event->{type} // '';
    if ($type eq 'rcaccess_set') {
        $state->{rcaccess}{ $event->{tty} } = $event->{mask};
    } elsif ($type eq 'clerk_add') {
        my $hash = $event->{password_hash}
            // password_hash($event->{clerk}, $event->{password});
        $state->{clerks}{ $event->{clerk} } = {
            password_hash => $hash,
            role          => $event->{role},
        };
    } elsif ($type eq 'alarm_raise') {
        push @{ $state->{alarms} }, $event->{alarm};
        $state->{next_alarm_id} = $event->{alarm}{id} + 1
            if ($event->{alarm}{id} && $event->{alarm}{id} >= ($state->{next_alarm_id} || 1));
    } elsif ($type eq 'alarm_ack') {
        for my $alarm (@{ $state->{alarms} }) {
            next unless $alarm->{id} == $event->{id};
            $alarm->{ack_state} = 'ACK';
        }
    } elsif ($type eq 'alarm_clear') {
        for my $alarm (@{ $state->{alarms} }) {
            next unless $alarm->{id} == $event->{id};
            $alarm->{cleared_time} = $event->{cleared_time};
        }
    } elsif ($type eq 'line_set') {
        $state->{lines}{ $event->{term} } = $event->{line};
    } elsif ($type eq 'dn_set') {
        $state->{dns}{ $event->{dn} } = $event->{term};
    } elsif ($type eq 'rcv_open') {
        $state->{rcv_sessions}{ $event->{channel} } = {
            ticket_id => $event->{ticket_id},
            opened_at => $event->{opened_at},
            changes   => {},
        };
    } elsif ($type eq 'rcv_add') {
        $state->{rcv_sessions}{ $event->{channel} }{changes}{ $event->{key} } = $event->{value};
    } elsif ($type eq 'rcv_abort') {
        $state->{rcv_sessions}{ $event->{channel} } = {
            ticket_id => undef,
            opened_at => undef,
            changes   => {},
        };
    } elsif ($type eq 'rcv_commit') {
        my $channel = $event->{channel};
        my $changes = $event->{changes} || {};
        if ((!$changes->{TERM} || !keys %{$changes}) && ref($event->{applied}) eq 'HASH') {
            my $applied = $event->{applied};
            $changes = { %{$changes} };
            $changes->{TERM} //= $applied->{term} if defined $applied->{term};
            $changes->{DN}   //= $applied->{dn} if defined $applied->{dn};
        }
        my $term = $changes->{TERM};
        if ($term) {
            my $line = $state->{lines}{$term} || {};
            for my $field (qw(PAIR COS LINETYPE CLASS FEATURES)) {
                $line->{ lc($field) } = $changes->{$field} if defined $changes->{$field};
            }
            $state->{lines}{$term} = $line;
            if ($changes->{DN}) {
                $line->{dn} = $changes->{DN};
                $state->{dns}{ $changes->{DN} } = $term;
            }
        }
        $state->{rcv_sessions}{$channel} = {
            ticket_id => undef,
            opened_at => undef,
            changes   => {},
        };
    } elsif ($type eq 'scc_submit') {
        push @{ $state->{batch_queue} }, $event->{job};
        $state->{next_job_id} = $event->{job}{id} + 1
            if ($event->{job}{id} && $event->{job}{id} >= ($state->{next_job_id} || 1));
    } elsif ($type eq 'unauth') {
        $state->{unauth}{count} = $event->{count};
        $state->{unauth}{last_time} = $event->{last_time};
    }
}

my $state = Persist::default_state();
Persist::replay_journal(sub { apply_event($state, shift) });

if (!@{ $state->{alarms} }) {
    my $alarms = Alarms->new($state);
    $alarms->raise_alarm(severity => 'MN', source => 'SM02', text => 'HIGH-BIT-ERROR-RATE');
    $alarms->raise_alarm(severity => 'MJ', source => 'PWR', text => 'BATTERY DISCHARGE 53.1 V -> 50.9 V');
}

my $alarms = Alarms->new($state);
my $scc = SCC->new($state);
update_derived_alarms($state);

sub update_derived_alarms {
    my ($state) = @_;
    my $alarms = Alarms->new($state);
    my $journal = Persist::journal_path();
    my $size = -e $journal ? -s $journal : 0;
    if ($size > $config{journal_size_threshold}) {
        $alarms->ensure_alarm('DMERT', severity => 'MJ', text => 'DMERT JOURNAL NEAR FULL');
    } else {
        $alarms->clear_by_source('DMERT');
    }

    my $unauth = $state->{unauth}{count} || 0;
    if ($unauth >= $config{unauth_alarm_threshold}) {
        $alarms->ensure_alarm('SECURITY', severity => 'MN', text => 'UNAUTH ATTEMPT');
    } else {
        $alarms->clear_by_source('SECURITY');
    }

    my $queue = @{ $state->{batch_queue} || [] };
    if ($queue > $config{scc_backlog_threshold}) {
        $alarms->ensure_alarm('SCC', severity => 'MN', text => 'SCC BACKLOG');
    } else {
        $alarms->clear_by_source('SCC');
    }
}

sub decay_unauth {
    my ($state) = @_;
    my $last = $state->{unauth}{last_time};
    return unless $last;
    my $now = time();
    my $last_epoch = $state->{unauth}{last_epoch} || 0;
    if ($last_epoch == 0) {
        $state->{unauth}{last_epoch} = $now;
        return;
    }
    if (($now - $last_epoch) > $config{unauth_decay_seconds}) {
        $state->{unauth}{count} = 0;
        $state->{unauth}{last_time} = undef;
        $state->{unauth}{last_epoch} = $now;
        Persist::append_journal({
            type      => 'unauth',
            count     => 0,
            last_time => undef,
        });
    }
}

sub record_unauth {
    my ($state) = @_;
    $state->{unauth}{count} = ($state->{unauth}{count} || 0) + 1;
    $state->{unauth}{last_time} = now_stamp();
    $state->{unauth}{last_epoch} = time();
    Persist::append_journal({
        type      => 'unauth',
        count     => $state->{unauth}{count},
        last_time => $state->{unauth}{last_time},
    });
}

sub status_text {
    my ($session) = @_;
    my $err = $session->{last_error} || { code => 'OK', msg => '' };
    my $err_text = $err->{code};
    $err_text .= " $err->{msg}" if $err->{msg};
    my $seq = sprintf('%05d', $session->{seq} || 0);
    my $mode = $session->{mode} eq 'RCV_MENU' ? 'RCV' : $session->{mode};
    return sprintf(
        'CH=%s CLRK=%s MODE=%s TIME=%s SEQ=%s ERR=%s',
        $session->{channel},
        $session->{clerk_id} // 'NONE',
        $mode,
        now_stamp(),
        $seq,
        $err_text,
    );
}

sub set_last_error {
    my ($session, $code, $msg) = @_;
    $session->{last_error} = { code => $code, msg => ($msg // '') };
}

sub result_ok {
    my ($session, $msg) = @_;
    set_last_error($session, 'OK', '');
    print "RESULT: OK";
    print " - $msg" if defined $msg && $msg ne '';
    print "\n";
}

sub result_ng {
    my ($session, $msg) = @_;
    set_last_error($session, 'NG', $msg);
    print "RESULT: NG - $msg\n";
}

sub error_out {
    my ($session, $msg) = @_;
    set_last_error($session, $msg, '');
    print "? $msg\n";
}

sub session_prompt {
    my ($session) = @_;
    my $seq = sprintf('%05d', $session->{seq} || 0);
    my $mode = $session->{mode} eq 'RCV_MENU' ? 'RCV' : $session->{mode};
    return sprintf(
        'CH=%s CLRK=%s MODE=%s %s SEQ=%s> ',
        $session->{channel},
        $session->{clerk_id} // 'NONE',
        $mode,
        now_stamp(),
        $seq,
    );
}

sub session_create {
    my ($channel, $clerk_id, $role) = @_;
    return {
        channel          => $channel,
        mode             => ($channel eq 'SCC') ? 'SCC' : 'CRAFT',
        clerk_id         => $clerk_id,
        role             => $role,
        tty_name         => 'ttyV',
        permissions_mask => $state->{rcaccess}{'ttyV'} // 'FFFFF',
        created_at       => now_stamp(),
        seq              => 0,
        last_error       => { code => 'OK', msg => '' },
        auth_token       => undef,
    };
}

sub print_banner {
    $ui->screen_clear();
    $ui->draw_header();
    print "UNAUTHORIZED USE PROHIBITED\n";
    print "ALL ACTIVITY MAY BE MONITORED AND RECORDED\n\n";
    if (-e 'etc/motd.dat') {
        open my $fh, '<', 'etc/motd.dat';
        print while <$fh>;
        close $fh;
    }
    $ui->draw_footer('ENTER CLERK ID TO CONTINUE');
}

sub select_channel {
    print "\nCHANNEL SELECT:\n";
    print " 1) MCC\n";
    print " 2) RC/V LOCAL\n";
    print " 3) RC/V REMOTE\n";
    print " 4) SCC\n";
    print " 5) TEST\n";
    print "SELECT (DEFAULT RC/V LOCAL): ";
    my $sel = <STDIN> // '';
    chomp $sel;
    $sel =~ s/^\s+|\s+$//g;
    return 'RCV_LOCAL' if $sel eq '' || $sel eq '2';
    return 'MCC'        if $sel eq '1';
    return 'RCV_REMOTE' if $sel eq '3';
    return 'SCC'        if $sel eq '4';
    return 'TEST'       if $sel eq '5';
    return 'RCV_LOCAL';
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

        if (exists $state->{clerks}{$clerk_id}) {
            if (($state->{clerks}{$clerk_id}{password_hash} // '')
                eq password_hash($clerk_id, $password)) {
                return ($clerk_id, $state->{clerks}{$clerk_id}{role});
            }
            print "RESULT: NG - INVALID PASSWORD\n";
            next;
        }

        if ($channel eq 'TEST') {
            print "PRIVILEGE CLASS (ADMIN/TECH/OBS)? ";
            my $role = <STDIN> // '';
            chomp $role;
            $role = uc($role || 'TECH');
            $role = 'TECH' unless $role =~ /^(ADMIN|TECH|OBS)$/;
            my $hash = password_hash($clerk_id, $password);
            $state->{clerks}{$clerk_id} = { password_hash => $hash, role => $role };
            Persist::append_journal({
                type     => 'clerk_add',
                clerk    => $clerk_id,
                password_hash => $hash,
                role     => $role,
            });
            print "RESULT: OK - NEW CLERK CREATED\n";
            return ($clerk_id, $role);
        }

        print "RESULT: NG - CLERK NOT AUTHORIZED\n";
    }
}

sub rcaccess_allows_changes {
    my ($session) = @_;
    return 1 unless $session->{channel} =~ /^RCV_/;
    my $mask = $state->{rcaccess}{ $session->{tty_name} } // 'FFFFF';
    return uc($mask) eq 'FFFFF';
}

sub role_allows_commit {
    my ($session) = @_;
    return 1 if ($session->{role} // '') eq 'ADMIN';
    return 0;
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

sub has_second_auth {
    my ($session) = @_;
    my $token = $session->{auth_token} || return 0;
    if (time() > $token->{expires_at}) {
        $session->{auth_token} = undef;
        return 0;
    }
    return 1 if ($token->{uses_left} // 0) > 0;
    return 0;
}

sub consume_second_auth {
    my ($session) = @_;
    return unless $session->{auth_token};
    $session->{auth_token}{uses_left}-- if $session->{auth_token}{uses_left} > 0;
}

sub grant_second_auth {
    my ($session, $other_clerk) = @_;
    return (0, 'CLERK NOT FOUND') unless exists $state->{clerks}{$other_clerk};
    return (0, 'SECOND AUTH MUST BE DIFFERENT CLERK') if $other_clerk eq $session->{clerk_id};
    $session->{auth_token} = {
        clerk      => $other_clerk,
        expires_at => time() + $config{auth_timeout_seconds},
        uses_left  => $config{auth_uses},
    };
    return (1, "AUTH GRANTED BY $other_clerk");
}

sub require_semicolon {
    my ($session, $cmd) = @_;
    return 0 if $cmd =~ m{^/};
    my $mode = $session->{mode};
    return 0 unless $config{semicolon_required}{$mode};
    return 0 if $mode eq 'RCV_MENU' && $cmd =~ /^(?:\d|Q)$/i;
    return $cmd !~ /;\s*$/;
}

sub handle_alm_list {
    my ($session) = @_;
    maybe_latency('ALM_LIST');
    my $rows = $alarms->list_active();
    my $output = "ID   SEV ACK   RAISED              CLEARED             SOURCE   TEXT\n";
    $output .= ("-" x 78) . "\n";
    for my $alarm (@$rows) {
        $output .= sprintf(
            "%-4d %-3s %-5s %-19s %-19s %-8s %s\n",
            $alarm->{id},
            $alarm->{severity},
            $alarm->{ack_state},
            $alarm->{raised_time} || '',
            $alarm->{cleared_time} || '--',
            $alarm->{source} || '',
            $alarm->{text} || '',
        );
    }
    $ui->pager($output);
    result_ok($session, 'ALARM LISTED');
}

sub handle_op_rcaccess {
    my ($session, $tty) = @_;
    my $mask = $state->{rcaccess}{$tty};
    if (defined $mask) {
        print sprintf("RCACCESS TTY=\"%s\" ACCESS=H'%s'\n", $tty, $mask);
        result_ok($session, 'RCACCESS READ');
    } else {
        result_ng($session, 'NO SUCH TTY');
    }
}

sub handle_set_rcaccess {
    my ($session, $tty, $mask) = @_;
    $state->{rcaccess}{$tty} = uc $mask;
    Persist::append_journal({
        type => 'rcaccess_set',
        tty  => $tty,
        mask => uc $mask,
    });
    $scc->log_event("SCC RCACCESS UPDATE TTY=$tty ACCESS=H'$mask'");
    result_ok($session, 'RCACCESS UPDATED');
}

sub handle_op_clerk {
    my ($session) = @_;
    my $clerk = $session->{clerk_id} // 'NONE';
    print "CLERK ID=\"$clerk\" CHANNEL=$session->{channel} PRIV=$session->{role}\n";
    result_ok($session, 'CLERK DISPLAYED');
}

sub handle_mcc_guide {
    my ($session) = @_;
    print "\n--- MCC PAGE LOCATION GUIDE (STUB) ---\n";
    print "USE MCC:SHOW <PAGE> TO DISPLAY A PAGE.\n";
    print "KNOWN PAGES: 1000, 105, 110\n";
    result_ok($session, 'MCC GUIDE');
}

sub handle_mcc_show {
    my ($session, $page) = @_;
    my %mcc_pages = (
        '1000' => {
            title => 'MCC PAGE INDEX',
            body  => [
                '105  SYSTEM STATUS SUMMARY',
                '110  SWITCH ENVIRONMENT',
                '115  CM2 STATUS',
                '116  CM2 ALARMS',
                '123  NETWORK OVERVIEW',
                '125  TRUNK SUMMARY',
                '1800X PROCESSOR STATUS',
                '1850  RECENT-CHANGE ACTIVITY',
                '1851  VERIFICATION SUMMARY',
            ],
        },
        '105' => {
            title => 'SYSTEM STATUS SUMMARY',
            body  => [
                'SM02  OK',
                'SM03  OK',
                'PWR   MINOR (BATTERY DISCHARGE 50.9 V)',
                'ALM   MAJOR (HIGH-BIT-ERROR-RATE)',
            ],
        },
        '110' => {
            title => 'SWITCH ENVIRONMENT',
            body  => [
                'TEMP  72F',
                'HUM   45%',
                'PWR   53.1V',
                'FANS  OK',
            ],
        },
    );
    $page ||= '';
    $page =~ s/^\s+|\s+$//g;
    unless ($page && exists $mcc_pages{$page}) {
        error_out($session, 'ILL FORM');
        return;
    }
    my $entry = $mcc_pages{$page};
    my $output = "\n--- MCC PAGE $page: $entry->{title} ---\n";
    $output .= join("\n", @{ $entry->{body} }) . "\n";
    $ui->pager($output);
    result_ok($session, 'MCC PAGE DISPLAYED');
}

sub handle_rclog {
    my ($session, $count) = @_;
    $count ||= 20;
    my $path = Persist::journal_path();
    unless (-e $path) {
        result_ng($session, 'NO JOURNAL');
        return;
    }
    open my $fh, '<', $path or do {
        result_ng($session, 'JOURNAL READ FAILED');
        return;
    };
    my @lines = <$fh>;
    close $fh;
    my @tail;
    if (@lines <= $count) {
        @tail = @lines;
    } elsif (@lines) {
        @tail = @lines[-$count .. -1];
    }
    my $output = "--- DMERT JOURNAL (LAST $count) ---\n" . join('', @tail);
    $ui->pager($output);
    result_ok($session, 'JOURNAL DISPLAYED');
}

sub handle_save {
    my ($session) = @_;
    Persist::save_snapshot($state, 'manual');
    result_ok($session, 'SNAPSHOT SAVED');
}

sub handle_reload {
    my ($session) = @_;
    $state = Persist::default_state();
    Persist::replay_journal(sub { apply_event($state, shift) });
    $alarms = Alarms->new($state);
    $scc = SCC->new($state);
    result_ok($session, 'STATE RELOADED');
}

sub handle_line_station_menu {
    my ($session) = @_;
    return result_ng($session, 'CHANNEL RESTRICTED') unless channel_allows_rc_changes($session);
    return result_ng($session, 'CLERK LOGIN REQUIRED') unless clerk_allows_changes($session);
    return result_ng($session, 'RCACCESS DENIED') unless rcaccess_allows_changes($session);

    print "\n[1.11] LINE ASSIGNMENT – TERMINAL #, CABLE-PAIR, COS, TYPE, CLASS, FEATURES\n";

    print "TERMINAL? ";
    my $term = <STDIN>; chomp $term; $term =~ s/^\s+|\s+$//g;
    return result_ng($session, 'TERM REQUIRED') unless $term;

    print "CABLE-PAIR? ";
    my $pair = <STDIN>; chomp $pair; $pair =~ s/^\s+|\s+$//g;

    print "CLASS OF SERVICE (E.G. POTS, ISDN)? ";
    my $cos = <STDIN>; chomp $cos; $cos =~ s/^\s+|\s+$//g;

    print "LINE TYPE (E.G. 1FR, 1TR, ISDN)? ";
    my $linetype = <STDIN>; chomp $linetype; $linetype =~ s/^\s+|\s+$//g;

    print "LINE CLASS (E.G. RES, BUS)? ";
    my $lineclass = <STDIN>; chomp $lineclass; $lineclass =~ s/^\s+|\s+$//g;

    print "FEATURES (COMMA-SEPARATED, E.G. CALLWAIT, 3WAY)? ";
    my $features = <STDIN>; chomp $features; $features =~ s/^\s+|\s+$//g;

    $state->{lines}{$term} = {
        pair     => $pair,
        cos      => $cos,
        dn       => undef,
        linetype => $linetype,
        class    => $lineclass,
        features => $features,
    };

    Persist::append_journal({
        type => 'line_set',
        term => $term,
        line => $state->{lines}{$term},
    });
    $scc->log_event("SCC LINE CREATED TERM=$term");
    result_ok($session, "LINE $term CREATED");
}

sub handle_directory_number_menu {
    my ($session) = @_;
    return result_ng($session, 'CHANNEL RESTRICTED') unless channel_allows_rc_changes($session);
    return result_ng($session, 'CLERK LOGIN REQUIRED') unless clerk_allows_changes($session);
    return result_ng($session, 'RCACCESS DENIED') unless rcaccess_allows_changes($session);

    print "\n[8.12] ASSIGN DIRECTORY NUMBER – ENTER DN & TERMINAL #\n";
    print "DN? ";
    my $dn = <STDIN>; chomp $dn; $dn =~ s/^\s+|\s+$//g;
    return result_ng($session, 'DN REQUIRED') unless $dn;

    print "TERMINAL? ";
    my $term = <STDIN>; chomp $term; $term =~ s/^\s+|\s+$//g;

    unless (exists $state->{lines}{$term}) {
        error_out($session, 'DATA ERROR');
        return;
    }

    $state->{lines}{$term}{dn} = $dn;
    $state->{dns}{$dn} = $term;
    Persist::append_journal({
        type => 'dn_set',
        dn   => $dn,
        term => $term,
    });
    $scc->log_event("SCC DN ASSIGNED DN=$dn TERM=$term");
    result_ok($session, "DN $dn ASSIGNED");
}

sub handle_verify_menu {
    my ($session) = @_;
    my $output = "\n--- TRANSLATION DATABASE DUMP ---\n";
    for my $term (sort keys %{ $state->{lines} }) {
        my $rec = $state->{lines}{$term};
        $output .= sprintf(
            "TERM %-6s DN %-10s COS %-8s TYPE %-6s CLASS %-5s FEAT [%-10s] CABLE %s\n",
            $term,
            ($rec->{dn} // '---------'),
            ($rec->{cos} // ''),
            ($rec->{linetype} // ''),
            ($rec->{class} // ''),
            ($rec->{features} // ''),
            ($rec->{pair} // ''),
        );
    }
    $ui->pager($output);
    result_ok($session, 'VERIFY COMPLETE');
}

sub handle_rcv_open {
    my ($session, $tkt) = @_;
    my $rcv = RCV->new($state, $session->{channel});
    my ($ok, $msg) = $rcv->open_ticket($tkt);
    if ($ok) {
        Persist::append_journal({
            type      => 'rcv_open',
            channel   => $session->{channel},
            ticket_id => $tkt,
            opened_at => now_stamp(),
        });
        result_ok($session, $msg);
    } else {
        result_ng($session, $msg);
    }
}

sub handle_rcv_add {
    my ($session, $key, $value) = @_;
    my $rcv = RCV->new($state, $session->{channel});
    my ($ok, $msg) = $rcv->add_change($key, $value);
    if ($ok) {
        Persist::append_journal({
            type    => 'rcv_add',
            channel => $session->{channel},
            key     => $key,
            value   => $value,
        });
        result_ok($session, $msg);
    } else {
        result_ng($session, $msg);
    }
}

sub handle_rcv_check {
    my ($session) = @_;
    my $rcv = RCV->new($state, $session->{channel});
    my ($ok, $msg) = $rcv->check_ticket($state->{lines});
    if ($ok) {
        result_ok($session, $msg);
    } else {
        error_out($session, 'DATA ERROR');
        print "DETAIL: $msg\n";
    }
}

sub handle_rcv_abort {
    my ($session) = @_;
    my $rcv = RCV->new($state, $session->{channel});
    my ($ok, $msg) = $rcv->abort_ticket();
    if ($ok) {
        Persist::append_journal({
            type    => 'rcv_abort',
            channel => $session->{channel},
        });
        result_ok($session, $msg);
    } else {
        result_ng($session, $msg);
    }
}

sub handle_rcv_commit {
    my ($session) = @_;
    return result_ng($session, 'CHANNEL RESTRICTED') unless channel_allows_rc_changes($session);
    return result_ng($session, 'CLERK LOGIN REQUIRED') unless clerk_allows_changes($session);
    return result_ng($session, 'RCACCESS DENIED') unless rcaccess_allows_changes($session);
    unless (has_second_auth($session)) {
        record_unauth($state);
        return error_out($session, 'NOT AUTH');
    }

    my $rcv = RCV->new($state, $session->{channel});
    my ($ok, $msg, $ticket_id, $payload, $changes) = $rcv->commit_ticket($state->{lines}, $state->{dns});
    if ($ok) {
        maybe_latency('RCV_COMMIT');
        Persist::append_journal({
            type    => 'rcv_commit',
            channel => $session->{channel},
            ticket  => $ticket_id,
            changes => $changes || {},
            applied => $payload,
        });
        $scc->log_event("RCV COMMIT TKT=$ticket_id TERM=$payload->{term}");
        consume_second_auth($session);
        result_ok($session, "RCV COMMIT $ticket_id");
    } else {
        result_ng($session, $msg);
    }
}

sub handle_alm_ack {
    my ($session, $id) = @_;
    my $alarm = $alarms->find_alarm($id);
    unless ($alarm) {
        error_out($session, 'DATA ERROR');
        return;
    }
    $alarms->ack_alarm($alarm);
    Persist::append_journal({ type => 'alarm_ack', id => $id });
    result_ok($session, "ALARM $id ACKED");
}

sub handle_alm_clear {
    my ($session, $id) = @_;
    my $alarm = $alarms->find_alarm($id);
    unless ($alarm) {
        error_out($session, 'DATA ERROR');
        return;
    }
    $alarms->clear_alarm($alarm);
    Persist::append_journal({
        type         => 'alarm_clear',
        id           => $id,
        cleared_time => $alarm->{cleared_time},
    });
    result_ok($session, "ALARM $id CLEARED");
}

sub handle_alm_raise {
    my ($session, $sev, $source, $text) = @_;
    if (($session->{role} // '') ne 'ADMIN' && !has_second_auth($session)) {
        record_unauth($state);
        error_out($session, 'NOT AUTH');
        return;
    }
    my $alarm = $alarms->raise_alarm(
        severity => $sev,
        source   => $source,
        text     => $text,
    );
    Persist::append_journal({ type => 'alarm_raise', alarm => $alarm });
    consume_second_auth($session) if has_second_auth($session);
    result_ok($session, "ALARM $alarm->{id} RAISED");
}

sub handle_scc_submit {
    my ($session, $job, $parm) = @_;
    maybe_latency('SCC_SUBMIT');
    my $job_entry = $scc->submit_job($job, $parm);
    Persist::append_journal({ type => 'scc_submit', job => $job_entry });
    $scc->log_event("SCC JOB $job_entry->{id} SUBMITTED $job");
    result_ok($session, "JOB $job_entry->{id} QUEUED");
}

sub handle_scc_stat {
    my ($session) = @_;
    my $counts = $scc->stats();
    print "SCC STATUS: QUEUED=$counts->{QUEUED} RUNNING=$counts->{RUNNING} DONE=$counts->{DONE}\n";
    print "RECENT JOBS:\n";
    for my $job (@{ $scc->recent_jobs(5) }) {
        printf "JOB %-4d %-8s %-7s SUBMIT %s\n",
            $job->{id}, $job->{status}, $job->{name}, $job->{submitted};
    }
    result_ok($session, 'SCC STATUS');
}

sub handle_scc_out {
    my ($session, $jobid) = @_;
    my $job = $scc->find_job($jobid);
    unless ($job) {
        error_out($session, 'DATA ERROR');
        return;
    }
    my $output = "--- SCC OUTPUT JOB $jobid ---\n" . join("\n", @{ $job->{output} }) . "\n";
    $ui->pager($output);
    result_ok($session, 'SCC OUTPUT');
}

sub dispatch_craft_command {
    my ($session, $cmd) = @_;
    if ($cmd =~ /^RCV:MENU:APPRC\b/i || $cmd =~ /^RCV\b/i) {
        return error_out($session, 'INHIBITED') unless channel_allows_rc_changes($session);
        $session->{mode} = 'RCV_MENU';
        print "\n--- 5ESS RECENT-CHANGE/VERIFY ---\n";
        print " 1 LINE/STATION  8 DIRECTORY-NUMBER  0 VERIFY  Q QUIT\n";
        result_ok($session, 'MODE RCV');
        return;
    }
    if ($cmd =~ /^ALM:LIST;?$/i) {
        handle_alm_list($session);
        return;
    }
    if ($cmd =~ /^ALM:ACK,(\d+);?$/i) {
        handle_alm_ack($session, $1);
        return;
    }
    if ($cmd =~ /^ALM:CLEAR,(\d+);?$/i) {
        handle_alm_clear($session, $1);
        return;
    }
    if ($cmd =~ /^ALM:RAISE,([A-Z]{2}),([^,]+),(.+);?$/i) {
        handle_alm_raise($session, uc($1), $2, $3);
        return;
    }
    if ($cmd =~ /^MCC:GUIDE;?$/i) {
        handle_mcc_guide($session);
        return;
    }
    if ($cmd =~ /^MCC:SHOW\s+(\S+);?$/i) {
        handle_mcc_show($session, $1);
        return;
    }
    if ($cmd =~ /^OP:RCACCESS,TTY="([^"]+)"\s*;?$/i) {
        handle_op_rcaccess($session, $1);
        return;
    }
    if ($cmd =~ /^OP:CLERK\s*;?$/i) {
        handle_op_clerk($session);
        return;
    }
    if ($cmd =~ /^SET:RCACCESS,TTY="([^"]+)",ACCESS=H'([0-9A-Fa-f]{5})'\s*;?$/i) {
        if (($session->{role} // '') ne 'ADMIN') {
            record_unauth($state);
            error_out($session, 'NOT AUTH');
        } else {
            handle_set_rcaccess($session, $1, $2);
        }
        return;
    }
    if ($cmd =~ /^REQ:AUTH,CLRK="([^"]+)";?$/i) {
        my ($ok, $msg) = grant_second_auth($session, $1);
        $ok ? result_ok($session, $msg) : result_ng($session, $msg);
        return;
    }
    if ($cmd =~ /^RCV:OPEN,TKT="([^"]+)";?$/i) {
        handle_rcv_open($session, $1);
        return;
    }
    if ($cmd =~ /^RCV:ADD,([A-Z0-9_]+)=(.+);?$/i) {
        handle_rcv_add($session, uc($1), $2);
        return;
    }
    if ($cmd =~ /^RCV:CHECK;?$/i) {
        handle_rcv_check($session);
        return;
    }
    if ($cmd =~ /^RCV:COMMIT;?$/i) {
        handle_rcv_commit($session);
        return;
    }
    if ($cmd =~ /^RCV:ABORT;?$/i) {
        handle_rcv_abort($session);
        return;
    }
    if ($cmd =~ m{^/rclog\s*(\d+)?$}i) {
        handle_rclog($session, $1);
        return;
    }
    if ($cmd =~ m{^/save$}i) {
        handle_save($session);
        return;
    }
    if ($cmd =~ m{^/reload$}i) {
        handle_reload($session);
        return;
    }
    if ($cmd =~ /^HELP$/i) {
        print "\nAVAILABLE COMMANDS: RCV:MENU:APPRC  ALM:LIST  ALM:ACK  ALM:CLEAR  ALM:RAISE\n";
        print "MCC:GUIDE  MCC:SHOW  OP:CLERK  OP:RCACCESS  SET:RCACCESS  REQ:AUTH\n";
        print "RCV:OPEN/ADD/CHECK/COMMIT/ABORT  /rclog /save /reload  QUIT\n";
        result_ok($session, 'HELP');
        return;
    }
    error_out($session, 'TRYPT LTR');
}

sub dispatch_rcv_menu {
    my ($session, $cmd) = @_;
    if ($cmd =~ /^RCV:MENU:SH!\b/i || $cmd =~ /^Q$/i) {
        $session->{mode} = 'CRAFT';
        result_ok($session, 'MODE CRAFT');
        return;
    }
    if ($cmd =~ /^1$/) {
        handle_line_station_menu($session);
        return;
    }
    if ($cmd =~ /^8$/) {
        handle_directory_number_menu($session);
        return;
    }
    if ($cmd =~ /^0$/) {
        handle_verify_menu($session);
        return;
    }
    if ($cmd =~ /^ALM:LIST;?$/i) {
        handle_alm_list($session);
        return;
    }
    if ($cmd =~ /^OP:RCACCESS,TTY="([^"]+)"\s*;?$/i) {
        handle_op_rcaccess($session, $1);
        return;
    }
    if ($cmd =~ /^OP:CLERK\s*;?$/i) {
        handle_op_clerk($session);
        return;
    }
    if ($cmd =~ /^SET:RCACCESS,TTY="([^"]+)",ACCESS=H'([0-9A-Fa-f]{5})'\s*;?$/i) {
        if (($session->{role} // '') ne 'ADMIN') {
            record_unauth($state);
            error_out($session, 'NOT AUTH');
        } else {
            handle_set_rcaccess($session, $1, $2);
        }
        return;
    }
    if ($cmd =~ /^RCV:OPEN,TKT="([^"]+)";?$/i) {
        handle_rcv_open($session, $1);
        return;
    }
    if ($cmd =~ /^RCV:ADD,([A-Z0-9_]+)=(.+);?$/i) {
        handle_rcv_add($session, uc($1), $2);
        return;
    }
    if ($cmd =~ /^RCV:CHECK;?$/i) {
        handle_rcv_check($session);
        return;
    }
    if ($cmd =~ /^RCV:COMMIT;?$/i) {
        handle_rcv_commit($session);
        return;
    }
    if ($cmd =~ /^RCV:ABORT;?$/i) {
        handle_rcv_abort($session);
        return;
    }
    error_out($session, 'ILL FORM');
}

sub dispatch_scc {
    my ($session, $cmd) = @_;
    if ($cmd =~ /^ALM:LIST;?$/i) {
        handle_alm_list($session);
        print "$_\n" for $scc->emit_lines();
        return;
    }
    if ($cmd =~ /^SCC:SUBMIT,JOB="([^"]+)",PARM="([^"]*)";?$/i) {
        handle_scc_submit($session, $1, $2);
        print "$_\n" for $scc->emit_lines();
        return;
    }
    if ($cmd =~ /^SCC:STAT;?$/i) {
        handle_scc_stat($session);
        print "$_\n" for $scc->emit_lines();
        return;
    }
    if ($cmd =~ /^SCC:OUT,JOBID=(\d+);?$/i) {
        handle_scc_out($session, $1);
        print "$_\n" for $scc->emit_lines();
        return;
    }
    if ($cmd =~ /^REQ:AUTH,CLRK="([^"]+)";?$/i) {
        my ($ok, $msg) = grant_second_auth($session, $1);
        $ok ? result_ok($session, $msg) : result_ng($session, $msg);
        return;
    }
    if ($cmd =~ m{^/rclog\s*(\d+)?$}i) {
        handle_rclog($session, $1);
        return;
    }
    if ($cmd =~ m{^/save$}i) {
        handle_save($session);
        return;
    }
    if ($cmd =~ m{^/reload$}i) {
        handle_reload($session);
        return;
    }
    print "(STUB) SCC COMMAND IGNORED\n";
    print "$_\n" for $scc->emit_lines();
    result_ok($session, 'SCC NO-OP');
}

sub main_loop {
    my ($session) = @_;
    while (1) {
        decay_unauth($state);
        my @async = $scc->tick();
        print "$_\n" for @async;
        $ui->draw_status_line(status_text($session));
        print session_prompt($session);

        my $cmd = <STDIN>;
        last unless defined $cmd;
        chomp $cmd;
        $cmd =~ s/^\s+|\s+$//g;
        $session->{seq}++;

        if ($cmd eq '') {
            set_last_error($session, 'OK', '');
            next;
        }

        if ($cmd =~ /^QUIT$/i) {
            print "RESULT: OK - LOGOUT COMPLETE\n";
            last;
        }

        if (require_semicolon($session, $cmd)) {
            error_out($session, 'ILL FORM');
            next;
        }

        if ($session->{mode} eq 'CRAFT') {
            dispatch_craft_command($session, $cmd);
        } elsif ($session->{mode} eq 'RCV_MENU') {
            dispatch_rcv_menu($session, $cmd);
        } else {
            dispatch_scc($session, $cmd);
        }

        update_derived_alarms($state);
        $ui->draw_status_line(status_text($session));
    }
}

print_banner();

my $channel = select_channel();
my ($clerk_id, $role) = clerk_login($channel);
my $session = session_create($channel, $clerk_id, $role);

my $rc_inhibit = (!channel_allows_rc_changes($session) || !rcaccess_allows_changes($session)) ? 'YES' : 'NO';
print "\nPRIVILEGE CLASS: $role\n";
print "RECENT CHANGE INHIBITED: $rc_inhibit\n\n";

print "* * *  5ESS CRAFT SHELL (SIM)  * * *\nTYPE HELP FOR COMMAND LIST.\n\n";

main_loop($session);
