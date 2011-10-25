package Ormish::Mapping;
use Moose;
use Moose::Util::TypeConstraints;
use Carp ();

has 'table'         => (is => 'rw', isa => 'Str', required => 1);
has 'oid'           => (is => 'rw', does => 'Ormish::OID::BaseRole', required => 1);
has 'for_class'     => (is => 'rw', isa => 'Str', predicate => 'has_for_class');
has 'attributes'    => (is => 'rw', isa => 'ArrayRef', trigger => sub { $_[0]->_setup_attrs($_[1]) });
has '_attr2col'     => (is => 'rw', isa => 'HashRef', default => sub { { } });
has '_col2attr'     => (is => 'rw', isa => 'HashRef', default => sub { { } });

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
            my $col = $self->_attr2col->{$at} || $at;
            $row{$col} = $obj->$at();
        }
        if ($with_where) { # update or delete
            %where = %{ $self->oid->col_to_values($obj) };
        }
        # ---
        push @rows, [ \%row, \%where ];
    }
    return { $table => \@rows };
}


sub _setup_attrs {
    my ($self, $attr_name_or_aliases) = @_;
    my @attributes = ();
    my %a2c = ();
    my %c2a = ();
    foreach my $at (@$attr_name_or_aliases) {
        my ($meth, $col) = split /\|/, $at, 2;
        if (not $col) {
            $col = $meth;
        }
        push @attributes, $meth;
        $a2c{$meth} = $col;
        $c2a{$col}  = $meth;
    }
    $self->_attr2col( \%a2c );
    $self->_col2attr( \%c2a );
    $self->meta->get_attribute('attributes')->set_raw_value($self, \@attributes);
}

sub attr_to_col {
    my ($self) = @_;
    return $self->_attr2col;
}

sub col_to_attr {
    my ($self, $include_oid_cols) = @_;
    my %h = %{$self->_col2attr};
    if ($include_oid_cols) {
        %h = (%h, %{$self->oid->col_to_attr});
    }
    return \%h;
}


1;

__END__
