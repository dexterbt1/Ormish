use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Ormish',
    license             => 'perl',
    dist_author         => q{Dexter Tad-y <dtady@cpan.org>},
    dist_version_from   => 'lib/Ormish.pm',
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'Ormish-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
