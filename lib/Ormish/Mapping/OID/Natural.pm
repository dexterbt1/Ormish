package Ormish::Mapping::OID::Natural;
use Moose;
use Ormish::Mapping::OID::Auto;

extends 'Ormish::Mapping::OID::Auto';

sub is_db_generated { 0 }


1;

__END__

