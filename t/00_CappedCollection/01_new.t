#!/usr/bin/perl -w

use 5.010;
use strict;
use warnings;

use lib 'lib';

use Test::More;
plan "no_plan";

BEGIN {
    eval "use Test::Exception";
    plan skip_all => "because Test::Exception required for testing" if $@;
}

BEGIN {
    eval "use Test::RedisServer";
    plan skip_all => "because Test::RedisServer required for testing" if $@;
}

BEGIN {
    eval "use Test::TCP";
    plan skip_all => "because Test::TCP required for testing" if $@;
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

# options for testing arguments: ( undef, 0, 0.5, 1, -1, -3, "", "0", "0.5", "1", 9999999999999999, \"scalar", [] )

my $redis;
my $real_redis;
my $port = empty_port();

eval { $real_redis = Redis->new( server => DEFAULT_SERVER.":".DEFAULT_PORT ) };
my $skip_msg;
$skip_msg = "Redis server is unavailable" unless ( !$@ and $real_redis and $real_redis->ping );
$skip_msg = "Need a Redis server version 2.6 or higher" if ( !$skip_msg and !eval { return $real_redis->eval( 'return 1', 0 ) } );

SKIP: {
    diag $skip_msg if $skip_msg;
    skip( $skip_msg, 1 ) if $skip_msg;

# For real Redis:
#$redis = $real_redis;
#isa_ok( $redis, 'Redis' );

# For Test::RedisServer
$real_redis->quit;
$redis = Test::RedisServer->new( conf => { port => $port }, timeout => 3 );
isa_ok( $redis, 'Test::RedisServer' );

my ( $coll, $name, $tmp, $status_key, $queue_key );
my $uuid = new Data::UUID;
my $msg = "attribute is set correctly";

# all default

# a class method
$coll = Redis::CappedCollection->new();
isa_ok( $coll, 'Redis::CappedCollection' );
is $coll->_server, DEFAULT_SERVER.":".DEFAULT_PORT, $msg;
ok ref( $coll->_redis ) =~ /Redis/, $msg;
is bytes::length( $coll->name ), bytes::length( '89116152-C5BD-11E1-931B-0A690A986783' ), $msg;
is $coll->size, 0, $msg;
is $coll->max_datasize, Redis::CappedCollection::MAX_DATASIZE, $msg;
is $coll->last_errorcode, 0, $msg;

$status_key  = NAMESPACE.':status:'.$coll->name;
$queue_key   = NAMESPACE.':queue:'.$coll->name;
ok $coll->_call_redis( "EXISTS", $status_key ), "status hash created";
ok !$coll->_call_redis( "EXISTS", $queue_key ), "queue list not created";
ok $coll->_call_redis( "HEXISTS", $status_key, 'size'   ), "status field created";
ok $coll->_call_redis( "HEXISTS", $status_key, 'length' ), "status field created";
ok $coll->_call_redis( "HEXISTS", $status_key, 'lists'  ), "status field created";
is $coll->_call_redis( "HGET", $status_key, 'size'   ), $coll->size, "correct status value";
is $coll->_call_redis( "HGET", $status_key, 'length' ), 0,           "correct status value";
is $coll->_call_redis( "HGET", $status_key, 'lists'  ), 0,           "correct status value";

my $coll_1 = Redis::CappedCollection->new();
my $coll_2 = Redis::CappedCollection->new();
ok $coll_1->name ne $coll_2->name, "new UUID";

# an object method
$coll = $coll->new();
isa_ok( $coll, 'Redis::CappedCollection' );
is $coll->_server, DEFAULT_SERVER.":".DEFAULT_PORT, $msg;
ok ref( $coll->_redis ) =~ /Redis/, $msg;

$coll->_call_redis( 'DEL',
    NAMESPACE.':queue:'.$coll->name,
    NAMESPACE.':status:'.$coll->name,
    $coll->_call_redis( 'KEYS', NAMESPACE.':I:'.$coll->name.":*" ),
    $coll->_call_redis( 'KEYS', NAMESPACE.':D:'.$coll->name.":*" ),
    $coll->_call_redis( 'KEYS', NAMESPACE.':T:'.$coll->name.":*" ),
    );
$coll->quit;

# each argument separately

my $redis2 = Redis->new(
    server => DEFAULT_SERVER.":".DEFAULT_PORT,
    encoding => undef,
    );

$coll = Redis::CappedCollection->new(
    $redis2,
    );
isa_ok( $coll, 'Redis::CappedCollection' );
is $coll->_server, DEFAULT_SERVER.":".DEFAULT_PORT, $msg;
ok ref( $coll->_redis ) =~ /Redis/, $msg;

is $coll->_redis->{encoding}, undef, 'encoding not exists';

$coll = Redis::CappedCollection->new(
    redis => DEFAULT_SERVER.":$port",
    );
isa_ok( $coll, 'Redis::CappedCollection' );
is $coll->_server, DEFAULT_SERVER.":$port", $msg;
ok ref( $coll->_redis ) =~ /Redis/, $msg;

is $coll->_redis->{encoding}, 'utf8', 'encoding exists';

$coll = Redis::CappedCollection->new(
    $coll,
    );
isa_ok( $coll, 'Redis::CappedCollection' );
is $coll->_server, DEFAULT_SERVER.":$port", $msg;
ok ref( $coll->_redis ) =~ /Redis/, $msg;

$coll = Redis::CappedCollection->new(
    $redis,
    );
isa_ok( $coll, 'Redis::CappedCollection' );
ok $coll->_server =~ /.+:$port$/, $msg;
ok ref( $coll->_redis ) =~ /Redis/, $msg;

$coll->_call_redis( "DEL", $_ ) foreach $coll->_call_redis( "KEYS", NAMESPACE.":*" );

$coll = Redis::CappedCollection->new(
    name => $msg,
    );
isa_ok( $coll, 'Redis::CappedCollection' );
is $coll->name, $msg, $msg;
$coll->_call_redis( 'DEL',
    NAMESPACE.':queue:'.$coll->name,
    NAMESPACE.':status:'.$coll->name,
    $coll->_call_redis( 'KEYS', NAMESPACE.':I:'.$coll->name.":*" ),
    $coll->_call_redis( 'KEYS', NAMESPACE.':D:'.$coll->name.":*" ),
    $coll->_call_redis( 'KEYS', NAMESPACE.':T:'.$coll->name.":*" ),
    );

$coll = Redis::CappedCollection->new(
    size => 12345,
    );
isa_ok( $coll, 'Redis::CappedCollection' );
is $coll->size, 12345, $msg;
$coll->_call_redis( 'DEL',
    NAMESPACE.':queue:'.$coll->name,
    NAMESPACE.':status:'.$coll->name,
    $coll->_call_redis( 'KEYS', NAMESPACE.':I:'.$coll->name.":*" ),
    $coll->_call_redis( 'KEYS', NAMESPACE.':D:'.$coll->name.":*" ),
    $coll->_call_redis( 'KEYS', NAMESPACE.':T:'.$coll->name.":*" ),
    );

$coll = Redis::CappedCollection->new(
    max_datasize => 98765,
    );
isa_ok( $coll, 'Redis::CappedCollection' );
is $coll->max_datasize, 98765, $msg;
$coll->_call_redis( 'DEL',
    NAMESPACE.':queue:'.$coll->name,
    NAMESPACE.':status:'.$coll->name,
    $coll->_call_redis( 'KEYS', NAMESPACE.':I:'.$coll->name.":*" ),
    $coll->_call_redis( 'KEYS', NAMESPACE.':D:'.$coll->name.":*" ),
    $coll->_call_redis( 'KEYS', NAMESPACE.':T:'.$coll->name.":*" ),
    );

# errors in the arguments
$tmp = $coll.'';
foreach my $arg ( ( undef, 0, 0.5, 1, -1, -3, "", "0", "0.5", "1", 9999999999999999, \"scalar", [], $uuid ) )
{
    dies_ok { $coll = Redis::CappedCollection->new(
        $arg,
        ) } "expecting to die";
}
is $coll.'', $tmp, "value has not changed";

$tmp = $coll.'';
foreach my $arg ( ( undef, 0, 0.5, 1, -1, -3, "", "0", "0.5", "1", 9999999999999999, \"scalar", [], $uuid ) )
{
    dies_ok { $coll = Redis::CappedCollection->new(
        redis => $arg,
        ) } "expecting to die";
}
is $coll.'', $tmp, "value has not changed";

$tmp = $coll.'';
foreach my $arg ( ( undef, "", \"scalar", [], $uuid ) )
{
    dies_ok { $coll = Redis::CappedCollection->new(
        redis   => DEFAULT_SERVER.":$port",
        name    => $arg,
        ) } "expecting to die: ".( $arg || '' );
}
is $coll.'', $tmp, "value has not changed";

$coll = Redis::CappedCollection->new(
    redis   => DEFAULT_SERVER.":$port",
    size    => 12345,
    );
isa_ok( $coll, 'Redis::CappedCollection' );
is $coll->size, 12345, "correct value set";
$status_key  = NAMESPACE.':status:'.$coll->name;
is $coll->_call_redis( "HGET", $status_key, 'size' ), $coll->size, "correct status value";
$name = $coll->name;
$coll->quit;
$tmp = $coll.'';
dies_ok {
    $coll = Redis::CappedCollection->new(
        redis   => DEFAULT_SERVER.":$port",
        name    => $name,
        size    => 54321,
    ) } "expecting to die";
is $coll.'', $tmp, "value has not changed";
$coll = Redis::CappedCollection->new(
    redis   => DEFAULT_SERVER.":$port",
    );
isa_ok( $coll, 'Redis::CappedCollection' );
$coll->_call_redis( "DEL", $_ ) foreach $coll->_call_redis( "KEYS", NAMESPACE.":*" );

$tmp = $coll.'';
foreach my $arg ( ( undef, 0.5, -1, -3, "", "0.5", \"scalar", [], $uuid ) )
{
    dies_ok { $coll = Redis::CappedCollection->new(
        redis   => DEFAULT_SERVER.":$port",
        size    => $arg,
        ) } "expecting to die: ".( $arg || '' );
    is $coll.'', $tmp, "value has not changed";
}

$tmp = $coll.'';
foreach my $arg ( ( undef, 0.5, -1, -3, "", "0.5", \"scalar", [], $uuid ) )
{
    dies_ok { $coll = Redis::CappedCollection->new(
        redis           => DEFAULT_SERVER.":$port",
        max_datasize    => $arg,
        ) } "expecting to die: ".( $arg || '' );
    is $coll.'', $tmp, "value has not changed";
}

}