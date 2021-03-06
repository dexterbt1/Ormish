package Ormish::DataStore;
use strict;
use Moose;
use namespace::autoclean;

use Scalar::Util ();
use Carp();
use YAML;

use Ormish::Query;

has 'engine'                => (is => 'ro', does => 'Ormish::Engine::Role', );
has 'auto_register'         => (is => 'ro', isa => 'Bool', default => sub { 0 });
has 'auto_register_method'  => (is => 'rw', isa => 'Str', default => sub { '_ORMISH_MAPPING' } );
has 'debug_log'             => (is => 'rw', isa => 'ArrayRef', default => sub { [] });

has '_mappings'             => (is => 'ro', isa => 'HashRef[Str]', default => sub { { } });
has '_work_queue'           => (is => 'ro', isa => 'ArrayRef', default => sub { [] } );
has '_work_flushed'         => (is => 'ro', isa => 'ArrayRef', default => sub { [] } );

has '_pending_init'         => (is => 'ro', isa => 'HashRef', default => sub { { } });
has '_init_ok'              => (is => 'ro', isa => 'HashRef', default => sub { { } });



# --- unit of work methods

my %store_of = ();
my %ident_of = ();
my %is_dirty = ();
my %classes_with_hooks = ();


sub of { # ---Function
    my ($obj) = @_;
    return if (not defined $obj);
    return if (not ref($obj));
    my $addr = Scalar::Util::refaddr($obj);
    return (exists $store_of{$addr}) ? $store_of{$addr} : undef;
}

sub obj_is_dirty {
    my ($self, $obj) = @_;
    return (exists $is_dirty{Scalar::Util::refaddr($self)}) 
        ? exists($is_dirty{Scalar::Util::refaddr($self)}{Scalar::Util::refaddr($obj)}) 
        : 0;
}

sub clean_dirty_obj {
    my ($self, $obj) = @_;
    delete $is_dirty{Scalar::Util::refaddr($self)}{Scalar::Util::refaddr($obj)};
}

sub bind_object { # --- Function
    my ($obj, $datastore) = @_;
    # bind obj to datastore 
    my $obj_addr = Scalar::Util::refaddr($obj);
    $store_of{$obj_addr} = $datastore;
    Scalar::Util::weaken($store_of{$obj_addr});
}

sub unbind_object { # --- Function
    my ($obj) = @_;
    my $obj_addr = Scalar::Util::refaddr($obj);
    if (defined $obj_addr) {
        delete $store_of{$obj_addr};
    }
}

# --- 

sub add {
    my ($self, $obj) = @_;
    # check class if mapped; 
    my $obj_addr = Scalar::Util::refaddr($obj);
    my $class   = ref($obj) || '';
    my $mapping = $self->mapping_of_class($class);

    # object is not yet managed by other datastore instances
    if (exists $store_of{$obj_addr}) {
        (Scalar::Util::refaddr($store_of{$obj_addr}) eq Scalar::Util::refaddr($self))
            or Carp::confess("Cannot add object managed by another ".ref($self)." instance");
    }

    my $obj_oid = $mapping->oid->as_str( $obj );

    if (defined $obj_oid) {
        if (not $mapping->oid->is_db_generated) { # e.g. natural keys
            my $idmapped = $self->idmap_get($mapping, $obj);
            return if ($idmapped); # ok, means we have added/seen this object before
            # if we get here, it means we need to insert this object yet as it's not in the identity map
        }
        else {
            return; # autoinc pk that we've seen already
        }
    }
    else { # undef oid
        if (not $mapping->oid->is_db_generated) {
            Carp::confess("Cannot add object with undefined non-DB-generated OID");
        }
    }

    bind_object( $obj, $self );
    $mapping->meta_traverse_relations($class, sub {
        my ($rel, $rel_attr_name, $rel_attr) = @_;
        my $rel_o = $rel_attr->get_raw_value($obj);
        my $rel_m = $self->_mappings->{ref($rel_o)};
        return if (not defined $rel_o);
        if (not $rel->is_collection) {
            $self->add($rel_o); # deep add
            $self->object_invalidate_related_collections($rel_m, $rel_o);
        }
    });
    my @dos = ();
    push @dos, sub {
        $self->engine->insert_object($self, $obj);
        $self->clean_dirty_obj($obj);
        $self->idmap_add($mapping, $obj);
        $self->object_setup_related_collections($mapping, $obj);
    };

    my @undos = ();
    push @undos, sub {
        unbind_object( $obj );
    };
    push @{$self->_work_queue}, [ \@dos, \@undos ];
}


