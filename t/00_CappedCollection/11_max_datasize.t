#!/usr/bin/perl -w

use 5.010;
use strict;
use warnings;

use lib 'lib';

use Test::More;
plan "no_plan";

BEGIN {
    eval "use Test::Exception";                 ## no critic
    plan skip_all => "because Test::Exception required for testing" if $@;
}

BEGIN {
    eval "use Test::RedisServer";               ## no critic
    plan skip_all => "because Test::RedisServer required for testing" if $@;
}

BEGIN {
    eval "use Net::EmptyPort";                  ## no critic
    plan skip_all => "because Net::EmptyPort required for testing" if $@;
}

use bytes;
use Data::UUID;
use Redis::CappedCollection qw(
    DEFAULT_SERVER
    DEFAULT_PORT
    NAMESPACE

    ENOERROR
    EMISMATCHARG
    EDATATOOLARGE
    ENETWORK
    EMAXMEMORYLIMIT
    EMAXMEMORYPOLICY
    ECOLLDELETED
    EREDIS
    EDATAIDEXISTS
    EOLDERTHANALLOWED
    );

# options for testing arguments: ( undef, 0, 0.5, 1, -1, -3, "", "0", "0.5", "1", 9999999999999999, \"scalar", [], $uuid )

my $redis;
my $real_redis;
my $port = Net::EmptyPort::empty_port( 32637 ); # 32637-32766 Unassigned

eval { $real_redis = Redis->new( server => DEFAULT_SERVER.":".DEFAULT_PORT ) };
if ( !$real_redis )
{
    $redis = eval { Test::RedisServer->new( conf => { port => $port }, timeout => 3 ) };
    if ( $redis )
    {
        eval { $real_redis = Redis->new( server => DEFAULT_SERVER.":".$port ) };
    }
}
my $skip_msg;
$skip_msg = "Redis server is unavailable" unless ( !$@ and $real_redis and $real_redis->ping );
$skip_msg = "Need a Redis server version 2.6 or higher" if ( !$skip_msg and !eval { return $real_redis->eval( 'return 1', 0 ) } );
$redis->stop if $redis;

SKIP: {
    diag $skip_msg if $skip_msg;
    skip( $skip_msg, 1 ) if $skip_msg;

# For Test::RedisServer
$real_redis->quit;

my ( $coll, $name, $tmp, $id, $status_key, $queue_key, $list_key, @arr, $len, $maxmemory, $info );
my $uuid = new Data::UUID;
my $msg = "attribute is set correctly";

sub new_connect {
    # For Test::RedisServer
    $redis = Test::RedisServer->new( conf =>
        {
            port                => $port,
            maxmemory           => 0,
#            "vm-enabled"        => 'no',
            "maxmemory-policy"  => 'noeviction',
            "maxmemory-samples" => 100,
        } );
    isa_ok( $redis, 'Test::RedisServer' );

    $coll = Redis::CappedCollection->new(
        $redis,
        );
    isa_ok( $coll, 'Redis::CappedCollection' );

    ok $coll->_server =~ /.+:$port$/, $msg;
    ok ref( $coll->_redis ) =~ /Redis/, $msg;

    $status_key  = NAMESPACE.':status:'.$coll->name;
    $queue_key   = NAMESPACE.':queue:'.$coll->name;
    ok $coll->_call_redis( "EXISTS", $status_key ), "status hash created";
    ok !$coll->_call_redis( "EXISTS", $queue_key ), "queue list not created";
}

new_connect();

#-- all correct

# some inserts
$len = 0;
$tmp = 0;
for ( my $i = 1; $i <= 10; ++$i )
{
    ( $coll->insert( $_, $i ), $tmp += bytes::length( $_.'' ), ++$len ) for $i..10;
}
$info = $coll->collection_info;
is $info->{length}, $tmp,   "OK length - $info->{length}";
is $info->{lists},  10,     "OK lists - $info->{lists}";
is $info->{items},  $len,   "OK queue length - $info->{items}";

my $prev_max_datasize = $coll->max_datasize;
my $max_datasize = 100;
$coll->max_datasize( $max_datasize );
is $coll->max_datasize, $max_datasize, $msg;

eval { $id = $coll->insert( '*' x ( $max_datasize + 1 ) ) };
is $coll->last_errorcode, EDATATOOLARGE, "EDATATOOLARGE";
note '$@: ', $@;
$info = $coll->collection_info;
is $info->{length}, $tmp,   "OK length - $info->{length}";
is $info->{lists},  10,     "OK lists - $info->{lists}";
is $info->{items},  $len,   "OK queue length - $info->{items}";

eval { $id = $coll->update( '1', 0, '*' x ( $max_datasize + 1 ) ) };
is $coll->last_errorcode, EDATATOOLARGE, "EDATATOOLARGE";
note '$@: ', $@;
$info = $coll->collection_info;
is $info->{length}, $tmp,   "OK length - $info->{length}";
is $info->{lists},  10,     "OK lists - $info->{lists}";
is $info->{items},  $len,   "OK queue length - $info->{items}";

$coll->max_datasize( $prev_max_datasize );
is $coll->max_datasize, $prev_max_datasize, $msg;

eval { $id = $coll->insert( '*' x ( $max_datasize + 1 ) ) };
ok !$@, $msg;
$info = $coll->collection_info;
is $info->{length}, $tmp += $max_datasize + 1,  "OK length - $info->{length}";
is $info->{lists},  11,                         "OK lists - $info->{lists}";
is $info->{items},  ++$len,                     "OK queue length - $info->{items}";

eval { $id = $coll->update( '1', 0, '*' x ( $max_datasize + 1 ) ) };
ok !$@, $msg;
$info = $coll->collection_info;
is $info->{length}, $tmp + $max_datasize,   "OK length - $info->{length}";
is $info->{lists},  11,                     "OK lists - $info->{lists}";
is $info->{items},  $len,                   "OK queue length - $info->{items}";

$coll->_call_redis( "DEL", $_ ) foreach $coll->_call_redis( "KEYS", NAMESPACE.":*" );

}
