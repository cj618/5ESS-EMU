#!/usr/bin/perl
use strict;
use warnings;

# -----------------------------------------------------------------------------
# 5ESS Craft‑Shell & RC/V miniature emulator (educational use)
# -----------------------------------------------------------------------------
# C R Jervis – starter template, April 2025
# Emulates a tiny subset of the AT&T 5ESS craft environment so you can get the
# “feel” of moving between the shell prompt and the Recent‑Change/Verify menu.
# -----------------------------------------------------------------------------

# In‑memory data structures ----------------------------------------------------
my %lines;         # key = terminal number, value = hashref of line data
my %dns;           # key = directory number, value = terminal number
my @alarms;        # array of outstanding alarm strings

# Seed some demo alarms
push @alarms, 'MINOR  SM02  High‑Bit‑Error‑Rate';
push @alarms, 'MAJOR  PWR   Battery discharge 53.1 V → 50.9 V';

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
        if ($cmd =~ /^HELP$/i) {
            print "\nAvailable commands: RCV   ALM:LIST   HELP   QUIT\n";
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
    print "\n[1.11] Line Assignment – enter Terminal #, Cable‑Pair, Class of Service\n";
    print "TERMINAL? ";
    my $term = <STDIN>; chomp $term; $term =~ s/^\s+|\s+$//g;
    return unless $term;

    print "CABLE‑PAIR? ";
    my $pair = <STDIN>; chomp $pair; $pair =~ s/^\s+|\s+$//g;

    print "CLASS OF SERVICE (e.g. POTS, ISDN)? ";
    my $cos = <STDIN>; chomp $cos; $cos =~ s/^\s+|\s+$//g;

    $lines{$term} = { pair => $pair, cos => $cos, dn => undef };
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
        printf "TERM %-6s DN %-10s COS %-8s CABLE %s\n",
            $term,
            ($rec->{dn} // '‑‑‑‑‑‑‑‑‑'),
            $rec->{cos},
            $rec->{pair};
    }
}

# -----------------------------------------------------------------------------
print "\n* * *  5ESS Craft Shell (sim)  * * *\nType HELP for command list.\n\n";

shell();
