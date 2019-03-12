=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


### Bio::Vega::Utils::MacProxyConfig

package Bio::Vega::Utils::MacProxyConfig;

use strict;
use warnings;
use Mac::PropertyList qw{ parse_plist_file };
use base 'Exporter';

our @EXPORT_OK = qw{ mac_os_x_set_proxy_vars };

sub mac_os_x_set_proxy_vars {
    my ($env_hash) = @_;

    my $netwk_prefs_file = '/Library/Preferences/SystemConfiguration/preferences.plist';
    my $parsed = parse_plist_file($netwk_prefs_file)
        or die "Error parsing PropertyList file '$netwk_prefs_file'";
    my $plist = $parsed->as_perl;

    # CurrentSet points to the current network configuration, ie: Location
    my $current = $plist->{'CurrentSet'}
        or die "No key CurrentSet in plist";
    my $set = fetch_node_from_path($plist, $current);

    # The ServiceOrder lists the network adapters in the order in which they
    # will be used.  We'll take the proxy info from the first active one.
    # This might break if someone is using an IPv6 network!
    my $ipv4_service_keys = $set->{'Network'}{'Global'}{'IPv4'}{'ServiceOrder'}
        or die "No ServiceOrder list in 'Network.Global.IPv4'";
    my @services;
    foreach my $key (@$ipv4_service_keys) {
        # There can be keys listed in ServiceOrder which don't have an entry
        my $link = $set->{'Network'}{'Service'}{$key}{'__LINK__'} or next;
        my $serv = fetch_node_from_path($plist, $link);
        push(@services, $serv);
    }

    unless (@services) {
        warn "No network services found in Mac network prefs file.  Leaving network proxy config untouched\n";
        return;
    }

    # Find the proxy config in the first active network service
    my $active_device = active_network_device_name_hash();
    my $prox = {};
    my $first_network_service_name;
    foreach my $serv (@services) {
        # Skip inactive network services
        my $active = $serv->{'__INACTIVE__'} ? 0 : 1;
        next unless $active;

        my $device_name = $serv->{'Interface'}{'DeviceName'};
        next unless $active_device->{$device_name};

        $first_network_service_name = $serv->{'UserDefinedName'};

        $prox = $serv->{'Proxies'} || {};

        # Only take proxy config from first active service (which ought to
        # be the one which is acutally used).
        last;
    }

    # Protocol names we proxy, and the name of their environment variables.
    # (Probably don't actually need HTTPS, but included anyway.)
    my %proxy_env = qw{
        HTTP    http_proxy
        HTTPS   https_proxy
        FTP     ftp_proxy
    };

    foreach my $protocol (keys %proxy_env) {
        my $var_name = $proxy_env{$protocol};
        if ($prox->{"${protocol}Enable"}) {
            # Fetch the values needed if there is an active proxy
            my $host = $prox->{"${protocol}Proxy"}
                or die "No proxy host for '$protocol' protocol in '$first_network_service_name'";
            my $port = $prox->{"${protocol}Port"}
                or die "No proxy port for '$protocol' protocol in '$first_network_service_name'";
            __setenv($env_hash, $var_name, "http://$host:$port");
        }
        else {
            # There may be proxies set from the previous network
            # config.  We must remove them if there are.
            __setenv($env_hash, $var_name);
        }
    }

    if (my $exc = $prox->{'ExceptionsList'}) {
        __setenv($env_hash, 'no_proxy', join(',', @$exc));
    }
    else {
        __setenv($env_hash, 'no_proxy');
    }

    return;
}

# Some keys in the plist point to other parts of the tree using a UNIX
# filesystem like path. This subroutine fetches the node for a given path
sub fetch_node_from_path {
    my ($plist, $path) = @_;

    $path =~ s{^/}{}
        or die "Path '$path' does not begin with '/'";
    foreach my $ele (split m{/}, $path) {
        $plist = $plist->{$ele}
            or die "No node '$ele' when walking path '$path'";
    }
    return $plist;
}

sub __setenv {
    my ($env_hash, $key, $val) = @_;

    my $old_val = $env_hash->{$key};
    if ((!exists $env_hash->{$key} && !defined $val) or
        (defined $old_val && $old_val eq $val)) {
        # no-op, so keep quiet
    } elsif (defined $val) {
        my $was = (defined $old_val ? "'$old_val'"
                   : (exists $env_hash->{$key} ? 'undef' : 'absent'));
        warn sprintf("%s: Setting %s=%s, was %s\n", __PACKAGE__, $key,
                     defined $val ? "'$val'" : '(delete)',
                     $was);
        # we don't say in which hash we set, but it is invariably %ENV
    }

    if (defined $val) {
        $env_hash->{$key} = $val;
    } else {
        delete $env_hash->{$key};
    }

    return;
}

sub active_network_device_name_hash {

    my @if_com = qw{ ifconfig -u };
    open(my $if_config, '-|', @if_com) or die "Can't open pipe from '@if_com'; $!";
    my $dn;
    my $active_hash = {};
    while (<$if_config>) {
        if (/^(\w+)/) {
            $dn = $1;
        }
        elsif (/status: active/) {
            $active_hash->{$dn} = 1;
        }
    }
    close $if_config or die "Error running '@if_com'; exit $?";
    return $active_hash;
}

1;

__END__

=head1 NAME - Bio::Vega::Utils::MacProxyConfig

=head1 SYNOPSIS

    use Bio::Vega::Utils::MacProxyConfig qw{ mac_os_x_set_proxy_vars };

    if ($^O eq 'darwin') {
        mac_os_x_set_proxy_vars(\%ENV);
    }

=head1 DESCRIPTION

Used to set the HTTP, HTTPS and FTP proxy environment vairables on Mac OS
X. These variables are not propagated by the operating system, but the
data needed to construct them is avaialble in the property list file:

  /Library/Preferences/SystemConfiguration/preferences.plist

This module is vulnerable to changes in the organisation of data in this
property list.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

