use strict;
use warnings;
use Test::More;

use lib 'lib';
require Persist;
require SCC;

local $ENV{FIXED_TIME_FOR_TESTS} = '1996-02-15 03:04:05';

my $state = Persist::default_state();
my $scc = SCC->new($state);

my $job = $scc->submit_job('CHECK', 'LINES');
is($job->{id}, 1, 'first SCC job id');
is($job->{status}, 'QUEUED', 'job starts queued');

my $stats = $scc->stats();
is($stats->{QUEUED}, 1, 'queued count');
is($stats->{RUNNING}, 0, 'running count');

$scc->tick();
is($job->{status}, 'RUNNING', 'tick starts queued job');

for (1 .. 5) {
    $scc->tick();
}

is($job->{status}, 'DONE', 'job eventually completes');
ok(grep(/COMPLETE/, @{ $job->{output} }), 'completion output recorded');

$scc->log_event('SCC TEST MESSAGE');
my @lines = $scc->emit_lines();
ok(@lines <= 1, 'emit_lines returns zero or one line for one event');

my $found = $scc->find_job(1);
is($found->{name}, 'CHECK', 'find_job returns submitted job');

done_testing();
