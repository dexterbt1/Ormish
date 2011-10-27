package Ormish::OID::BaseRole;
use Moose::Role;

# $oid->as_str( \%hashref_or_$object )
#   can return undef
requires 'as_str';

requires 'set_object_identity';

requires 'is_db_generated';

requires 'get_attributes';

requires 'attr_values';


1;

__END__
