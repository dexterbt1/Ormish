package Ormish::Query;
use Moose;
use Carp ();

has 'datastore'         => (is => 'ro', isa => 'Ormish::DataStore', required => 1);
has 'result_types'      => (is => 'rw', isa => 'ArrayRef[Str]');

sub get {
    my ($self, $oid) = @_;
    $self->datastore->flush;
    (scalar(@{$self->result_types})==1)
        or Carp::confess("get() expects a single result type");
    my $class = $self->result_types->[0];
    return $self->datastore->engine->get_object_by_oid($self->datastore, $class, $oid);
}

1;

__END__
