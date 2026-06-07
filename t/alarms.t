use strict;
use warnings;
use Test::More;

use lib 'lib';
require Persist;
require Alarms;

local $ENV{FIXED_TIME_FOR_TESTS} = '1996-02-15 03:04:05';

my $state = Persist::default_state();
my $alarms = Alarms->new($state);

my $alarm = $alarms->raise_alarm(severity => 'MJ', source => 'PWR', text => 'BATTERY DISCHARGE');
is($alarm->{id}, 1, 'first alarm id');
is($alarm->{ack_state}, 'UNACK', 'alarm starts unacknowledged');
is(scalar @{ $alarms->list_active() }, 1, 'one active alarm');

$alarms->ack_alarm($alarm);
is($alarm->{ack_state}, 'ACK', 'alarm can be acknowledged');

$alarms->clear_alarm($alarm);
is($alarm->{cleared_time}, '1996-02-15 03:04:05', 'alarm clear time uses fixed time');
is(scalar @{ $alarms->list_active() }, 0, 'cleared alarm is not active');

$alarms->ensure_alarm('DMERT', severity => 'MN', text => 'JOURNAL NEAR FULL');
$alarms->ensure_alarm('DMERT', severity => 'MN', text => 'JOURNAL NEAR FULL');
is(scalar @{ $alarms->list_active() }, 1, 'ensure_alarm does not duplicate active source');

$alarms->clear_by_source('DMERT');
is(scalar @{ $alarms->list_active() }, 0, 'clear_by_source clears active alarm');

done_testing();
