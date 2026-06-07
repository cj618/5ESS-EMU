use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

use lib 'lib';
require Persist;

my $dir = tempdir(CLEANUP => 1);
local $ENV{5ESS_STATE_DIR} = $dir;
local $ENV{FIXED_TIME_FOR_TESTS} = '1996-02-15 03:04:05';

my $state = Persist::default_state();
ok(ref $state eq 'HASH', 'default state is a hash');
is($state->{rcaccess}{ttyV}, 'FFFFF', 'default ttyV access is full');

Persist::append_journal({ type => 'test_event', value => 5 });
ok(-e Persist::journal_path(), 'journal is created');

my @events;
Persist::replay_journal(sub { push @events, shift });
is(scalar @events, 1, 'journal replays one event');
is($events[0]{type}, 'test_event', 'event type survived replay');
is($events[0]{_ts}, '1996-02-15 03:04:05', 'fixed time is used');

Persist::save_snapshot($state, 'test');
ok(-e Persist::snapshot_path(), 'snapshot is written');
my $loaded = Persist::load_snapshot();
ok(ref $loaded eq 'HASH', 'snapshot loads');

done_testing();
