use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME      => 'FiveESS-EMU',
    VERSION   => '0.01',
    PREREQ_PM => {
        'JSON::PP'      => 0,
        'Digest::SHA'   => 0,
        'Time::HiRes'   => 0,
        'Term::ReadKey' => 0,
        'File::Path'    => 0,
        'File::Temp'    => 0,
        'Test::More'    => 0,
    },
    test => { TESTS => 't/*.t' },
);
