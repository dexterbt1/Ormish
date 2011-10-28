package Ormish::Engine::DBI::ResultObjects;
use Moose;
use namespace::autoclean;

use Carp ();

with 'Ormish::Query::Result::BaseRole';

extends 'Ormish::Engine::DBI::ResultRows';

# the object tree, arrayref of objects based on the wanted query's result_types
has '_objects'          => (is => 'rw', isa => 'ArrayRef|Undef', predicate => '_objtree_built');

sub _build_object_tree {
    my ($self) = @_;
    my %map_class_oid = (); 
    my $datastore   = $self->query->datastore;
    my $class_to_mapping = $self->cache_mapping;
    while (my $row = $self->next_row) { # TODO: possible fragile base class
        # for now, build only 1 class 

        # TODO: build the actual tree, including relations
        my ($class, $table, $alias) = @{$self->cache_result_cta};

        my $mapping = $class_to_mapping->{$class};
        my $o       = $datastore->object_from_hashref($mapping, $row);
        my $oid_str = $mapping->oid->as_str($o);

        $map_class_oid{$class}{$oid_str} = $o;
    }
    my @objects = ();
    foreach my $class (keys %$class_to_mapping) {
        push @objects, values %{$map_class_oid{$class}};
    } 
    %map_class_oid = ();
    $self->_objects(\@objects);
}
        

sub next {
    my ($self) = @_;
    if (not $self->_objtree_built) {
        $self->_build_object_tree;
    }
    return shift @{$self->_objects};
}

sub list {
    my ($self) = @_;
    if (not $self->_objtree_built) {
        $self->_build_object_tree;
    }
    return @{$self->_objects};
}


__PACKAGE__->meta->make_immutable;

1;

__END__

# based on Set::Object::TieArray

sub as_tied_arrayref {
    my $self = shift;
    my @h = {};
    tie @h, 'Ormish::Engine::DBI::Result::TiedArray', [ ], $self;
    \@h;
}


{
    
    package Ormish::Engine::DBI::Result::TiedArray;
    use strict;
    use Carp ();

    sub TIEARRAY {
        my $p = shift;
        # expects 
        my $tie = bless [ @_ ], $p;
        require Scalar::Util;
        Scalar::Util::weaken($tie->[0]);
        Scalar::Util::weaken($tie->[1]);
        @{$tie->[0]} = $tie->[1]->as_list; # natural sort order given by the engine query result
        return $tie;
    }
    sub commit {
        my $self = shift;
        $self->[1]->clear;
        $self->[1]->insert(@{$self->[0]});
    }
    sub FETCH {
        my $self = shift;
        my $index = shift;
        $self->[0]->[$index];
    }
    sub STORE {
        Carp::confess("Unsupported STORE operation on a readonly result");
    }
    sub FETCHSIZE {
        my $self = shift;
        scalar(@{$self->[0]});
    }
    sub STORESIZE {
        Carp::confess("Unsupported STORESIZE operation on a readonly result");
    }
    sub EXTEND {
    }
    sub EXISTS {
        my $self = shift;
        my $index = shift;
        if ( $index+1 > $self->FETCHSIZE ) {
            return undef;
        } else {
            return 1;
        }
    }
    sub DELETE {
        Carp::confess("Unsupported DELETE operation on a readonly result");
    }
    sub PUSH {
        Carp::confess("Unsupported PUSH operation on a readonly result");
    }
    sub POP {
        my $self = shift;
        my $rv = pop @{$self->promote};
        return $rv;
    }
    sub CLEAR {
        my $self = shift;
        $self->[0] = [ ];
        Scalar::Util::weaken($self->[0]);
        $self->[0];
    }
    sub SHIFT {
        my $self = shift;
        my $rv = shift @{$self->[0]};
        return $rv;
    }
    sub UNSHIFT {
        Carp::confess("Unsupported UNSHIFT operation on a readonly result");
    }
    sub SPLICE {
        my $self = shift;
        my @rv;
        # perl5--
        if ( @_ == 1 ) {
            splice @{$self->[0]}, $_[0];
        }
        elsif ( @_ == 2 ) {
            splice @{$self->[0]}, $_[0], $_[1];
        }
        else {
            splice @{$self->[0]}, $_[0], $_[1], @_;
        }
        @rv;
    }

}

1;


