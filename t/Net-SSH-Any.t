#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use File::Spec;

use Net::SSH::Any::Test::Isolated;
use Net::SSH::Any;
use Net::SSH::Any::Constants qw(SSHA_NO_BACKEND_ERROR
                                SSHA_REMOTE_CMD_ERROR);

#$Net::SSH::Any::Test::Isolated::debug =-1;

my %remote_cmd;

sub ssh_ok {
    my $ssh = shift;
    my $msg = join(': ', 'no ssh error', @_);
    if (my $error = $ssh->error) {
        return is($error, 0, $msg);
    }
    ok(1, $msg);
}

sub which {
    my ($ssh, $cmd) = @_;
    $remote_cmd{$cmd} //= do {
        my $out = $ssh->capture(which => $cmd);
        if ($ssh->error) {
            if ($ssh->error == SSHA_REMOTE_CMD_ERROR) {
                diag "remote command $cmd not found";
            }
            else {
                ssh_ok($ssh, "looking for $cmd");
            }
            undef;
        }
        else {
            chomp $out;
            diag "$cmd found at $out";
            $out;
        }
    };
}

our $tssh = Net::SSH::Any::Test::Isolated->new(logger => 'diag');
if (my $error = $tssh->error) {
    diag "Unable to find or start SSH service: $error";
    goto DONE;
}


subtest "$_ backend" => \&test_backend, $_
    for qw(Net_SSH2 Net_OpenSSH Ssh_Cmd Dbclient_Cmd);


DONE:
done_testing();


sub test_backend {
    my $be = shift;
    my %opts = ( backend => $be,
                 timeout => 30,
                 strict_host_key_checking => 0,
                 known_hosts_path => File::Spec->devnull,
                 batch_mode => 1,
                 backend_opts => { Net_OpenSSH => { strict_mode => 0 } } );

    my $ssh = Net::SSH::Any->new($tssh->uri, %opts);

    ok($ssh, "constructor returns an object");
    if (my $error = $ssh->error) {
        if (ok(1, "no backend available")) {
            diag "backend log: $_" for @{$ssh->{backend_log} // []};
        }
        else {
            diag "error: $error";
        }
        return;
    }
    ok(1, "no constructor error");

    my %auto = $ssh->autodetect();
    ssh_ok($ssh, "autodetect") or return;

    ok(defined $auto{os}, "OS detected") or return;
    diag "Remote OS is $auto{os}";

    ok ($auto{shell}, "shell detected");
    diag "remote shell is $auto{shell}" if defined $auto{shell};
    diag "remote shell is csh" if $auto{csh_shell};

    my $wdir = $tssh->make_wdir('Net-SSH-Any');
    my $islh = $tssh->is_localhost($ssh);
    ok (defined $islh, "is_localhost returns a defined value");
    $islh or return;
}


