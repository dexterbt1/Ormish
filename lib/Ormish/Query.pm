package Ormish::Query;
use Moose;
use namespace::autoclean;

use Carp ();

use Ormish::Query::Result;

has 'datastore'         => (is => 'ro', isa => 'Ormish::DataStore', required => 1);
has 'result_types'      => (is => 'rw', isa => 'ArrayRef[Str]');
has '_filter_cond'      => (is => 'rw', isa => 'ArrayRef');


sub meta_result_class_table_alias {
    my ($self) = @_;
    my @cta = ();
    foreach my $rt (@{$self->result_types}) {
        my $m;
        # check if aliased
        my ($class, $alias) = split /\|/, $rt, 2;
        # try if what we want is a class
        eval {
            $m = $self->datastore->mapping_of_class($class);
        };
        if ($@) {
            # FIXME: try then if this is a relationship 
            Carp::croak(@_); # unsupported for now
        }
        else {
            # for now, support 1 table per class
            my $table = $m->table;
            push @cta, $class, $table, $alias;
        }
    }
    return @cta;
}


sub meta_result_qkv {
    my ($self) = @_;
    my %qkv = ();
    {
        my @tmp_cta = $self->meta_result_class_table_alias;
        while (scalar(@tmp_cta)>=3) {
            my ($class, $table, $alias) = splice(@tmp_cta, 0, 3);
            my $m = $self->datastore->mapping_of_class($class);
            $qkv{$class} = $table;
            if ($alias) {
                $qkv{$alias} = $alias;
            }
            my $alias_or_class = $alias || $class;
            my $alias_or_table = $alias || $table;

            ## oid 
            #my $oid_attr_to_col = $m->oid->attr_to_col;
            #foreach my $oid_attr (keys %$oid_attr_to_col) {
            #    $qkv{$oid_attr} = $oid_attr_to_col->{$oid_attr};    
            #    $qkv{$alias_or_class.'.'.$oid_attr} = $alias_or_table.'.'.$oid_attr_to_col->{$oid_attr};    
            #}

            # regular attributes
            my $class_attr_to_col = $m->attr_to_col;
            foreach my $c_attr (keys %$class_attr_to_col) {
                $qkv{$c_attr} = $class_attr_to_col->{$c_attr};    
                $qkv{$alias_or_class.'.'.$c_attr} = $alias_or_table.'.'.$class_attr_to_col->{$c_attr};    
            }
        }
    }
    return \%qkv;
}


sub meta_filter_condition {
    my ($self) = @_;
    return $self->_filter_cond;
}


sub get {
    my ($self, $oid) = @_;
    $self->datastore->flush;
    (scalar(@{$self->result_types})==1)
        or Carp::confess("get() expects a single result type");
    my $class = $self->result_types->[0];
    return $self->datastore->engine->get_object_by_oid($self->datastore, $class, $oid);
}


sub select {
    my ($self) = @_;
    $self->datastore->flush;
    return $self->datastore->engine->do_select($self->datastore, $self);
}


sub where {
    my $self = shift @_;
    $self->_filter_cond(\@_);
    return $self;
}


__PACKAGE__->meta->make_immutable;

1;

__END__
