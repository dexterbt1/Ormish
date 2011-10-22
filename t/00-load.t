#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Ormish' ) || print "Bail out!
";
}

diag( "Testing Ormish $Ormish::VERSION, Perl $], $^X" );