sub add_dirty {
    my ($self, $o, $attr_name) = @_;
    # mark as dirty, save the original oid value
    my $class   = ref($o) || '';
    $is_dirty{Scalar::Util::refaddr($self)}{Scalar::Util::refaddr($o)} = 1;
    my $obj_m = $self->mapping_of_class($class);
    my $oids_before_update = $obj_m->oid->attr_values($o);
    my $mod_attr = $class->meta->get_attribute($attr_name);
    my $prev_value = $mod_attr->get_raw_value($o);
    my $undo_attr_set = sub { 
        return if (not defined $mod_attr);
        $mod_attr->set_raw_value($o, $prev_value); 
    };
    my $do_attr_set = sub {
        $self->engine->update_object($self, $o, $oids_before_update);
        $self->clean_dirty_obj($o);
    };
    push @{$self->_work_queue}, [ [ $do_attr_set ], [ $undo_attr_set ] ];
}


sub add_dirty_collection {
    my ($self, $o, $rel_attr, $rel, $new_val, $old_val) = @_;
    my $class = ref($o);
    my $o_m = $self->mapping_of_class($class);
    my $reverse_rel = $o_m->get_reverse_relation_info($self, $rel_attr->name);
    my $reverse_class = $reverse_rel->{mapping}->for_class;
    my $reverse_attr = $reverse_class->meta->get_attribute($reverse_rel->{attr_name});
    if ($new_val->can('does') && $new_val->does('Ormish::Mapping::Relation::Proxy::Role')) {
        Carp::confess("Assert: unsupported operation");
    }
    else {
        my $proxy = $rel->get_proxy($self, $rel_attr->name, $o, $o_m);
        foreach my $existing_o (@$old_val) { # TODO: should use remove
            my $ds = Ormish::DataStore::of($existing_o);
            if ($ds) {
                $self->add_dirty($existing_o, $reverse_rel->{attr_name}); # mark as dirty first prior to modifying the value
            }
            else {
                $self->add($existing_o); # mark as dirty first prior to modifying the value
            }
            $reverse_attr->set_raw_value($existing_o, undef);
        }
        foreach my $new_o (@$new_val) {
            my $ds = Ormish::DataStore::of($new_o);
            if ($ds) {
                $self->add_dirty($new_o, $reverse_rel->{attr_name}); # mark as dirty first prior to modifying the value
            }
            else {
                $self->add($new_o); # mark as dirty first prior to modifying the value
            }
            $reverse_attr->set_raw_value($new_o, $o);
        }
        $_[4] = $proxy; # substitute!
    }

    if ($old_val->can('does') && $old_val->does('Ormish::Mapping::Relation::Proxy::Role')) {
        $old_val->invalidate_cache() if ($old_val->can('invalidate_cache'));
    }
}


sub delete {
    my ($self, $obj) = @_;
    (of($obj) eq $self)
        or Carp::confess("Cannot delete object from another datastore instance");
    my $class   = ref($obj) || '';
    my $mapping = $self->mapping_of_class($class);

    unbind_object( $obj );

    my $obj_oid = $mapping->oid->as_str( $obj );
    if ($obj_oid) {
        my $undo_delete = sub {
            Ormish::DataStore::bind_object($obj, $self);
            $self->idmap_add($mapping, $obj);
        };
        my $oids_on_delete = $mapping->oid->attr_values($obj);
        my $do_delete = sub {
            $self->engine->delete_object($self, $obj, $oids_on_delete);
        };
        push @{$self->_work_queue}, [ [ $do_delete ], [ $undo_delete ] ];
    }
}

sub flush {
    my ($self) = @_;
    while (my $work = shift @{$self->_work_queue}) {
        my ($dos, $undos) = @$work;
        if ($dos) { # do it!
            foreach my $do (@$dos) {
                $do->();
            }
        }
        push @{$self->_work_flushed}, $work;
    }
}

sub commit {
    my ($self) = @_;
    $self->flush;
    @{$self->_work_flushed} = ();
    $self->engine->commit;
}

sub rollback {
    my ($self) = @_;
    return if (not defined $self->engine);
    $self->engine->rollback;
    my $do_undo = sub {
        my $w = shift;
        my ($dos, $undos) = @$w;
        if ($undos) { # just undo
            foreach my $u (@$undos) {
                $u->();
            }
        }
    };
    while (my $work = pop @{$self->_work_queue}) {
        $do_undo->($work);
    }
    while (my $work = pop @{$self->_work_flushed}) {
        $do_undo->($work);
    }
    # invalidate caches of collections in the identity map
    my $thisaddr = Scalar::Util::refaddr($self);
    foreach my $class (keys %{$ident_of{$thisaddr}}) {
        my $m = $self->_mappings->{$class};
        foreach my $o (values %{$ident_of{$thisaddr}{$class}}) {
            $self->object_invalidate_related_collections($m, $o);
        }
    }
    
}

