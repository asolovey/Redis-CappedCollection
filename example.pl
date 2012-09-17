#!/usr/bin/perl -w

# NAME: Redis CappedCollection demonstration

use 5.010;
use strict;
use warnings;

#-- Common ---------------------------------------------------------------------
use Data::UUID;
use Redis::CappedCollection qw(
    DEFAULT_SERVER
    DEFAULT_PORT

    ENOERROR
    EMISMATCHARG
    EDATATOOLARGE
    ENETWORK
    EMAXMEMORYLIMIT
    ECOLLDELETED
    EREDIS
    );

my $server = DEFAULT_SERVER.":".DEFAULT_PORT;   # the Redis Server
my $uuid   = new Data::UUID;

sub exception {
    my $coll    = shift;
    my $err     = shift;

    die $err unless $coll;
    if ( $coll->last_errorcode == ENOERROR )
    {
        # For example, to ignore
        return unless $err;
    }
    elsif ( $coll->last_errorcode == EMISMATCHARG )
    {
        # Necessary to correct the code
    }
    elsif ( $coll->last_errorcode == EDATATOOLARGE )
    {
        # You must use the control data length
    }
    elsif ( $coll->last_errorcode == ENETWORK )
    {
        # For example, sleep
        #sleep 60;
        # and return code to repeat the operation
        #return 'to repeat';
    }
    elsif ( $coll->last_errorcode == EMAXMEMORYLIMIT )
    {
        # For example, return code to restart the server
        #return 'to restart the redis server';
    }
    elsif ( $coll->last_errorcode == ECOLLDELETED )
    {
        # For example, return code to ignore
        #return "to ignore $err";
    }
    elsif ( $coll->last_errorcode == EREDIS )
    {
        # Independently analyze the $err
    }
    else
    {
        # Unknown error code
    }
    die $err if $err;
}

my ( $id, $coll, @data );

eval {
    $coll = Redis::CappedCollection->new(
        redis   => $server,
        name    => 'Some name', # If 'name' not specified, it creates
                        # a new collection named as $uuid->create_str
                        # If specified, the work is done with
                        # a given collection or create a collection
                        # with the specified name
        size    => 100_000, # The maximum size, in bytes,
                        # of the capped collection data
                        # (Default 0 - no limit)
                        # Is set for the new collection
        );
};
exception( $coll, $@ ) if $@;
print "'", $coll->name, "' collection created.\n";
print "Restrictions: ", $coll->size, " size, ", "\n";

#-- Producer -------------------------------------------------------------------
#-- New data

eval {
    $id = $coll->insert(
        'Some data stuff',
        'Some_unique_id',   # If not specified, it creates a new items list
                        # named as $uuid->create_str
        );
    print "Added data in a list with '", $id, "' id\n";

    if ( $coll->update( $id, 0, 'Some new data stuff' ) )
    {
        print "Data updated successfully\n";
    }
    else
    {
        print "The data is not updated\n";
    }
};
exception( $coll, $@ ) if $@;

#-- Consumer -------------------------------------------------------------------
#-- Fetching the data

eval {
    @data = $coll->receive( $id );
    print "List '$id' has '$_'\n" foreach @data;

# or
    while ( my ( $id, $data ) = $coll->pop_oldest )
    {
        print "List '$id' had '$data'\n";
    }
};
exception( $coll, $@ ) if $@;

#-- Utility --------------------------------------------------------------------
#-- Getting statistics

my ( $length, $lists, $items );
eval {
    ( $length, $lists, $items ) = $coll->validate;
    print "An existing collection uses $length byte of data, in $items items are placed in $lists lists\n";

    print "The collection has '$id' list\n" if $coll->exists( 'Some_id' );

    print "Collection '", $coll->name, "' has '$_' list\n" foreach $coll->lists;
};
exception( $coll, $@ ) if $@;

#-- Closes and cleans up -------------------------------------------------------

eval {
    $coll->quit;

# Before use, make sure that the collection is not being used by other customers
#    $coll->drop;
};
exception( $coll, $@ ) if $@;

exit;
