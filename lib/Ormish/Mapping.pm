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

sub table_rows_of {
    my ($self, $obj) = @_;
    my $table = $self->table;
    my @rows = ();
    {
        my %row = ();
        foreach my $at (@{$self->attributes}) {
            $row{$at} = $obj->$at();
        }
        push @rows, \%row;
    }
    return { $table => \@rows };
}


1;

__END__
