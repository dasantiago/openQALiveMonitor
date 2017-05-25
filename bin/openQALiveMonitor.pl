#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use IO::Socket::INET;
use IO::Select;
use Glib::Object::Introspection;
use YAML qw/LoadFile/;
 use Scalar::Util qw/refaddr/;
use 5.018;


my $CRLF="\x0D\x0A";
$\=$CRLF;
$|=1;

Glib::Object::Introspection->setup (
    basename => 'Notify',
    version => '0.7',
    package => 'Notify');
Notify->init;

sub main{
    my %VARS = (
        _livelog=>'GET /tests/%d/livelog', 
        _config=>"$Bin/../conf/openQALiveMonitor.cfg",
        _states=>"$Bin/../conf/states",
        host=>'localhost', 
        port=>80, 
        );

    GetOptions("host=s"=>\$VARS{host}, "port=i"=>\$VARS{port}, "config=s"=>\$VARS{_config}, "test=i"=>\$VARS{test});
    my $patterns = _load_patterns($VARS{_config}, $VARS{_states});

    #TODO: check if test is already finished

    my $select = IO::Select->new(_create_socket($VARS{host}, $VARS{port}));
    _do_request($select, sprintf($VARS{_livelog}, $VARS{test}));
    _listen($select, $patterns);
}

sub _help {
    say <<END;
    Please indicate a test number in the utility invocation.
END
    exit 0;
}

sub _load_patterns {

    my ($config, $statesFolder) = @_;
    my %data = (patterns=>[], functions=>{});
    my $yaml = LoadFile($config);

    for my $state (@{$yaml->{states}}){

        open my $ifh, '<', "$statesFolder/$state" or die "Error opening file: $!";
        while(defined (my $line = <$ifh>)){
            chomp $line;
            next if $line =~ /^\s*$/;
            if($line !~ /^(info|warn|critical): .*/){
                warn "State $state wrongly specified!. Please verify";
                next;
            }
            my ($type, $regexp) = split(/:/, $line, 2);
            
            $type = 'warning' if ($type eq 'warn');
                
            $regexp =~ s/^\s+|\s+$//;
            my $re = qr/$regexp/;
            push @{$data{patterns}}, $re;

            $data{functions}->{refaddr($re)}=sub{
                print STDERR $_[0] if($type=~ /warn|critical/);
                my $popup = Notify::Notification->new("OpenQALiveMonitor: $state", $_[0], "dialog-$type");
                $popup->show;
            }
        }
        close $ifh;
    }

    return \%data;
}

sub _listen {
    my ($select, $patternsData) = @_;
    my @lifeIndicator = ("[-]\r", "[\]\r", "[|]\r", "[/]\r");
    my $counter = 0;
    $\ = undef;
    while(1){
        my ($socket) = $select->can_read();
        my $data = <$socket>;
        print $lifeIndicator[$counter++%4];
        return if !defined $data;
        chomp $data;
        for my $re (@{$patternsData->{patterns}}){
            if($data =~ $re){ #TODO
                #say "Match: ". ($patternsData->{funtions}{refaddr($re)});
                my $functions = $patternsData->{functions}{refaddr($re)}->($1);
            }
        }
    }
}

sub _do_request {
    my ($select, $request) = @_;
    my ($socket) = $select->can_write();

    print $socket $request;

    return 0;
}

sub _create_socket {
    my ($host, $port) = @_;
    my $socket =  IO::Socket::INET->new(Blocking=> 1, PeerAddr => $host, PeerPort=>$port, Proto=>'tcp', Timeout=> 5) or die "Unable to connect to the server";
    $socket->setsockopt(SOL_SOCKET, SO_KEEPALIVE, 1);
    $socket->autoflush(1);

    return $socket;
}

main(@ARGV) unless caller();
