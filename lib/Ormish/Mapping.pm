package Ormish::Mapping;
use Moose;
use namespace::autoclean;

use Scalar::Util ();
use Carp ();

has 'table'         => (is => 'ro', isa => 'Str', required => 1);
has 'oid'           => (is => 'ro', does => 'Ormish::OID::BaseRole', required => 1);
has 'for_class'     => (is => 'ro', isa => 'Str', predicate => 'has_for_class');
has 'attributes'    => (is => 'ro', isa => 'ArrayRef', required => 1);
has 'relations'     => (is => 'ro', isa => 'HashRef', default => sub { { } });

has '_attr2metaattr' => (is => 'ro', isa => 'HashRef', default => sub { { } });
has '_attr2col'     => (is => 'ro', isa => 'HashRef', default => sub { { } });
has '_col2attr'     => (is => 'ro', isa => 'HashRef', default => sub { { } });
has '_oid_attr2col' => (is => 'ro', isa => 'HashRef', default => sub { { } });
has '_oid_col2attr' => (is => 'ro', isa => 'HashRef', default => sub { { } });

has '_related_classes'  => (is => 'ro', isa => 'HashRef', default => sub { { } });
has '_reverse_rel'      => (is => 'ro', isa => 'HashRef', default => sub { { } });


sub BUILD {
    my ($self) = @_;
    # check class
    $self->for_class->can('meta')
        or Carp::confess('Trying to map non-existent or non-Moose class '.$self->for_class);
    # TODO: check attributes 
}

sub initialize {
    my ($self, $datastore) = @_; # datastore is needed for resolving other mappings
    $self->_setup_attrs($datastore);
    $self->_setup_relations($datastore);
}

sub _setup_attrs {
    my ($self, $datastore) = @_;
    my $attr_name_or_aliases = $self->attributes;
    my @attributes = ();
    my %a2c = ();
    my %a2ma = ();
    my %c2a = ();
    my %oid_attrs = map { $_ => 1 } $self->oid->get_attributes;
    my %oid_c2a  = ();
    my %oid_a2c  = ();
    my $class = $self->for_class;
    # auto 
    if ($self->oid->install_attributes) {
        $self->oid->do_install_meta_attributes($class);
    }
    foreach my $oid_attr (keys %oid_attrs) {
        $class->meta->has_attribute($oid_attr)
            or Carp::confess("Undeclared attribute '$oid_attr' in class '$class'");
    } 
    foreach my $at (@$attr_name_or_aliases) {
        my ($meth, $col) = split /\|/, $at, 2;
        if (not $col) {
            $col = $meth;
        }
        my $class_meta = $class->meta;

        $class_meta->has_attribute($meth)
            or Carp::confess("Undeclared attribute '$meth' in class '$class'");

        $a2ma{$meth} = $class_meta->get_attribute($meth);

        push @attributes, $meth;
        $a2c{$meth} = $col;
        $c2a{$col}  = $meth;
        if (exists $oid_attrs{$meth}) {
            $oid_c2a{$col} = $meth;
            $oid_a2c{$meth} = $col;
        }
    }

    %{$self->_attr2col} = %a2c;
    %{$self->_attr2metaattr} = %a2ma;
    %{$self->_col2attr} = %c2a;
    %{$self->_oid_attr2col} = %oid_a2c;
    %{$self->_oid_col2attr} = %oid_c2a;
    $self->meta->get_attribute('attributes')->set_raw_value($self, \@attributes);
}

sub _setup_relations {
    my ($self, $datastore) = @_;
    my $attr_to_rel_map = $self->relations;
    my $class = $self->for_class;
    my $class_meta = $class->meta;
    foreach my $at (keys %$attr_to_rel_map) {
        # attribute should exist 
        $class_meta->has_attribute($at)
            or Carp::confess('Trying to map relation in non-existent attribute '.$at.' for class '.$class);

        my $rel = $attr_to_rel_map->{$at};

        my $to_class = $rel->to_class;
        ($to_class->can('meta'))
            or Carp::confess("Non-moose class $to_class not supported in a relationship");

        # test attribute
        $rel->check_supported_type_constraint($class, $at);
        $self->_related_classes->{$to_class} = 1;

        # check that we have a mapping (or auto load)
        #my $reverse_rel = $self->get_reverse_relation_attr_name($datastore, $at);
        #(defined $reverse_rel)
        #    or Carp::confess("Expected reverse relation to be declared for relation '$at' in class '$class'");

        1;
    }    
}

