package Ormish::Store;
use strict;
use Moose;
use Scalar::Util qw/refaddr/;
use Carp();

use Ormish::Engine::DBI;

has 'dbh'           => (is => 'rw', isa => 'DBI::db', trigger => sub { $_[1]->{RaiseError} = 1 }, required => 1);
has 'engine'        => (is => 'rw', isa => 'Ormish::Engine::DBI', default => sub { Ormish::Engine::DBI->new });
has 'debug_log'     => (is => 'rw', isa => 'ArrayRef', default => sub { [] });

has '_mappings'     => (is => 'rw', isa => 'HashRef[Str]', default => sub { { } });
has '_work_queue'   => (is => 'rw', isa => 'ArrayRef', default => sub { [] } );

# object -> ... maps
# ---
my %store_of = ();
my %ident_of = ();
my %is_dirty = ();

sub of {
    my ($obj) = @_;
    my $addr = refaddr($obj);
    return (exists $store_of{$addr}) ? $store_of{$addr} : undef;
}

sub add {
    my ($self, $obj) = @_;
    # check class if mapped; 
    # TODO: possible convenience to cache and auto map those classes with _DEFAULT_MAPPING
    my $class = ref($obj) || '';
    my $mapping = $self->mapping_of_class($class);

    # object is not yet managed by other store instances
    if (exists $store_of{$obj}) {
        (refaddr($store_of{$obj}) eq refaddr($self))
            or Carp::croak("Cannot add object managed by another ".ref($self)." instance");
    }
    $store_of{refaddr($obj)} = $self;

    my $obj_oid = $mapping->oid->as_str( $obj );
    if (not defined $obj_oid) {
        # not yet in identity map
        push @{$self->_work_queue}, [ 'insert', $self, $obj ];
    }
    else {
        if (not exists $ident_of{$obj_oid}) {
        }
        else {
            # ...
        }
    }
}

sub flush {
    my ($self) = @_;
    while (my $work = shift @{$self->_work_queue}) {
        my ($engine_method, @params) = @$work;
        push @{$self->debug_log}, 
            $self->engine->$engine_method(@params);
    }
}

sub mapping_of_class {
    my ($self, $class) = @_;
    (exists $self->_mappings->{$class})
        or Carp::croak("Cannot add object of unmapped class: $class");
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
    $self->_mappings->{$class} = $m;
}


1;

__END__
