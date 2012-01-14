package Ormish::Mapping;
use Moose;
use namespace::autoclean;

use Scalar::Util ();
use Carp ();

use Ormish::Mapping::Hook::Role;

has 'table'         => (is => 'ro', isa => 'Str', required => 1);
has 'oid'           => (is => 'ro', does => 'Ormish::Mapping::OID::Role', required => 1);
has 'for_class'     => (is => 'ro', isa => 'Str', predicate => 'has_for_class');

has 'relations'     => (is => 'ro', isa => 'HashRef', default => sub { { } });

has 'hooks'         => (is => 'ro', isa => 'ArrayRef[Ormish::Mapping::Hook::Role]', predicate => 'has_hooks');

# DSL attr for auto defining simple attributes-to-column mapping
has 'attributes'    => (is => 'ro', isa => 'ArrayRef', default => sub { [ ] });

# for simple ones
has 'attr2col'          => (is => 'ro', isa => 'HashRef', default => sub { { } });
has 'col2attr'          => (is => 'ro', isa => 'HashRef', default => sub { { } });

# for oids
has 'oid_attr2col'      => (is => 'ro', isa => 'HashRef', default => sub { { } });
has 'oid_col2attr'      => (is => 'ro', isa => 'HashRef', default => sub { { } });

# for hook-managed 
has 'hooks_attr2col'    => (is => 'ro', isa => 'HashRef', default => sub { { } });
has 'hooks_col2attr'    => (is => 'ro', isa => 'HashRef', default => sub { { } });

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
    my %oid_c2a  = ();
    my %oid_a2c  = ();

    # auto 
    my $class = $self->for_class;
    if ($self->oid->install_attributes) {
        $self->oid->do_install_meta_attributes($class);
    }

    my %oid_attrs = map { $_ => 1 } $self->oid->get_attributes;
    foreach my $oid_attr (keys %oid_attrs) {
        $class->meta->has_attribute($oid_attr)
            or Carp::confess("Undeclared attribute '$oid_attr' in class '$class'");
    } 

    foreach my $at (@$attr_name_or_aliases) {
        my ($meth, $col) = split /:/, $at, 2;
        if (not $col) {
            $col = $meth;
        }
        my $class_meta = $class->meta;

        $class_meta->has_attribute($meth)
            or Carp::confess("Undeclared attribute '$meth' in class '$class'");

        push @attributes, $meth;
        $a2c{$meth} = $col;
        $c2a{$col}  = $meth;
        if (exists $oid_attrs{$meth}) {
            $oid_c2a{$col} = $meth;
            $oid_a2c{$meth} = $col;
        }
    }

    # attrs managed by hooks, we need to identify which columns are part of the oid
    if ($self->has_hooks) {
        foreach my $hook (@{$self->hooks}) {
            next if (not $hook->can('get_attr_to_col'));
            my $ha2c = $hook->get_attr_to_col;
            foreach my $meth (keys %$ha2c) {
                my $col = $ha2c->{$meth};
                if (exists $oid_attrs{$meth}) {
                    $oid_c2a{$col} = $meth;
                    $oid_a2c{$meth} = $col;
                }
                $self->hooks_attr2col->{$meth} = $col;
                $self->hooks_col2attr->{$col} = $meth;
            }
        }
    }

    # include auto-installed oid attrs
    if ($self->oid->install_attributes) {
        foreach my $oid_at (keys %oid_attrs) {
            # FIXME: support custom columns for auto-installed attributes
            if (!exists $oid_a2c{$oid_at}) {
                $oid_a2c{$oid_at}   = $oid_at;
                $oid_c2a{$oid_at}   = $oid_at;
            }
            if (!exists $a2c{$oid_at}) {
                $a2c{$oid_at}       = $oid_at;
                $c2a{$oid_at}       = $oid_at;
            }
        }
    }


    %{$self->attr2col} = %a2c;
    %{$self->col2attr} = %c2a;
    %{$self->oid_attr2col} = %oid_a2c;
    %{$self->oid_col2attr} = %oid_c2a;
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

        # check presence of reverse relation
        my $reverse_rel = $self->get_reverse_relation_info($datastore, $at);
        (defined $reverse_rel)
            or Carp::confess("Expected reverse relation to be declared for relation '$at' in class '$class'");
    }    
}


