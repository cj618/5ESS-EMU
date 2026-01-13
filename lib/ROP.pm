package ROP;

use strict;
use warnings;
use File::Path qw(make_path);
use Persist;

sub new {
    my ($class, %opts) = @_;
    my $state_dir = $opts{state_dir} || Persist::base_dir();
    my $path = $opts{path} || "$state_dir/rop.log";
    my $self = {
        state_dir   => $state_dir,
        path        => $path,
        brand       => $opts{brand} // 'AT&T/Lucent 5ESS Craft',
        office_id   => $opts{office_id} // 'CO',
        switch_name => $opts{switch_name} // '5ESS',
    };
    return bless $self, $class;
}

sub path {
    my ($self) = @_;
    return $self->{path};
}

sub _ensure_dir {
    my ($self) = @_;
    make_path($self->{state_dir}) unless -d $self->{state_dir};
}

sub log {
    my ($self, $subsystem, $severity, $message, $meta) = @_;
    $self->_ensure_dir();
    my $stamp = Persist::now_stamp();
    my $brand = $self->{brand};
    my $office = $self->{office_id};
    my $switch = $self->{switch_name};
    my $line = sprintf(
        "%s  %s/%s %s  ROP  %s %s  %s",
        $stamp,
        $brand,
        $office,
        $switch,
        ($subsystem // 'SYS'),
        ($severity // 'INFO'),
        ($message // ''),
    );
    if ($meta && ref $meta eq 'HASH' && keys %{$meta}) {
        my @pairs;
        for my $key (sort keys %{$meta}) {
            my $value = defined $meta->{$key} ? $meta->{$key} : '';
            $value =~ s/\s+/ /g;
            push @pairs, "$key=$value";
        }
        $line .= " [" . join(' ', @pairs) . "]";
    }
    open my $fh, '>>', $self->{path} or return;
    print {$fh} $line . "\n";
    close $fh;
}

sub tail {
    my ($self, $count) = @_;
    $count ||= 20;
    return [] unless -e $self->{path};
    open my $fh, '<', $self->{path} or return [];
    my @lines = <$fh>;
    close $fh;
    return \@lines if @lines <= $count;
    return [ @lines[-$count .. -1] ];
}

1;
