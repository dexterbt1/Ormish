package Ormish::Engine::DBI::ResultRows;
use Moose;
use namespace::autoclean;

use Carp ();

with 'Ormish::Query::Result::Role';

# depend on DBIx::Simple-style interface for now
has '_engine_result'    => (is => 'rw', isa => 'Any', writer => '_set_engine_result', predicate => '_has_engine_result');


sub _get_cached_engine_result {
    my ($self) = @_;
    if (not $self->_has_engine_result) {
        my $r = $self->engine->execute_raw_query($self->engine_query);
        $self->_set_engine_result($r);
    }
    return $self->_engine_result;
}


sub next_row {
    my ($self) = @_;
    my $row = $self->_get_cached_engine_result->hash; 
    return $row;
}


sub next {
    return $_[0]->next_row;
}

sub list {
    my ($self) = @_;
    return $self->_get_cached_engine_result->hashes;
}

sub first_row {
    my ($self) = @_;
    my $r = $self->_get_cached_engine_result->hash;
    $self->_get_cached_engine_result->finish;
    return $r;
}

sub first {
    return $_[0]->first_row;
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



