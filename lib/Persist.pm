package Persist;

use strict;
use warnings;
use JSON::PP;
use File::Path qw(make_path);

sub now_stamp {
    my @t = localtime();
    return sprintf "%04d-%02d-%02d %02d:%02d:%02d",
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0];
}

sub base_dir {
    return $ENV{5ESS_STATE_DIR} || $ENV{5ESS_VAR} || './var';
}

sub journal_path {
    return base_dir() . '/dmert.journal';
}

sub snapshot_path {
    return base_dir() . '/state.json';
}

sub ensure_dir {
    my $dir = base_dir();
    make_path($dir) unless -d $dir;
}

sub default_state {
    return {
        lines        => {},
        dns          => {},
        alarms       => [],
        rcaccess     => {
            ttyV => 'FFFFF',
            ttyW => 'FFFFF',
        },
        clerks       => {},
        batch_queue  => [],
        scc_log      => [],
        rcv_sessions => {},
        unauth       => {
            count     => 0,
            last_time => undef,
        },
        next_alarm_id => 1,
        next_job_id   => 1,
    };
}

sub append_journal {
    my ($event) = @_;
    ensure_dir();
    my $path = journal_path();
    open my $fh, '>>', $path or return;
    my $json = JSON::PP->new->utf8->encode($event);
    print {$fh} now_stamp() . "\t" . $json . "\n";
    close $fh;
}

sub save_snapshot {
    my ($state, $reason) = @_;
    ensure_dir();
    my $path = snapshot_path();
    my $tmp = $path . '.tmp';
    my $json = JSON::PP->new->utf8->pretty(1)->encode($state);
    open my $fh, '>', $tmp or die "Unable to write $tmp: $!";
    print {$fh} $json;
    close $fh;
    rename $tmp, $path or die "Unable to replace $path: $!";
    append_journal({ type => 'snapshot', reason => ($reason // 'manual') });
}

sub load_snapshot {
    my $path = snapshot_path();
    return unless -e $path;
    open my $fh, '<', $path or return;
    local $/;
    my $json = <$fh>;
    close $fh;
    my $data = eval { JSON::PP->new->utf8->decode($json) };
    return $data if $data && ref $data eq 'HASH';
    return;
}

sub replay_journal {
    my ($apply_cb) = @_;
    my $path = journal_path();
    return unless -e $path;
    open my $fh, '<', $path or return;
    while (my $line = <$fh>) {
        chomp $line;
        my ($ts, $json) = split(/\t/, $line, 2);
        next unless $json;
        my $event = eval { JSON::PP->new->utf8->decode($json) };
        next unless $event && ref $event eq 'HASH';
        $event->{_ts} = $ts;
        $apply_cb->($event) if $apply_cb;
    }
    close $fh;
}

1;
