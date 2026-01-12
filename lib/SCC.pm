package SCC;

use strict;
use warnings;
use Persist;

sub new {
    my ($class, $state) = @_;
    $state->{batch_queue} ||= [];
    $state->{scc_log} ||= [];
    return bless { state => $state }, $class;
}

sub next_job_id {
    my ($self) = @_;
    my $id = $self->{state}{next_job_id} || 1;
    $self->{state}{next_job_id} = $id + 1;
    return $id;
}

sub submit_job {
    my ($self, $name, $parm) = @_;
    my $job = {
        id         => $self->next_job_id(),
        name       => $name,
        parm       => $parm,
        status     => 'QUEUED',
        submitted  => Persist::now_stamp(),
        started_at => undef,
        done_at    => undef,
        output     => [],
        duration_s => 2 + int(rand(3)),
    };
    push @{ $self->{state}{batch_queue} }, $job;
    return $job;
}

sub tick {
    my ($self) = @_;
    my @async;
    my $has_running = 0;
    for my $job (@{ $self->{state}{batch_queue} }) {
        if ($job->{status} eq 'RUNNING') {
            $has_running = 1;
            last;
        }
    }
    if (!$has_running) {
        for my $job (@{ $self->{state}{batch_queue} }) {
            if ($job->{status} eq 'QUEUED') {
                $job->{status} = 'RUNNING';
                $job->{started_at} = Persist::now_stamp();
                push @{ $job->{output} }, "JOB $job->{id} STARTED";
                last;
            }
        }
    }
    for my $job (@{ $self->{state}{batch_queue} }) {
        next unless $job->{status} eq 'RUNNING';
        $job->{duration_s}-- if $job->{duration_s} > 0;
        if ($job->{duration_s} <= 0) {
            $job->{status} = 'DONE';
            $job->{done_at} = Persist::now_stamp();
            push @{ $job->{output} }, "JOB $job->{id} COMPLETE";
            push @async, "SCC: JOB $job->{id} COMPLETE";
        }
        last;
    }
    return @async;
}

sub stats {
    my ($self) = @_;
    my %counts = (QUEUED => 0, RUNNING => 0, DONE => 0);
    for my $job (@{ $self->{state}{batch_queue} }) {
        $counts{ $job->{status} }++ if exists $counts{ $job->{status} };
    }
    return \%counts;
}

sub recent_jobs {
    my ($self, $limit) = @_;
    $limit ||= 5;
    my @jobs = reverse @{ $self->{state}{batch_queue} };
    return [ splice(@jobs, 0, $limit) ];
}

sub find_job {
    my ($self, $job_id) = @_;
    for my $job (@{ $self->{state}{batch_queue} }) {
        return $job if $job->{id} == $job_id;
    }
    return undef;
}

sub log_event {
    my ($self, $text, $limit) = @_;
    $limit ||= 60;
    my $line = Persist::now_stamp() . " $text";
    push @{ $self->{state}{scc_log} }, $line;
    shift @{ $self->{state}{scc_log} } while @{ $self->{state}{scc_log} } > $limit;
}

sub emit_lines {
    my ($self) = @_;
    my $count = int(rand(4));
    $count = @{ $self->{state}{scc_log} } if $count > @{ $self->{state}{scc_log} };
    my @lines;
    for (1 .. $count) {
        my $line = shift @{ $self->{state}{scc_log} };
        push @lines, $line if defined $line;
    }
    return @lines;
}

1;
