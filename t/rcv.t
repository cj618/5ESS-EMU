use strict;
use warnings;
use Test::More;

use lib 'lib';
require Persist;
require RCV;

local $ENV{FIXED_TIME_FOR_TESTS} = '1996-02-15 03:04:05';

my $state = Persist::default_state();
my $rcv = RCV->new($state, 'RCV_LOCAL');

my ($ok, $msg) = $rcv->open_ticket('SO-1001');
ok($ok, 'ticket opens');
is($msg, 'TICKET OPENED', 'open message');

($ok, $msg) = $rcv->open_ticket('SO-1002');
ok(!$ok, 'second ticket is refused');

($ok, $msg) = $rcv->add_change('TERM', '1001');
ok($ok, 'term change staged');

($ok, $msg) = $rcv->check_ticket($state->{lines});
ok(!$ok, 'new line without required fields fails check');
like($msg, qr/NEW LINE MISSING/, 'missing field details returned');

for my $pair ([PAIR => '01-02-03'], [COS => 'POTS'], [LINETYPE => '1FR'], [CLASS => 'RES'], [DN => '5551001']) {
    ($ok, $msg) = $rcv->add_change($pair->[0], $pair->[1]);
    ok($ok, "staged $pair->[0]");
}

($ok, $msg) = $rcv->check_ticket($state->{lines});
ok($ok, 'complete ticket passes check');

my ($ticket, $payload, $changes);
($ok, $msg, $ticket, $payload, $changes) = $rcv->commit_ticket($state->{lines}, $state->{dns});
ok($ok, 'ticket commits');
is($ticket, 'SO-1001', 'committed ticket id');
is($state->{lines}{1001}{dn}, '5551001', 'line dn is assigned');
is($state->{dns}{5551001}, '1001', 'dn index is assigned');

($ok, $msg) = $rcv->abort_ticket();
ok(!$ok, 'no ticket left to abort');

($ok, $msg) = $rcv->open_ticket('SO-1003');
ok($ok, 'second ticket opens after commit');
($ok, $msg) = $rcv->abort_ticket();
ok($ok, 'ticket aborts');

done_testing();