# --- query factory method

sub query {
    my ($self, @result_types) = @_;
    return Ormish::Query->new( 
        result_types    => \@result_types, 
        datastore       => $self,
    );
}


# --- identity map methods

sub idmap_add {
    my ($self, $mapping, $obj) = @_;
    my $obj_class = $mapping->for_class;
    my $obj_oid = $mapping->oid->as_str( $obj );
    (defined $obj_oid)
        or Carp::confess("Cannot manage object without identity yet");
    # datastore -> class -> obj_oid = obj
    $ident_of{Scalar::Util::refaddr($self)}{$obj_class}{$obj_oid} = $obj; # strong ref
}

sub idmap_get {
    my ($self, $mapping, $oid_str) = @_;
    my $class = $mapping->for_class;
    if (exists($ident_of{Scalar::Util::refaddr($self)}{$class}{$oid_str})) {
        # return cached copy from identity map
        return $ident_of{Scalar::Util::refaddr($self)}{$class}{$oid_str};
    }
    return;
}

sub object_from_hashref {
    my ($self, $mapping, $h) = @_;
    my $tmp_o       = $mapping->new_object_from_hashref($self, $h); # intimate exchange
    my $oid_str     = $mapping->oid->as_str($tmp_o);
    my $o = $self->idmap_get($mapping, $oid_str);
    if ($o) {
        # ignore the temporary new object, return existing object from identity map
        return $o;
    }
    Ormish::DataStore::bind_object($tmp_o, $self);
    $self->idmap_add($mapping, $tmp_o);
    $self->object_setup_related_collections($mapping, $tmp_o);    
    return $tmp_o;
}


sub object_setup_related_collections {
    my ($self, $mapping, $obj) = @_;
    # assumes obj is persistent and w/ oid
    # assumes obj has the correct $mapping + $datastore already

    # populate relations if necessary
    my $class = $mapping->for_class;
    $mapping->meta_traverse_relations($class, sub {
        my ($rel, $rel_attr_name, $rel_attr) = @_;
        my $rel_o = $rel_attr->get_raw_value($obj);
        if ($rel->is_collection) {
            $rel_o = $rel->get_proxy($self, $rel_attr_name, $obj, $mapping);

            # re-insert all existing items
            my $existing_set = $rel_attr->get_raw_value($obj);
            if (defined($existing_set) and not($existing_set->isa(ref($rel_o)))) {
                $rel_o->insert($existing_set->members);
            }
            $self->flush;

            $rel_attr->set_raw_value($obj, $rel_o);
    
        }
    });
}


sub object_invalidate_related_collections {
    my ($self, $mapping, $obj) = @_;
    # assumes obj is persistent and w/ oid
    # assumes obj has the correct $mapping + $datastore already
    # populate relations if necessary
    return if (not defined $obj);
    my $class = $mapping->for_class;
    $mapping->meta_traverse_relations($class, sub {
        my ($rel, $rel_attr_name, $rel_attr) = @_;
        my $rel_o = $rel_attr->get_raw_value($obj);
        if ($rel->is_collection) {
            if (Scalar::Util::blessed($rel_o) and $rel_o->can('invalidate_cache')) {
                $rel_o->invalidate_cache;
            }
        }
    });
}


# --- mapping routines

sub mapping_of_class {
    my ($self, $class) = @_;
    if (scalar keys %{$self->_pending_init} > 0) {
        # lazy initialization of mapped classes
        foreach my $rc (keys %{$self->_pending_init}) {
            delete $self->_pending_init->{$rc};
            next if (exists $self->_init_ok->{$rc}); # prevent deep recursion
            my $m = $self->_mappings->{$rc};
            $m->initialize($self);
            $self->_add_class_hooks($m);
            $self->_init_ok->{$rc} = 1;
        }
    }
    
    if ($self->auto_register) {
        if (! exists $self->_mappings->{$class}) {
            my $method = $self->auto_register_method;
            if ($class->can($method)) {
                my $m = $class->$method;
                $self->_add_to_mappings( $m );
            }
        }
    }
    (exists $self->_mappings->{$class})
        or Carp::confess("Unable to find mapping for class: $class");
    return $self->_mappings->{$class};
}


