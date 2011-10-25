package Ormish::DataStore;
use strict;
use Moose;
use Scalar::Util qw/refaddr weaken/;
use Carp();
use YAML;

use Ormish::Engine::DBI;

has 'dbh'           => (is          => 'rw', 
                        isa         => 'DBI::db', 
                        required    => 1,
                        trigger     => sub { 
                                        $_[1]->{RaiseError} = 1;
                                        (not $_[1]->{AutoCommit}) or Carp::confess("AutoCommit is not supported");
                                    },
                        );
                        
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

sub obj_is_dirty {
    my ($self, $obj) = @_;
    return (exists $is_dirty{refaddr($self)}) ? exists($is_dirty{refaddr($self)}{refaddr($obj)}) : 0;
}

sub clean_dirty_obj {
    my ($self, $obj) = @_;
    delete $is_dirty{refaddr($self)}{refaddr($obj)};
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
    my $mapping = $self->mapping_of_class($class, 1);

    # object is not yet managed by other datastore instances
    if (exists $store_of{$obj_addr}) {
        (refaddr($store_of{$obj_addr}) eq refaddr($self))
            or Carp::croak("Cannot add object managed by another ".ref($self)." instance");
    }
    $store_of{$obj_addr} = $self;
    weaken $store_of{$obj_addr};

    my $obj_oid = $mapping->oid->as_str( $obj );
    if (not defined $obj_oid) {
        # not yet in identity map
        push @{$self->_work_queue}, [ 'new_object', $self, $obj ];
    }
    # TODO: traverse attributes and relationships ...
}

sub flush {
    my ($self) = @_;
    while (my $work = shift @{$self->_work_queue}) {
        my ($engine_method, @params) = @$work;
        $self->engine->$engine_method(@params);
    }
}

sub commit {
    my ($self) = @_;
    $self->flush;
    $self->dbh->commit;
}


# --- helper routines

sub mapping_of_class {
    my ($self, $class, $use_default) = @_;
    if ($use_default) {
        if (! exists $self->_mappings->{$class}) {
            if ($class->can('_ORMISH_MAPPING')) {
                my $m = $class->_ORMISH_MAPPING;
                $self->_add_to_mappings( $m );
            }
        }
    }
    (exists $self->_mappings->{$class})
        or Carp::croak("Unable to find mapping for class: $class");
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
    # NOTE: this is invasive, so make this generic and a one time thing
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
                delete $is_dirty{refaddr($st)}{refaddr($o)};
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
        # install dirty detectors, 
        #       i.e. detect if the object was modified via writers/accessor, then mark as dirty
        my $on_modify_mark_dirty = sub {
            my $o = shift @_;
            if (scalar @_ > 0) {
                my $st = Ormish::DataStore::of($o); 
                if ($st) {
                    # mark as dirty
                    $is_dirty{refaddr($st)}{refaddr($o)} = 1;
                    push @{$st->_work_queue}, [ 'update_dirty', $self, $o ];
                }
            }
        };
        foreach my $attr ($metaclass->get_all_attributes) {
            my $writer_name = $attr->writer || $attr->accessor;
            next if (not defined $writer_name); # skip non-public attributes (i.e. w/o writers/accessors)
            $metaclass->add_before_method_modifier( $writer_name, $on_modify_mark_dirty );
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
    # FIXME: $self->rollback;
    delete $ident_of{refaddr($self)}; # clear identity map
}


1;

__END__
