use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

use lib 'lib';
require ROP;

my $dir = tempdir(CLEANUP => 1);
local $ENV{FIXED_TIME_FOR_TESTS} = '1996-02-15 03:04:05';

my $path = "$dir/rop.log";
my $rop = ROP->new(
    state_dir   => $dir,
    path        => $path,
    brand       => 'PACIFIC BELL',
    office_id   => 'SF01',
    switch_name => '5ESS-SF',
);

is($rop->path(), $path, 'ROP path is retained');

$rop->log('RCV', 'INFO', 'RCV TEST RECORD');
ok(-e $path, 'ROP log file is written');

my $tail = $rop->tail(5);
is(scalar @$tail, 1, 'tail returns one line');
like($tail->[0], qr/PACIFIC BELL/, 'brand appears in ROP line');
like($tail->[0], qr/RCV TEST RECORD/, 'message appears in ROP line');

done_testing();
