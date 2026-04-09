# -*- Perl -*-
# Tests for IPv6 support in Net::Ident.
# These verify that IPv6 sockaddr structures are correctly detected,
# unpacked, and used for ident connections.

use 5.010;
use strict;
use warnings;

use Test::More;
use Net::Ident;
use Socket;

# Check if Socket.pm has IPv6 support
my $has_ipv6 = defined &Socket::pack_sockaddr_in6
    && defined &Socket::unpack_sockaddr_in6
    && defined &Socket::inet_ntop
    && defined &Socket::inet_pton;

plan skip_all => 'Socket.pm lacks IPv6 support' unless $has_ipv6;

# Check if AF_INET6 / PF_INET6 are available
my $af_inet6 = eval { Socket::AF_INET6() };
plan skip_all => 'AF_INET6 not available' unless defined $af_inet6;

# --- newFromInAddr with IPv6 addresses ---
# Uses ::1 (loopback) as local and a documentation address as remote.
# The connect to the remote identd port will fail, but the object
# should be created with correct state.
{
    my $local  = Socket::pack_sockaddr_in6( 12345, Socket::inet_pton( $af_inet6, '::1' ) );
    my $remote = Socket::pack_sockaddr_in6( 54321, Socket::inet_pton( $af_inet6, '::1' ) );
    my $obj    = Net::Ident->newFromInAddr( $local, $remote, 2 );
    ok( $obj, 'newFromInAddr(::1, ::1): returns object' );

    # On most systems, bind to ::1 succeeds, connect to ::1:113 may fail
    if ( $obj->geterror ) {
        like( $obj->geterror, qr/socket|bind|connect/i,
            'newFromInAddr IPv6: error is from socket/bind/connect' );
    }
    else {
        ok( $obj->getfh, 'newFromInAddr IPv6: has fh when no immediate error' );
    }
}

# --- new() with an IPv6 connected socket (loopback, no identd) ---
SKIP: {
    eval { require IO::Socket::IP };
    skip 'IO::Socket::IP not available', 4 if $@;

    my $listener = IO::Socket::IP->new(
        Listen    => 1,
        LocalAddr => '::1',
        Proto     => 'tcp',
    );
    skip 'cannot create IPv6 listener (IPv6 may not be configured)', 4 unless $listener;

    my $port = $listener->sockport;
    my $client = IO::Socket::IP->new(
        PeerAddr => '::1',
        PeerPort => $port,
        Proto    => 'tcp',
    );
    skip 'cannot connect to IPv6 listener', 4 unless $client;
    my $server = $listener->accept;
    skip 'IPv6 accept failed', 4 unless $server;

    # This exercises the full new() path with an IPv6 socket:
    # getsockname/getpeername return AF_INET6 sockaddr structures,
    # which newFromInAddr must handle correctly.
    my $obj = Net::Ident->new( $client, 2 );
    ok( $obj, 'new(IPv6 connected socket): returns object' );

    if ( !$obj->geterror ) {
        ok( $obj->getfh, 'new(IPv6 socket): has ident fh' );

        # query + ready should eventually fail (no identd on ::1)
        my ( $user, $opsys, $error ) = $obj->username;
        ok( !defined $user, 'IPv6 no identd: username is undef' );
        ok( $error, "IPv6 no identd: got error: " . ( $error // '<undef>' ) );
    }
    else {
        # On some systems, connect to ::1:113 fails immediately
        like( $obj->geterror, qr/socket|connect|refused|timed/i,
            'new(IPv6 socket): error from ident connect' );
        pass('skipping IPv6 username test — ident connect failed');
        pass('skipping IPv6 username test — ident connect failed');
    }

    close($client);
    close($server);
    close($listener);
}

# --- Address family mismatch ---
# Mixing IPv4 and IPv6 addresses should produce an error, not a crash.
{
    my $local4  = sockaddr_in( 12345, inet_aton('127.0.0.1') );
    my $remote6 = Socket::pack_sockaddr_in6( 54321, Socket::inet_pton( $af_inet6, '::1' ) );
    my $obj     = Net::Ident->newFromInAddr( $local4, $remote6, 2 );
    ok( $obj, 'mixed IPv4/IPv6: returns object' );
    like( $obj->geterror, qr/mismatch/i,
        'mixed IPv4/IPv6: reports address family mismatch' );
}

# --- IPv6 username parsing (via subclass, no network) ---
# Reuse the parse testing technique from t/parse.t to verify that
# the ident protocol response parsing works identically for IPv6.
{
    package Net::Ident::IPv6Test;
    our @ISA = ('Net::Ident');
    sub ready { return 1 }

    package main;

    my $local  = Socket::pack_sockaddr_in6( 12345, Socket::inet_pton( $af_inet6, '::1' ) );
    my $remote = Socket::pack_sockaddr_in6( 54321, Socket::inet_pton( $af_inet6, '::1' ) );

    # Create a fake object that already has an answer
    my $obj = bless {
        state      => 'ready',
        answer     => '54321 , 12345 : USERID : UNIX : testuser',
        remoteport => 54321,
        localport  => 12345,
    }, 'Net::Ident::IPv6Test';

    my ( $user, $opsys, $error ) = $obj->username;
    is( $user,  'testuser', 'IPv6 parse: correct username' );
    is( $opsys, 'UNIX',     'IPv6 parse: correct opsys' );
    is( $error, undef,      'IPv6 parse: no error' );
}

done_testing;
