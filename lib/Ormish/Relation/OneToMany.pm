package Ormish::Relation::OneToMany;
use Moose;
use namespace::autoclean;
use Carp ();
use Set::Object ();

with 'Ormish::Relation::Role';

sub check_supported_type_constraint {
    my ($self, $class, $attr_name) = @_;
    my $attr = $class->meta->get_attribute($attr_name);
    $attr->verify_against_type_constraint(Set::Object->new)
        or Carp::confess("Unsupported type constraint for attribute '$attr_name' in class '$class' (expected Set::Object)");
}

sub get_proxy {
    my ($self, $datastore, $attr_name, $obj, $obj_mapping) = @_;
    my $attr = $obj->meta->get_attribute($attr_name);
    my $existing_set = $attr->get_raw_value($obj);

    my $proxy = Ormish::Relation::OneToMany::SetProxy->new(
        _attr_name          => $attr_name,
        _object             => $obj,
        _object_mapping     => $obj_mapping,
        _datastore          => $datastore,
        _relation           => $self,
    );
    # re-insert all items
    if (defined($existing_set) and not($existing_set->isa(ref($proxy)))) {
        $proxy->insert($existing_set->members);
    }

    $datastore->flush;
    
    return $proxy;
}

sub is_collection { 1 }

1;

__PACKAGE__->meta->make_immutable;

{
    package Ormish::Relation::OneToMany::SetProxy;
    use Moose;
    use MooseX::NonMoose;
    use MooseX::InsideOut;
    
    use Scalar::Util ();
    use Carp ();
    use Set::Object;

    use Ormish::Query;

    with 'Ormish::Relation::Proxy::Role';

    extends 'Set::Object';

    has '_attr_name'        => (is => 'rw', isa => 'Str');
    has '_object'           => (is => 'rw', isa => 'Object', weak_ref => 1); # in OneToMany, this is the MANY part, as a Set::Object
    has '_object_mapping'   => (is => 'rw', isa => 'Ormish::Mapping');
    has '_datastore'        => (is => 'rw', isa => 'Ormish::DataStore', weak_ref => 1);
    has '_relation'         => (is => 'rw', does => 'Ormish::Relation::Role');
    has '_cached_set'       => (is => 'rw', isa => 'Set::Object', predicate => '_has_cached_set', clearer => '_cached_set_clear');

    for (qw/ union equal /) {
        override $_ => sub {
            Carp::confess("Unimplemented functionality");
        }; 
    }

    # ---

    sub insert {
        my $self = shift;
        my $o = $self->_object;
        my $ds = $self->_datastore;
        $ds->flush;
        foreach my $t (@_) {
            my $t_ds = Ormish::DataStore::of($t);
            my $t_class = ref($t);
            my $t_mapping = $ds->mapping_of_class($t_class);

            if (defined $t_ds) {
                (Scalar::Util::refaddr($t_ds) == Scalar::Util::refaddr($ds))
                    or Carp::confess("Cannot insert object bound in another datastore into OneToMany relation");
                # update
                $ds->add_dirty($o, $self->_attr_name);
            }
            else {
                # insert
                my $t_reverse_rel = $self->_object_mapping->get_reverse_relation_info($ds, $self->_attr_name);
                my $attr = $t_class->meta->get_attribute($t_reverse_rel->{attr_name});
                $ds->add($t); 
                $attr->set_value($t, $o);
                1;
            }
        }
        $self->invalidate_cache;
        return scalar(@_);
    }

    sub invalidate_cache {
        $_[0]->_cached_set_clear;
    }

    sub size {
        my ($self) = @_;
        if ($self->_has_cached_set) {
            return $self->members_set->size;
        }
        else {
            # do a select count
            my ($row) = $self->get_query->select_rows(['COUNT(1)|c'])->list;
            return $row->{c};
        }
    }
    
    sub elements { return $_[0]->members(@_); }

    sub members {
        my ($self) = @_;
        return $self->members_set->members;
    }

    sub members_set {
        my ($self) = @_;
        if (not $self->_has_cached_set) {
            my $q = $self->get_query;
            my $set = Set::Object->new($q->select_objects->list);
            $self->_cached_set($set);
        }
        return $self->_cached_set;
    }

    sub get_query {
        my ($self) = @_;
        my $o = $self->_object;
        my $ds = $self->_datastore;
        $ds->flush;
        my $rev_rel_info = $self->_object_mapping->get_reverse_relation_info($ds, $self->_attr_name);
        my $rev_class = $rev_rel_info->{mapping}->for_class;;

        my $static_where = $rev_rel_info->{mapping}->related_object_oid_col_values($ds, $rev_rel_info->{attr_name}, $o);

        my $q = Ormish::Query->new(
            result_types    => [$rev_class],
            datastore       => $ds,
        );
        $q->static_where($static_where);
        return $q;
    }
        

    __PACKAGE__->meta->make_immutable;
}


1;

__END__

