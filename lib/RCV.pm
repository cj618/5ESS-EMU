package RCV;

use strict;
use warnings;
use Persist;

sub new {
    my ($class, $state, $channel) = @_;
    $state->{rcv_sessions} ||= {};
    $state->{rcv_sessions}{$channel} ||= {
        ticket_id => undef,
        opened_at => undef,
        changes   => {},
    };
    return bless { state => $state, channel => $channel }, $class;
}

sub session_state {
    my ($self) = @_;
    return $self->{state}{rcv_sessions}{ $self->{channel} };
}

sub open_ticket {
    my ($self, $ticket_id) = @_;
    my $rcv = $self->session_state();
    return (0, 'TICKET ALREADY OPEN') if $rcv->{ticket_id};
    $rcv->{ticket_id} = $ticket_id;
    $rcv->{opened_at} = Persist::now_stamp();
    $rcv->{changes}   = {};
    return (1, 'TICKET OPENED');
}

sub add_change {
    my ($self, $key, $value) = @_;
    my $rcv = $self->session_state();
    return (0, 'NO OPEN TICKET') unless $rcv->{ticket_id};
    $rcv->{changes}{$key} = $value;
    return (1, 'CHANGE STAGED');
}

sub abort_ticket {
    my ($self) = @_;
    my $rcv = $self->session_state();
    return (0, 'NO OPEN TICKET') unless $rcv->{ticket_id};
    $rcv->{ticket_id} = undef;
    $rcv->{opened_at} = undef;
    $rcv->{changes}   = {};
    return (1, 'TICKET ABORTED');
}

sub check_ticket {
    my ($self, $lines_ref) = @_;
    my $rcv = $self->session_state();
    return (0, 'NO OPEN TICKET') unless $rcv->{ticket_id};
    my %c = %{ $rcv->{changes} };
    my @errors;
    push @errors, 'TERM REQUIRED' unless $c{TERM};
    if ($c{DN} && !$c{TERM}) {
        push @errors, 'DN REQUIRES TERM';
    }
    if ($c{TERM} && !exists $lines_ref->{ $c{TERM} }) {
        my @needed = grep { !$c{$_} } qw(PAIR COS LINETYPE CLASS);
        if (@needed) {
            push @errors, 'NEW LINE MISSING ' . join(',', @needed);
        }
    }
    return (0, join('; ', @errors)) if @errors;
    return (1, 'VALIDATION OK');
}

sub commit_ticket {
    my ($self, $lines_ref, $dns_ref) = @_;
    my $rcv = $self->session_state();
    return (0, 'NO OPEN TICKET') unless $rcv->{ticket_id};
    my %c = %{ $rcv->{changes} };
    return (0, 'TERM REQUIRED') unless $c{TERM};

    my $term = $c{TERM};
    my $line = $lines_ref->{$term} || {};
    for my $field (qw(PAIR COS LINETYPE CLASS FEATURES)) {
        $line->{ lc($field) } = $c{$field} if defined $c{$field};
    }
    $lines_ref->{$term} = $line;
    if ($c{DN}) {
        $line->{dn} = $c{DN};
        $dns_ref->{ $c{DN} } = $term;
    }

    my $ticket_id = $rcv->{ticket_id};
    $rcv->{ticket_id} = undef;
    $rcv->{opened_at} = undef;
    $rcv->{changes}   = {};

    return (1, 'TICKET COMMITTED', $ticket_id,
        { term => $term, dn => $c{DN} }, \%c);
}

1;