sub get_reverse_relation_info {
    my ($self, $datastore, $rel_name) = @_; 
    if (exists $self->_reverse_rel->{$rel_name}) {
        # cache this call (memoize)
        # FIXME: this is fragile, if we reuse the same instance across datastores with DIFFERENT group of mappings
        return $self->_reverse_rel->{$rel_name};
    }
    my $rel = $self->relations->{$rel_name};
    my $to_class = $rel->to_class;
    my $to_class_mapping = $datastore->mapping_of_class($to_class);
    my $to_class_relations = $to_class_mapping->relations;
    my $from_class = $self->for_class;
    my @found = ();
    foreach my $to_class_attr_name (keys %$to_class_relations) {
        my $to_class_rel = $to_class_relations->{$to_class_attr_name};
        # TODO: support multiple reverse_rel
        if ($to_class_rel->to_class eq $from_class) {
            push @found, { 
                rel             => $to_class_rel, 
                attr_name       => $to_class_attr_name,
                mapping         => $to_class_mapping,
            };
        }
    }
    my ($ret,) = @found;
    if (scalar(@found) >= 2) {
        # use hints
        my $reverse_found = 0;
        foreach my $f (@found) {
            if ($f->{rel}->has_reverse_hint) {
                if ($f->{rel}->reverse_relation eq $rel_name) {
                    $ret = $f;
                    $reverse_found = 1;
                    last;
                }
            }
        }
        ($reverse_found)
            or Carp::confess("Ambiguous reverse relation '$rel_name' in '$to_class' when resolving '$from_class'");
    }
    $self->_reverse_rel->{$rel_name} = $ret;
    return $ret;
}


sub attr_to_col {
    my ($self, $exclude_oid) = @_;
    my %h = ( %{$self->attr2col}, %{$self->hooks_attr2col} );
    if ($exclude_oid) {
        my $oid_attr2col = $self->oid_attr2col;
        foreach my $attr (keys %$oid_attr2col) {
            delete $h{$attr};
        }
    }
    return \%h;
}

sub col_to_attr {
    my ($self, $exclude_oid) = @_;
    my %h = ( %{$self->col2attr}, %{$self->hooks_col2attr} );
    if ($exclude_oid) {
        my $oid_col2attr = $self->oid_col2attr;
        foreach my $col (keys %$oid_col2attr) {
            delete $h{$col};
        }
    }
    return \%h;
}

sub oid_attr_to_col {
    return $_[0]->oid_attr2col;
}

sub oid_col_to_attr {
    return $_[0]->oid_col2attr;
}



sub related_object_oid_col_values {
    my ($self, $datastore, $relation_name, $rel_obj) = @_;
    my $rel             = $self->relations->{$relation_name};
    my $rel_class       = $rel->to_class;
    my $fk_mapping      = $datastore->mapping_of_class($rel_class);
    my $fk_oid_values   = $fk_mapping->oid->attr_values($rel_obj);
    my $attr_to_col     = $self->attr2col;
    my $col             = $attr_to_col->{$relation_name};

    my %col_to_fk_values = ();
    foreach my $col_to_fk_attr_name (split(/,/, $col)) {
        my ($c, $fk_attr_name) = split /=/, $col_to_fk_attr_name;
        $col_to_fk_values{$c} = $fk_oid_values->{$fk_attr_name};
    }
    return \%col_to_fk_values;
}


sub object_insert_table_rows {
    my ($self, $datastore, $obj) = @_;
    my %table_rows = ();
    {
        my $attr_to_col     = $self->attr2col;
        my $oid_attr_to_col = $self->oid_attr2col;
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
        $table_rows{$self->table} = [ [ \%row, \%where ] ];
    }
    # run hooks
    {
        if ($self->has_hooks) {
            foreach my $hook (@{$self->hooks}) {
                if ($hook->can('object_insert_table_rows_hook')) {
                    $hook->object_insert_table_rows_hook($self, \%table_rows, $datastore, $obj);
                }
            }
        }
    }
    return \%table_rows;
}


sub object_update_table_rows {
    my ($self, $datastore, $obj, $obj_oid_attr_values) = @_;
    my %table_rows = ();
    {
        my $attr_to_col     = $self->attr2col;
        my $oid_attr_to_col = $self->oid_attr2col;
        my $oid_is_db_generated = $self->oid->is_db_generated;
        my %row = ();
        foreach my $at (keys %$attr_to_col) {
            next if ($oid_is_db_generated && exists($oid_attr_to_col->{$at})); # skip serial/autoincrement oid fields 

            my $col     = $attr_to_col->{$at} || $at;
            my $attr    = $self->for_class->meta->get_attribute($at);
            my $v       = $attr->get_value($obj);
            if (exists $self->relations->{$at}) {
                # collapse objects into their oids
                my ($fk_mapping, $fk_oid_values) = @_;
                if (defined $v) {
                    $fk_mapping      = $datastore->mapping_of_class(ref($v));
                    $fk_oid_values   = $fk_mapping->oid->attr_values($v);
                } # else null values
                my %col_to_fk_values = ();
                foreach my $col_to_fk_attr_name (split(/,/, $col)) {
                    my ($c, $fk_attr_name) = split /=/, $col_to_fk_attr_name;
                    $col_to_fk_values{$c} 
                        = (defined $fk_oid_values) 
                            ? $fk_oid_values->{$fk_attr_name} 
                            : undef;
                }
                %row = (%row, %col_to_fk_values);
            }
            else {
                $row{$col}  = $v;
            }
        }
        my %where = ();
        foreach my $oid_attr (keys %$obj_oid_attr_values) {
            my $col     = $oid_attr_to_col->{$oid_attr} || $oid_attr;
            $where{$col} = $obj_oid_attr_values->{$oid_attr};
        }
        # ---
        $table_rows{$self->table} = [ [ \%row, \%where ] ];
    }
    # run hooks
    {
        if ($self->has_hooks) {
            foreach my $hook (@{$self->hooks}) {
                if ($hook->can('object_update_table_rows_hook')) {
                    $hook->object_update_table_rows_hook($self, \%table_rows, $datastore, $obj, $obj_oid_attr_values)
                }
            }
        }
    }
    return \%table_rows;
}


