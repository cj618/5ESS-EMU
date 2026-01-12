package Alarms;

use strict;
use warnings;
use Persist;

sub new {
    my ($class, $state) = @_;
    return bless { state => $state }, $class;
}

sub _next_id {
    my ($self) = @_;
    my $id = $self->{state}{next_alarm_id} || 1;
    $self->{state}{next_alarm_id} = $id + 1;
    return $id;
}

sub list_active {
    my ($self) = @_;
    return [ grep { !defined $_->{cleared_time} } @{ $self->{state}{alarms} } ];
}

sub find_alarm {
    my ($self, $id) = @_;
    return undef unless defined $id;
    for my $alarm (@{ $self->{state}{alarms} }) {
        return $alarm if $alarm->{id} == $id;
    }
    return undef;
}

sub raise_alarm {
    my ($self, %opts) = @_;
    my $alarm = {
        id           => $self->_next_id(),
        severity     => $opts{severity} || 'MN',
        raised_time  => $opts{raised_time} || Persist::now_stamp(),
        cleared_time => undef,
        ack_state    => 'UNACK',
        source       => $opts{source} || 'SYS',
        text         => $opts{text} || 'ALARM',
    };
    push @{ $self->{state}{alarms} }, $alarm;
    return $alarm;
}

sub ack_alarm {
    my ($self, $alarm) = @_;
    return unless $alarm;
    $alarm->{ack_state} = 'ACK';
}

sub clear_alarm {
    my ($self, $alarm) = @_;
    return unless $alarm;
    $alarm->{cleared_time} = Persist::now_stamp();
}

sub ensure_alarm {
    my ($self, $key, %opts) = @_;
    my ($existing) = grep {
        $_->{source} eq $key && !defined $_->{cleared_time}
    } @{ $self->{state}{alarms} };
    return $existing if $existing;
    return $self->raise_alarm(source => $key, %opts);
}

sub clear_by_source {
    my ($self, $source) = @_;
    for my $alarm (@{ $self->{state}{alarms} }) {
        next unless $alarm->{source} eq $source;
        next if defined $alarm->{cleared_time};
        $alarm->{cleared_time} = Persist::now_stamp();
    }
}

1;
