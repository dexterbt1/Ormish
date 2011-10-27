package Ormish::OID::Natural;
use Moose;
use Ormish::OID::Serial;

extends 'Ormish::OID::Serial';

sub is_db_generated { 0 }


1;

__END__