# return { table1 => { col1 => 1, col2 => 1, ... }, ... }
sub table_columns_for_select { 
    my ($self) = @_;
    my %tc = ( );
    my $table = $self->table;
    $tc{$table} = { map { $_ => 1 } keys %{$self->attr_to_col} };
    if ($self->has_hooks) {
        foreach my $hook (@{$self->hooks}) {
            if ($hook->can('table_columns_for_select_hook')) {
                $hook->table_columns_for_select_hook($self, \%tc);
            }
        }
    }
    return \%tc;
}


sub setup_related_collections {
    my ($self, $datastore, $obj) = @_;
    # assumes obj is persistent and w/ oid
    # assumes obj has the correct $mapping + $datastore already

    # populate relations if necessary
    foreach my $at (keys %{$self->relations}) {
        my $rel     = $self->relations->{$at};
        my $attr    = $obj->meta->get_attribute($at);
        my $v        = $attr->get_raw_value($obj);
        if ($rel->is_collection) {
            $v = $rel->get_proxy($datastore, $at, $obj, $self);
        }
        $attr->set_raw_value($obj, $v);
    }
}


sub meta_traverse_simple_persistent_attributes {
    my ($self, $callback) = @_;
    my $relations = $self->relations;
    foreach my $attr_name (keys %{$self->attr_to_col}) {
        next if (exists $relations->{$attr_name}); # skip relations
        $callback->($attr_name);
    }
}

sub meta_traverse_relations {
    my ($self, $class, $callback) = @_;
    my $relations = $self->relations;
    foreach my $rel_at (keys %$relations) {
        my $rel_attr = $class->meta->get_attribute($rel_at);
        my $rel = $relations->{$rel_at};
        $callback->($rel, $rel_at, $rel_attr);
    }
}


sub new_object_from_hashref {
    my ($self, $datastore, $h) = @_;
    my $obj_class   = $self->for_class;
    my $c2a         = $self->col2attr; # simple attributes only
    my $a2rel       = $self->relations;
    my %oh = ();

    # build primitive types
    foreach my $col (keys %$h) { 
        next if (not exists $c2a->{$col});
        my $attr = $c2a->{$col};
        next if (exists $a2rel->{$attr}); # skip related objects
        my $value = $h->{$col};
        $oh{$attr} = $value;
    }

    # build related non-collection objects
    foreach my $rel_at (keys %$a2rel) {
        my $rel         = $a2rel->{$rel_at};
        next if ($rel->is_collection);
        my $col_spec    = $self->attr_to_col->{$rel_at};
        my $rel_class   = $rel->to_class;
        my $rel_meta    = $rel_class->meta;
        my %fk_oh = ();
        foreach my $col_to_fk_attr_name (split(/,/, $col_spec)) {
            my ($c, $fk_attr_name) = split /=/, $col_to_fk_attr_name;
            $fk_oh{$fk_attr_name} = $h->{$c};
        }
        # build proxy
        my $rel_mapping = $datastore->mapping_of_class($rel_class);
        my $proxy = $rel->get_proxy($datastore, $rel_at, \%fk_oh, $rel_mapping);
        $oh{$rel_at} = $proxy;
    }

    # build attribute via hooks
    if ($self->has_hooks) {
        foreach my $hook (@{$self->hooks}) {
            if ($hook->can('new_object_from_hashref_hook')) {
                $hook->new_object_from_hashref_hook($self, $datastore, $h, \%oh);
            }
        }
    }

    # exclude non-required columns that are undefined
    my %oh_nulls    = ();
    my $metaclass   = $obj_class->meta;
    foreach my $at (keys %oh) {
        my $attr = $metaclass->get_attribute($at);
        if (not($attr->is_required) and (not defined $oh{$at})) {
            $oh_nulls{$at} = delete $oh{$at};
        }
    }

    
    # FIXME:    for now, bypass Moose construction, 
    #           the reason being that the data is from the database, 
    #           assumed to have been validated and sanitized already
    my $tmp_o       = bless \%oh, $obj_class;
    return $tmp_o;
}


__PACKAGE__->meta->make_immutable;


1;

__END__