sub register_mapping {
    my ($self, $opts) = @_;
    if (ref($opts) eq 'ARRAY') {
        foreach my $m (@$opts) {
            $self->_add_to_mappings( $m );
        }
    }
    else {
        $self->_add_to_mappings( $opts );
    }
}


sub _add_to_mappings {
    my ($self, $m) = @_;
    ($m->has_for_class)
        or Carp::confess("Expected for_class in mapping");
    my $class = $m->for_class;
    # ---
    # FIXME: validate oid
    # FIXME: validate attributes
    # FIXME: validate relations
    # FIXME: check conflicts / integrity with other classes

    (not exists $self->_mappings->{$class})
        or Carp::confess("Mapping for class '$class' already exists in datastore");

    $self->_mappings->{$class} = $m;
    $self->_pending_init->{$class} = 1;
}


sub _add_class_hooks {
    my ($self, $mapping) = @_;
    my $m = $mapping;
    my $class = $m->for_class;
    # ---
    # NOTE: this is invasive, so make this generic and a one time thing
    if (not exists $classes_with_hooks{$class}) {
        # install destructor hooks
        my $on_demolish_hook = sub {
            my ($o) = @_;
            my $st = of($o); 
            if ($st) {
                # delete store mapping
                unbind_object($o);
                delete $is_dirty{Scalar::Util::refaddr($st)}{Scalar::Util::refaddr($o)};
            }
        };
        my $metaclass = $class->meta;
        my $meta_was_immutable = $metaclass->is_immutable;
        if ($meta_was_immutable) {
            $metaclass->make_mutable;
        }
        if ($metaclass->has_method('DEMOLISH')) {
            $metaclass->add_before_method_modifier('DEMOLISH', $on_demolish_hook);
        }
        else {
            my $meth = Class::MOP::Method->wrap($on_demolish_hook, name => 'DEMOLISH', package_name => $class);
            $metaclass->add_method( DEMOLISH => $meth );
        }
        # install dirty detectors, 
        #       i.e. detect if the object was modified via writers/accessor, then mark as dirty

        # simple attributes
        my $hook__on_modify_mark_dirty_simple = sub {
            my ($mod_attr) = @_;
            return sub {
                my $o = shift @_;
                if (scalar @_ > 0) {
                    my $st = Ormish::DataStore::of($o); 
                    if (defined $st) {
                        my $new_val = $_[0];
                        my $old_val = $mod_attr->get_raw_value($o);
                        $st->add_dirty($o, $mod_attr->name);
                    }
                }
            };
        };
        $m->meta_traverse_simple_persistent_attributes(sub {
            my ($attr_name) = @_;
            my $attr = $metaclass->get_attribute($attr_name);
            my $writer_name = $attr->writer || $attr->accessor;
            return if (not defined $writer_name); # skip non-public attributes (i.e. w/o writers/accessors)
            $metaclass->add_before_method_modifier( $writer_name, $hook__on_modify_mark_dirty_simple->($attr) );
        });

        # related objects attributes
        my $hook__on_modify_mark_dirty_related = sub {
            my ($mod_attr, $rel) = @_;
            return sub {
                my $o = shift @_;
                if (scalar @_ > 0) {
                    my $st = Ormish::DataStore::of($o); 
                    my $new_val = $_[0];
                    my $old_val = $mod_attr->get_raw_value($o);
                    if ($st) {
                        if ($rel->is_collection) {
                            if (Scalar::Util::blessed($new_val)) {
                                $st->add_dirty_collection($o, $mod_attr, $rel, $_[0], $old_val);
                            }
                            else {
                                # TODO: handle undefs, etc
                            }
                        }
                        else {
                            if (defined $new_val) {
                                $st->add($new_val);
                            }
                            $st->add_dirty($o, $mod_attr->name);
                        }
                    }
                }
            };
        };
        $m->meta_traverse_relations($class, sub {
            my ($rel, $rel_at, $rel_attr) = @_;
            my $writer_name = $rel_attr->writer || $rel_attr->accessor;
            return if (not defined $writer_name); # skip non-public attributes (i.e. w/o writers/accessors)
            $metaclass->add_before_method_modifier( $writer_name, $hook__on_modify_mark_dirty_related->($rel_attr, $rel) );
        });


        $classes_with_hooks{$class} = 1;

        if ($meta_was_immutable) {
            $metaclass->make_immutable;
        }
    }
}

sub DEMOLISH {
    my ($self) = @_;
    $self->rollback;
    delete $ident_of{Scalar::Util::refaddr($self)}; # clear identity map
}

__PACKAGE__->meta->make_immutable;

1;

__END__
