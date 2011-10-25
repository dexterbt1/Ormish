package Ormish::Query;
use Moose;
use Carp ();

use Ormish::Query::Result;

has 'datastore'         => (is => 'ro', isa => 'Ormish::DataStore', required => 1);
has 'result_types'      => (is => 'rw', isa => 'ArrayRef[Str]');
has '_filter_cond'      => (is => 'rw', isa => 'ArrayRef');


sub meta_result_class_tables {
    my ($self) = @_;
    my @class_tables = ();
    foreach my $rt (@{$self->result_types}) {
        my $m;
        # try first if what we want is a class
        eval {
            $m = $self->datastore->mapping_of_class($rt);
        };
        if ($@) {
            # FIXME: try then if this is a relationship 
            Carp::croak(@_); # unsupported for now
        }
        else {
            my $class = $m->for_class;
            # for now, support 1 table per class
            my $table = $m->table;
            push @class_tables, $class, $table;
        }
    }
    return @class_tables;
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



1;

__END__
