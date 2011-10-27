package Ormish::Mapping;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;

use Carp ();

has 'table'         => (is => 'rw', isa => 'Str', required => 1);
has 'oid'           => (is => 'rw', does => 'Ormish::OID::BaseRole', required => 1);
has 'for_class'     => (is => 'rw', isa => 'Str', predicate => 'has_for_class');
has 'attributes'    => (is => 'rw', isa => 'ArrayRef', trigger => sub { $_[0]->_setup_attrs($_[1]) });

has '_attr2col'     => (is => 'rw', isa => 'HashRef', default => sub { { } });
has '_col2attr'     => (is => 'rw', isa => 'HashRef', default => sub { { } });
has '_oid_attr2col' => (is => 'rw', isa => 'HashRef', default => sub { { } });
has '_oid_col2attr' => (is => 'rw', isa => 'HashRef', default => sub { { } });

sub BUILD {
    my ($self) = @_;
    # check class
    $self->for_class->can('meta')
        or Carp::croak('Trying to map non-existent class '.$self->for_class);
    # TODO: check attributes 

}

sub _setup_attrs {
    my ($self, $attr_name_or_aliases) = @_;
    my @attributes = ();
    my %a2c = ();
    my %c2a = ();
    my %oid_attrs = map { $_ => 1 } $self->oid->get_attributes;
    my %oid_c2a  = ();
    my %oid_a2c  = ();
    foreach my $at (@$attr_name_or_aliases) {
        my ($meth, $col) = split /\|/, $at, 2;
        if (not $col) {
            $col = $meth;
        }
        push @attributes, $meth;
        $a2c{$meth} = $col;
        $c2a{$col}  = $meth;
        if (exists $oid_attrs{$meth}) {
            $oid_c2a{$col} = $meth;
            $oid_a2c{$meth} = $col;
        }
    }
    $self->_attr2col( \%a2c );
    $self->_col2attr( \%c2a );
    $self->_oid_attr2col( \%oid_a2c );
    $self->_oid_col2attr( \%oid_c2a );
    $self->meta->get_attribute('attributes')->set_raw_value($self, \@attributes);
}

sub oid_attr_to_col {
    return $_[0]->_oid_attr2col;
}
sub oid_col_to_attr {
    return $_[0]->_oid_col2attr;
}

sub attr_to_col {
    my ($self, $exclude_oid) = @_;
    my %h = %{$self->_attr2col};
    my %oid_h = ();
    if ($exclude_oid) {
        my $oid_attr2col = $self->_oid_attr2col;
        foreach my $attr (keys %$oid_attr2col) {
            delete $h{$attr};
        }
    }
    return \%h;
}

sub col_to_attr {
    my ($self, $exclude_oid) = @_;
    my %h = %{$self->_col2attr}; # copy
    if ($exclude_oid) {
        my $oid_col2attr = $self->_oid_col2attr;
        foreach my $col (keys %$oid_col2attr) {
            delete $h{$col};
        }
    }
    return \%h;
}

sub object_insert_table_rows {
    my ($self, $obj) = @_;
    my @rows = ();
    {
        my $attr_to_col     = $self->_attr2col;
        my $oid_attr_to_col = $self->_oid_attr2col;
        my %row = ();
        my %where = ();
        my $oid_is_db_generated = $self->oid->is_db_generated;
        foreach my $at (keys %$attr_to_col) {
            next if ($oid_is_db_generated && exists($oid_attr_to_col->{$at})); # skip serial/autoincrement oid fields 
            my $col     = $attr_to_col->{$at} || $at;
            $row{$col}  = $obj->$at();
        }
        # ---
        push @rows, [ \%row, \%where ];
    }
    return { 
        $self->table() => \@rows,
    };
}

sub object_update_table_rows {
    my ($self, $obj, $obj_oid_attr_values) = @_;
    my @rows = ();
    {
        my $attr_to_col     = $self->_attr2col;
        my $oid_attr_to_col = $self->_oid_attr2col;
        my $oid_is_db_generated = $self->oid->is_db_generated;
        my %row = ();
        foreach my $at (keys %$attr_to_col) {
            next if ($oid_is_db_generated && exists($oid_attr_to_col->{$at})); # skip serial/autoincrement oid fields 
            my $col     = $attr_to_col->{$at} || $at;
            $row{$col}  = $obj->$at();
        }
        my %where = ();
        foreach my $oid_attr (keys %$obj_oid_attr_values) {
            my $col     = $oid_attr_to_col->{$oid_attr} || $oid_attr;
            $where{$col} = $obj_oid_attr_values->{$oid_attr};
        }
        # ---
        push @rows, [ \%row, \%where ];
    }
    return { 
        $self->table() => \@rows,
    };
}


sub new_object_from_hashref {
    my ($self, $h) = @_;
    my $obj_class   = $self->for_class;
    my $c2a         = $self->col_to_attr;
    my %oh          = map { 
        $c2a->{$_} => $h->{$_} 
    } keys %$h;
    # for now, we bypass the Moose->new constraint checks
    my $tmp_o       = bless \%oh, $obj_class;
    return $tmp_o;
}


__PACKAGE__->meta->make_immutable;


1;

__END__
