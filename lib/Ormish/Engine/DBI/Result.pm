package Ormish::Engine::DBI::Result;
use Moose;
use namespace::autoclean;

use Carp ();

use Ormish::Query::Result::BaseRole;
with 'Ormish::Query::Result::BaseRole';

# depend on DBIx::Simple-style interface for now
has '_engine_result'    => (is => 'rw', isa => 'Any', writer => '_set_engine_result', predicate => '_has_engine_result');

# flag that a row was returned without being examined by the object-tree builder routine
has '_row_mode'         => (is => 'rw', isa => 'Bool'); 

# the object tree, arrayref of objects based on the wanted query's result_types
has '_objtree'          => (is => 'rw', isa => 'ArrayRef|Undef', predicate => '_objtree_built');

# flag that next_row() has been called, to warn against e.g. as_list() calls
has '_objtree_shifted'  => (is => 'rw', isa => 'Bool');

# meta data cache
has '_cache_result_cta' => (is => 'rw', isa => 'ArrayRef', default => sub { [ ] });
has '_cache_mapping'    => (is => 'rw', isa => 'HashRef', default => sub { { } });


sub BUILD {
    my ($self) = @_;
    my @result_cta = @{$self->query->meta_result_cta};
    $self->_cache_result_cta( \@result_cta );
    # for now, build only 1 class 
    my ($class, $table, $alias) = @{$self->_cache_result_cta};
    $self->_cache_mapping->{$class} = $self->query->datastore->mapping_of_class($class);
}


sub _next_row {
    my ($self, $row_mode) = @_;
    if (not $self->_has_engine_result) {
        my $r = $self->engine->execute_raw_query($self->engine_query);
        $self->_set_engine_result($r);
        $self->_row_mode(1);
    }
    ($row_mode != $self->_row_mode)
        or Carp::confess("Conflict use in result instance; only exclusively call at the time either: next_row() or next()");
    my $row = $self->_engine_result->hash; 
    return $row;
}


sub next_row {
    my ($self) = @_;
    my $row = $self->_next_row(1);
    return if (not $row);
    return $row;
}
        

sub _build_object_tree {
    my ($self) = @_;
    my %map_class_oid = (); 
    my $datastore   = $self->query->datastore;
    my $class_to_mapping = $self->_cache_mapping;
    while (my $row = $self->_next_row(0)) {
        # for now, build only 1 class 

        # TODO: build the actual tree, including relations
        my ($class, $table, $alias) = @{$self->_cache_result_cta};
        my $mapping     = $class_to_mapping->{$class};
        my $tmp_o       = $mapping->new_object_from_hashref($row);
        my $oid_str     = $mapping->oid->as_str($tmp_o);
        my $o = $datastore->idmap_get($mapping, $oid_str);
        if ($o) {
            $map_class_oid{$class}{$oid_str} = $o;
            next;
        }
        Ormish::DataStore::bind_object($tmp_o, $datastore);
        $datastore->idmap_set($mapping, $tmp_o);
        $map_class_oid{$class}{$oid_str} = $tmp_o;
    }
    my @objects = ();
    foreach my $class (keys %$class_to_mapping) {
        push @objects, values %{$map_class_oid{$class}};
    } 
    %map_class_oid = ();
    $self->_objtree(\@objects);
}
        

sub next {
    my ($self) = @_;
    if (not $self->_objtree_built) {
        $self->_build_object_tree;
    }
    $self->_objtree_shifted(1);
    return shift @{$self->_objtree};
}

sub as_list {
    my ($self) = @_;
    if (not $self->_objtree_built) {
        $self->_build_object_tree;
    }
    if ($self->_objtree_shifted) {
        Carp::carp("Calling as_list() on a result instance that was previously iterated by next() ");
    }
    return @{$self->_objtree};
}


__PACKAGE__->meta->make_immutable;

1;


