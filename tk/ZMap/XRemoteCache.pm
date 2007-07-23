
package ZMap::XRemoteCache;

use strict;
use warnings;

use X11::XRemote;
use Data::Dumper;

my $CLIENT_DEBUG = 1;
my $CACHE_DEBUG  = 1;

my $object_cache = {
    # 'window_id' => { object  => X11::XRemote, 
    #                  pid     => $process_id, 
    #                  actions => [ qw(actions accepted by window) ],
    # },
};

# A window has  1 pid, 1 pid  has many windows. A window  has a single
# list of  actions, each  list of actions  has many  windows, possibly
# spread over multiple pids.

sub new{
    my $pkg = shift;
    my $self = {};
    $self->{'_clients'} = \$object_cache;
    $self->{'_user_keys'} = {};
    $self->{'_self_windows'} = {};
    bless($self, $pkg);

    return $self;
}

sub insert_lookup{
    my ($self, $key, $value) = @_;
    $self->{'_user_keys'}->{$key} = $value;
    warn "Inserting $key - $value" if $CACHE_DEBUG;
    return 1;
}
sub lookup_value{
    my ($self, $key, $value) = @_;
    $value = $self->{'_user_keys'}->{$key};
    return $value;
}
# access the class data
sub _get_clients_cache{
    my ($self) = @_;

    if(ref $self){
        return ${ $self->{'_clients'} };
    }else{
        return $object_cache;
    }

    return {};
}

sub get_pid_list{
    my ($self) = @_;
    my ($list, $cache, $pid_hash);
    
    $list ||= [];

    $cache = $self->_get_clients_cache();

    foreach my $xwid(keys(%$cache)){
        my $pid = $cache->{$xwid}->{'pid'};
        if(defined $pid){ $pid_hash->{$pid} = 1; }
    }

    push(@$list, keys(%$pid_hash));

    return $list;
}

sub add_client_with_pid_actions{
    my ($self, $client, $pid, @actions) = @_;

    warn "client is required"    if(!defined($client));
    warn "pid is required"       if(!defined($pid));
    
    my $id = $client->window_id();

    warn "Are you _really_ sure? (client with id '$id' already exists)" if($self->get_client_with_id($id));
    
    my $cache = $self->_get_clients_cache();

    warn "Adding client $id" if $CACHE_DEBUG;
    $cache->{$id} = {
        'object'  => $client,
        'pid'     => $pid,
        'actions' => [ @actions ],
    };
    $self->{'_self_windows'}->{$id} = $id;

    return 1;
}

sub _internal_get_cache_with_id{
    my ($self, $id, $entry) = @_;

    my $cache = $self->_get_clients_cache();

    if($id){
        $entry = $cache->{$id};
    }else{
        $entry = undef;
    }

    return $entry;
}

sub get_client_with_id{
    my ($self, $id, $client) = @_;

    if(my $entry = $self->_internal_get_cache_with_id($id)){
        $client = $entry->{'object'};
    }else{
        $client = undef;
    }
    return $client;
}

sub get_clients_with_pid{
    my ($self, $pid) = @_;

    my $client_list = [];

    my $cache = $self->_get_clients_cache();

    foreach my $id(keys(%$cache)){
        if ($pid eq $cache->{$id}->{'pid'}){
            push(@$client_list, $cache->{$id}->{'object'});
        }
    }

    return $client_list;
}

sub _internal_get_client_for_action_pid{
    my ($self, $cache, $requested_action, $pid) = @_;

    my $client = undef;

    foreach my $id(keys(%$cache)){
        my ($tmp_client, $tmp_pid, $tmp_actions) = ($cache->{$id}->{'object'}, 
                                                    $cache->{$id}->{'pid'}, 
                                                    $cache->{$id}->{'actions'});
        if(defined($pid)){
            next unless $tmp_pid eq $pid;
        }
        $tmp_actions ||= [];
        foreach my $action(@$tmp_actions){
            if($requested_action eq $action){
                $client = $tmp_client;
            }
        }
    }

    return $client;

}

sub get_client_for_action_pid{
    my ($self, $requested_action, $pid) = @_;

    my $cache  = $self->_get_clients_cache();

    my $client = $self->_internal_get_client_for_action_pid($cache, $requested_action, $pid);

    return $client;
}

sub get_own_client_for_action_pid{
    my ($self, $requested_action, $pid) = @_;

    my $cache;

    foreach my $id(keys(%{$self->{'_self_windows'}})){
        $cache->{$id} = $self->_internal_get_cache_with_id($id);
    }

    my $client = $self->_internal_get_client_for_action_pid($cache, $requested_action, $pid);

    return $client;
}

sub remove_client_with_id{
    my ($self, $id, $name) = @_;

    my $client = $self->get_client_with_id($id);

    if($client){
        my $wid   = $client->window_id();
        my $cache = $self->_get_clients_cache();
        warn "Client Window id != hash key id" if ($id ne $wid);
        delete $cache->{$id};
        delete $self->{'_self_windows'}->{$id};
    }

    return undef;
}

sub remove_clients_to_bad_windows{
    my ($self) = @_;
    my $cache = $self->_get_clients_cache();

    warn "bad window cleaning" if $CACHE_DEBUG;
    foreach my $id(keys(%$cache)){
        if(my $xr = $cache->{$id}->{'object'}){
            if(!$xr->ping()){
                warn sprintf "client %s bad removing", $id if $CACHE_DEBUG;
                delete $cache->{$id};
                delete $self->{'_self_windows'}->{$id};
            }else{
                warn sprintf "client %s not bad", $id if $CACHE_DEBUG;
            }
        }else{
            delete $cache->{$id};
            delete $self->{'_self_windows'}->{$id};
        }
            
    }
    return undef;
}

sub create_client_with_pid_id_actions{
    my ($self, $requested_pid, $requested_id, @actions) = @_;
    my ($cached_name, $cached_id);

    my $client = $self->get_client_with_id($requested_id);

    my $allow_overwrite = 0;

    if($client){
        warn "Are you sure? (client with window id '$requested_id' already exists)";
        if($allow_overwrite){
            $cached_id = $client->window_id();
            $client = X11::XRemote->new(-id     => $requested_id, 
                                        -server => 0,
                                        -_DEBUG => $CLIENT_DEBUG);
            $self->add_client_with_pid_actions($client, $requested_pid, @actions);            
        }
    }else{
        $client = X11::XRemote->new(-id     => $requested_id, 
                                    -server => 0,
                                    -_DEBUG => $CLIENT_DEBUG);
        $self->add_client_with_pid_actions($client, $requested_pid, @actions);
    }

    return $client;
}


sub DESTROY{
    my ($self) = @_;

    my $cache = $self->_get_clients_cache();

    print Dumper $cache if $CACHE_DEBUG;
}

1;
