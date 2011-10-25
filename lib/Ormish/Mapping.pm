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
    my ($self, $obj, $with_where) = @_;
    my $table = $self->table;
    my @rows = ();
    {
        my %row = ();
        my %where = ();
        foreach my $at (@{$self->attributes}) {
            $row{$at} = $obj->$at();
        }
        if ($with_where) { # update or delete
            %where = %{ $self->oid->col_to_values($obj) };
        }
        # ---
        push @rows, [ \%row, \%where ];
    }
    return { $table => \@rows };
}


sub attr_to_col {
    my ($self) = @_;
    return {
        # TODO: no aliasing for now
        map { $_ => $_ } @{$self->attributes}
    };
}



1;

__END__
