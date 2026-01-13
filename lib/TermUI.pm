package TermUI;

use strict;
use warnings;
use Term::ReadKey;

sub new {
    my ($class, %opts) = @_;
    my $term = $ENV{TERM} // '';
    my $ansi = ($term ne '' && lc($term) ne 'dumb');
    my ($cols, $rows) = Term::ReadKey::GetTerminalSize();
    $cols ||= 80;
    $rows ||= 24;
    return bless {
        ansi => $ansi,
        cols => $cols,
        rows => $rows,
        title => $opts{title} // '5ESS Craft Environment',
    }, $class;
}

sub ansi_enabled {
    my ($self) = @_;
    return $self->{ansi};
}

sub screen_clear {
    my ($self) = @_;
    if ($self->{ansi}) {
        print "\e[2J\e[H";
    } else {
        print "\n";
    }
}

sub screen_home {
    my ($self) = @_;
    print "\e[H" if $self->{ansi};
}

sub draw_header {
    my ($self, $title) = @_;
    $title ||= $self->{title};
    my $line = sprintf("%-*s", $self->{cols}, $title);
    $line =~ s/\s+$//;
    print "$line\n";
    print(("-" x $self->{cols}) . "\n");
}

sub draw_footer {
    my ($self, $text) = @_;
    $text ||= '';
    print(("-" x $self->{cols}) . "\n");
    print "$text\n" if $text ne '';
}

sub draw_frame {
    my ($self, $title) = @_;
    my $cols = $self->{cols};
    my $border = "+" . ("-" x ($cols - 2)) . "+";
    print "$border\n";
    if (defined $title && $title ne '') {
        my $line = sprintf("| %-*s|", $cols - 3, $title);
        print "$line\n";
        print $border . "\n";
    }
}

sub pager {
    my ($self, $text) = @_;
    my @lines = split(/\n/, $text // '');
    my $rows = $self->{rows} - 2;
    $rows = 20 if $rows < 5;
    while (@lines) {
        my @chunk = splice(@lines, 0, $rows);
        print join("\n", @chunk) . "\n";
        last unless @lines;
        print "--MORE--";
        my $in = <STDIN>;
        last unless defined $in;
    }
}

sub draw_status_line {
    my ($self, $text) = @_;
    $text //= '';
    if ($self->{ansi}) {
        my $cols = $self->{cols};
        my $line = substr(sprintf("%-*s", $cols, $text), 0, $cols);
        print "\e7"; # save cursor
        printf "\e[%d;1H\e[2K%s", $self->{rows}, $line;
        print "\e8"; # restore cursor
    } else {
        print "\n$text\n" if $text ne '';
    }
}

sub render_template {
    my ($self, $path, $vars) = @_;
    return '' unless $path && -e $path;
    open my $fh, '<', $path or return '';
    local $/;
    my $text = <$fh>;
    close $fh;
    $vars ||= {};
    $text =~ s/\{\{(\w+)\}\}/exists $vars->{$1} ? $vars->{$1} : ''/ge;
    return $text;
}

1;
