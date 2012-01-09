package Ormish::OID::Natural;
use Moose;
use Ormish::OID::Auto;

extends 'Ormish::OID::Auto';

sub is_db_generated { 0 }


1;

__END__

