package Ormish::Mapping;
use Moose;
use Moose::Util::TypeConstraints;
use Carp ();

has 'table'         => (is => 'rw', isa => 'Str', required => 1);
has 'oid'           => (is => 'rw', does => 'Ormish::OID::BaseRole', required => 1);
has 'for_class'     => (is => 'rw', isa => 'Str', predicate => 'has_for_class');
has 'attributes'    => (is => 'rw', isa => 'ArrayRef');

sub BUILD {
    my ($self) = @_;
    # check class
    $self->for_class->can('meta')
        or Carp::croak('Trying to map non-existent class '.$self->for_class);
    # TODO: check attributes 

}

sub column_values_for {
    my ($self, $obj) = @_;
    my %col_to_val = ();
    foreach my $at (@{$self->attributes}) {
        $col_to_val{$at} = $obj->$at();
    }
    return \%col_to_val;
}


1;

__END__