sub get_reverse_relation_attr_name {
    my ($self, $datastore, $rel_name) = @_; 
    #if (exists $self->_reverse_rel->{Scalar::Util::refaddr($datastore)}->{$rel_name}) {
    #    # cache this call (memoize)
    #    return $self->_reverse_rel->{Scalar::Util::refaddr($datastore)}->{$rel_name};
    #}
    my $ret;
    my $rel = $self->relations->{$rel_name};
    my $to_class = $rel->to_class;
    my $to_class_mapping = $datastore->mapping_of_class($to_class);
    my $to_class_relations = $to_class_mapping->relations;
    my $from_class = $self->for_class;
    my $found = 0;
    foreach my $to_class_attr_name (keys %$to_class_relations) {
        my $to_class_rel = $to_class_relations->{$to_class_attr_name};
        # TODO: support multiple reverse_rel
        if ($to_class_rel->to_class eq $from_class) {
            $found++;
            $ret = $to_class_attr_name;
            #$self->_reverse_rel->{Scalar::Util::refaddr($datastore)}->{$rel_name} = $ret;
        }
    }
    ($found < 2) # TODO: support this later
        or Carp::confess("Ambiguous reverse relation in '$to_class' when resolving '$from_class'");
    return $ret;
}

sub get_related_classes {
    my ($self) = @_;
    return keys %{$self->_related_classes};
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
    my ($self, $datastore, $obj) = @_;
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
            my $attr    = $self->for_class->meta->get_attribute($at);
            my $v       = $attr->get_value($obj);
            if (exists $self->relations->{$at}) {
                if (defined($v) and Scalar::Util::blessed($v)) {
                    my $fk_mapping = $datastore->mapping_of_class(ref($v));
                    my $fk_oid_values = $fk_mapping->oid->attr_values($v);
                    # remap fk oids
                    # ---
                    # TODO: support multi-column composite keys
                    #my %fk_oid_cols = map {  } keys %$fk_oid_values;

                    my %col_to_fk_values = ();
                    foreach my $col_to_fk_attr_name (split(/,/, $col)) {
                        my ($c, $fk_attr_name) = split /=/, $col_to_fk_attr_name;
                        $col_to_fk_values{$c} = $fk_oid_values->{$fk_attr_name};
                    }
                    %row = (%row, %col_to_fk_values);
                }
            }
            else {
                $row{$col}  = $v;
            }
        }
        # ---
        push @rows, [ \%row, \%where ];
    }
    return { 
        $self->table() => \@rows,
    };
}

sub object_update_table_rows {
    my ($self, $datastore, $obj, $obj_oid_attr_values) = @_;
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


sub setup_object_relations {
    my ($self, $obj) = @_;
    # assumes obj is persistent and w/ oid
    # assumes obj has the correct $mapping + $datastore already

    # populate relations if necessary
    foreach my $at (keys %{$self->relations}) {
        my $rel     = $self->relations->{$at};
        my $attr    = $obj->meta->get_attribute($at);
        my $v        = $attr->get_raw_value($obj);
        if ($rel->requires_proxy) {
            $v = $rel->get_proxy_object($at, $obj, $self);
        }
        $attr->set_raw_value($obj, $v);
    }
}


sub new_object_from_hashref {
    my ($self, $h) = @_;
    my $obj_class   = $self->for_class;
    my $c2a         = $self->col_to_attr;
    my %oh          = map { 
        $c2a->{$_} => $h->{$_} 
    } keys %$h;

    # exclude non-required columns that are undefined
    my %oh_nulls    = ();
    foreach my $at (keys %oh) {
        my $attr = $self->_attr2metaattr->{$at};
        if (not($attr->is_required) and (not defined $oh{$at})) {
            $oh_nulls{$at} = delete $oh{$at};
        }
    }
    
    my $tmp_o       = $obj_class->new(%oh);
    return $tmp_o;
}


__PACKAGE__->meta->make_immutable;


1;

__END__
