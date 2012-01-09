package Ormish::Mapping::OID::Role;
use Moose::Role;

has 'install_attributes'     => (is => 'ro', isa => 'Bool', default => 0);

# $oid->as_str( \%hashref_or_$object )
#   can return undef
requires 'as_str';

requires 'set_object_identity';

requires 'is_db_generated';

requires 'get_attributes';

requires 'attr_values';

requires 'do_install_meta_attributes';


1;

__END__
