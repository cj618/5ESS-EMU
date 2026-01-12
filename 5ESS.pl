#!/usr/bin/perl

use strict;
use warnings;

# -----------------------------------------------------------------------------
# 5ESS AT&T craft environment miniature emulator
# -----------------------------------------------------------------------------
# Copyright (c) 2025, 2026 C R Jervis under the terms outlined in LICENSE document.
# Based on documentation that is Copyright (c) 1984 - 1991 AT&T.
#
# 5ESS is a registered trademark of Lucent Technologies, Inc.
#
#
# -----------------------------------------------------------------------------

# In‑memory data structures 
my %lines;         # key = terminal number, value = hashref of line data
my %dns;           # key = directory number, value = terminal number
my @alarms;        # array of outstanding alarm strings

# Seed some demo alarms
push @alarms, 'MINOR  SM02  High‑Bit‑Error‑Rate';
push @alarms, 'MAJOR  PWR   Battery discharge 53.1 V → 50.9 V';

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
sub prompt {
    print "CRAFT> ";
}

sub shell {
    while (1) {
        prompt();
        my $cmd = <STDIN> // '';
        chomp $cmd;
        $cmd =~ s/^\s+|\s+$//g;
        next unless $cmd;

        if ($cmd =~ /^RCV?:?$/i) {
            rcv_menu();
            next;
        }
        if ($cmd =~ /^ALM:LIST:?/i) {
            print "\n=== Outstanding Alarms ===\n";
            print "$_\n" for @alarms;
            next;
        }
            if ($cmd =~ /^MCC:GUIDE:?$/i) {
            mcc_location_guide();
            next;
        }
        if ($cmd =~ /^MCC:SHOW\s+(\S+)$/i) {
            mcc_show_page($1);
            next;
        }

        if ($cmd =~ /^HELP$/i) {
            print "\nAvailable commands: RCV   ALM:LIST   MCC:GUIDE   MCC:SHOW <page>   HELP   QUIT\n";
            next;
        }
        if ($cmd =~ /^QUIT$/i) {
            print "Logout complete – have a good one.\n";
            last;
        }
        print "? Unrecognised command – type HELP for options.\n";
    }
}

sub rcv_menu {
    while (1) {
        print "\n--- 5ESS Recent‑Change/Verify ---\n";
        print " 1 Line/Station  8 Directory‑Number  0 Verify  Q Quit\n";
        print "MENU? ";
        my $sel = <STDIN> // '';
        chomp $sel;
        $sel =~ s/^\s+|\s+$//g;
        if ($sel eq '1') {
            line_station_menu();
            next;
        }
        if ($sel eq '8') {
            directory_number_menu();
            next;
        }
        if ($sel eq '0') {
            verify_menu();
            next;
        }
        last if uc $sel eq 'Q';
        print "? Invalid selection\n";
    }
}

sub line_station_menu {
    print "\n[1.11] Line Assignment – Terminal #, Cable-Pair, COS, Type, Class, Features\n";

    print "TERMINAL? ";
    my $term = <STDIN>; chomp $term; $term =~ s/^\s+|\s+$//g;
    return unless $term;

    print "CABLE‑PAIR? ";
    my $pair = <STDIN>; chomp $pair; $pair =~ s/^\s+|\s+$//g;

    print "CLASS OF SERVICE (e.g. POTS, ISDN)? ";
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
    
    print "\nRECENT CHANGE COMPLETED – terminal $term ready.\n";
}

sub directory_number_menu {
    print "\n[8.12] Assign Directory Number – enter DN & Terminal #\n";
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

# print login motd for simulation purposes

print "\n";
open my $fh, '<', './etc/motd.dat' or die $!;
print while <$fh>;

# now drop the user into the shell

print "\n* * *  5ESS Craft Shell (sim)  * * *\nType HELP for command list.\n\n";

shell();
