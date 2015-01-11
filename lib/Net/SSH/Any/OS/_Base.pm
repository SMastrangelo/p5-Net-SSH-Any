package Net::SSH::Any::OS::_Base;

use strict;
use warnings;

use Carp;
our @CARP_NOT = ('Net::SSH::Any::Backend::_Cmd');

use Net::SSH::Any::Util qw($debug _debug _array_or_scalar_to_list);
use Net::SSH::Any::Constants qw(:error);

sub loaded { 1 } # helper method to ensure the module has been correctly loaded

sub pty {
    my ($os, $any) = @_;
    $any->_load_module('IO::Pty') or return;
    IO::Pty->new;
}

sub export_handler {
    my ($any, $file) = @_;
    my $fn = fileno $file;
    return $fn if $fn >= 0;
    ()
}

sub set_file_inherit_flag { 1 }

sub has_working_socketpair { }

sub io3_check_and_clean_data {
    my ($any, $in, $data) = @_;
    my @data = grep { defined and length } _array_or_scalar_to_list $data;
    if (@data and not $in) {
        croak "remote input channel is not defined but data is available for sending"
    }
    \@data
}

sub interactive_login {
    my ($any, $pty, $proc) = @_;
    my $opts = $any->{be_opts}; # FIXME. This shouldn't be here!
    my $user = $opts->{user};
    my $password = $opts->{password};
    my $password_prompt = $opts->{password_prompt};
    my $asks_username_at_login = $opts->{asks_username_at_login};

    if (defined $password_prompt) {
        unless (ref $password_prompt eq 'Regexp') {
            $password_prompt = quotemeta $password_prompt;
            $password_prompt = qr/$password_prompt\s*$/i;
        }
    }

    if ($asks_username_at_login) {
         croak "ask_username_at_login set but user was not given" unless defined $user;
         croak "ask_username_at_login set can not be used with a custom password prompt"
             if defined $password_prompt;
    }

    local ($ENV{SSH_ASKPASS}, $ENV{SSH_AUTH_SOCK});

    my $rv = '';
    vec($rv, fileno($pty), 1) = 1;
    my $buffer = '';
    my $at = 0;
    my $password_sent;
    my $start_time = time;
    while(1) {
        if ($any->{_timeout}) {
            $debug and $debug & 1024 and _debug "checking timeout, max: $any->{_timeout}, ellapsed: " . (time - $start_time);
            if (time - $start_time > $any->{_timeout}) {
                $any->_set_error(SSHA_TIMEOUT_ERROR, "timed out while login");
                $any->_os_wait_proc($proc, 0, 1);
                return;
            }
        }

        unless ($any->_os_check_proc($proc)) {
            my $err = ($? >> 8);
            $any->_set_error(SSHA_CONNECTION_ERROR,
                             "slave process exited unexpectedly with error code $err");
            return;
        }

        $debug and $debug & 1024 and _debug "waiting for data from the pty to become available";

        my $rv1 = $rv;
        select($rv1, undef, undef, 1) > 0 or next;
        if (my $bytes = sysread($pty, $buffer, 4096, length $buffer)) {
            $debug and $debug & 1024 and _debug "$bytes bytes readed from pty";

            if ($buffer =~ /^The authenticity of host/mi or
                $buffer =~ /^Warning: the \S+ host key for/mi) {
                $any->_set_error(SSHA_CONNECTION_ERROR,
                                  "the authenticity of the target host can't be established, " .
                                  "the remote host public key is probably not present on the " .
                                  "'~/.ssh/known_hosts' file");
                $any->_os_wait_proc($proc, 0, 1);
                return;
            }
            if ($password_sent) {
                $debug and $debug & 1024 and _debug "looking for password ok";
                last if substr($buffer, $at) =~ /\n$/;
            }
            else {
                $debug and $debug & 1024 and _debug "looking for user/password prompt";
                my $re = ( defined $password_prompt
                           ? $password_prompt
                           : qr/(user|name|login)?[:?]\s*$/i );

                $debug and $debug & 1024 and _debug "matching against $re";

                if (substr($buffer, $at) =~ $re) {
                    if ($asks_username_at_login and
                        ($asks_username_at_login ne 'auto' or defined $1)) {
                        $debug and $debug & 1024 and _debug "sending username";
                        print $pty "$user\n";
                        undef $asks_username_at_login;
                    }
                    else {
                        $debug and $debug & 1024 and _debug "sending password";
                        print $pty "$password\n";
                        $password_sent = 1;
                    }
                    $at = length $buffer;
                }
            }
        }
        else {
            $debug and $debug & 1024 and _debug "no data available from pty, delaying until next read";
            sleep 0.02;
        }

    }
    $debug and $debug & 1024 and _debug "password authentication done";
    return 1;
}

sub validate_cmd {
    my ($any, $cmd) = @_;
    if (defined $cmd and -x $cmd) {
        $debug and $debug & 1024 and _debug "file $cmd found to be executable";
        return $cmd;
    }
    $debug and $debug & 1024 and _debug "file ", $cmd, " is not executable or not found";
    ()
}

sub find_cmd_by_app {}

1;
