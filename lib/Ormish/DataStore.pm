package Ormish::DataStore;
use strict;
use Moose;
use Scalar::Util qw/refaddr weaken/;
use Carp();
use YAML;

use Ormish::Engine::DBI;

has 'dbh'           => (is => 'rw', isa => 'DBI::db', trigger => sub { $_[1]->{RaiseError} = 1 }, required => 1);
has 'engine'        => (is => 'rw', isa => 'Ormish::Engine::DBI', default => sub { Ormish::Engine::DBI->new });
has 'debug_log'     => (is => 'rw', isa => 'ArrayRef', default => sub { [] });

has '_mappings'     => (is => 'rw', isa => 'HashRef[Str]', default => sub { { } });
has '_work_queue'   => (is => 'rw', isa => 'ArrayRef', default => sub { [] } );

# ---
my %store_of = ();
my %ident_of = ();
my %is_dirty = ();
my %classes_with_hooks = ();

sub of { # ---Function
    my ($obj) = @_;
    my $addr = refaddr($obj);
    return (exists $store_of{$addr}) ? $store_of{$addr} : undef;
}

sub idmap_add {
    my ($self, $obj) = @_;
    my $obj_class = ref($obj) || '';
    my $mapping = $self->mapping_of_class($obj_class);
    my $obj_oid = $mapping->oid->as_str( $obj );
    (defined $obj_oid)
        or Carp::confess("Cannot manage object without identity yet");
    # datastore -> class -> obj_oid = obj
    $ident_of{refaddr($self)}{$obj_class}{$obj_oid} = $obj;
    weaken $ident_of{refaddr($self)}{$obj_class}{$obj_oid};
}

sub add {
    my ($self, $obj) = @_;
    # check class if mapped; 
    # TODO: possible convenience to cache and auto map those classes with _DEFAULT_MAPPING
    my $obj_addr = refaddr($obj);
    my $class   = ref($obj) || '';
    my $mapping = $self->mapping_of_class($class);

    # object is not yet managed by other datastore instances
    if (exists $store_of{$obj_addr}) {
        (refaddr($store_of{$obj_addr}) eq refaddr($self))
            or Carp::croak("Cannot add object managed by another ".ref($self)." instance");
    }
    $store_of{$obj_addr} = $self;

    my $obj_oid = $mapping->oid->as_str( $obj );
    if (not defined $obj_oid) {
        # not yet in identity map
        push @{$self->_work_queue}, [ 'new_object', $self, $obj ];
    }
    else {
        if (not exists $ident_of{refaddr($self)}{$class}{$obj_oid}) {
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
    # ---
    # NOTE: this is invasive, so make this a one time thing
    if (not exists $classes_with_hooks{$class}) {
        # install destructor hooks
        my $on_demolish_hook = sub {
            my ($o) = @_;
            my $st = Ormish::DataStore::of($o); 
            if ($st) {
                # delete in identity map of its datastore, if necessary
                my $obj_m = $st->mapping_of_class($class);
                my $obj_oid = $obj_m->oid->as_str( $o );
                if (defined $obj_oid) { 
                    delete $ident_of{refaddr($st)}{$class}{$obj_oid};
                }
                # delete store mapping
                delete $store_of{refaddr($o)};
            }
        };
        my $metaclass = $class->meta;
        if ($metaclass->has_method('DEMOLISH')) {
            $metaclass->add_before_method_modifier('DEMOLISH', $on_demolish_hook);
        }
        else {
            my $meth = Class::MOP::Method->wrap($on_demolish_hook, name => 'DEMOLISH', package_name => $class);
            $metaclass->add_method( DEMOLISH => $meth );
        }

        $classes_with_hooks{$class} = 1;
    }
}

sub log_debug {
    my ($self, $info) = @_;
    push @{$self->debug_log}, $info;
}

sub DEMOLISH {
    my ($self) = @_;
    delete $ident_of{refaddr($self)}; # clear identity map
}


1;

__END__
