
package ZMap::XRemoteCache;

use strict;
use warnings;

use X11::XRemote;
use Data::Dumper;

my $CLIENT_DEBUG = 0;
my $CACHE_DEBUG  = 0;

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
    $self->{'_self_windows'} = {};
    bless($self, $pkg);

    return $self;
}

sub get_pid_list{
    my ($self) = @_;
    my ($list, $pid_hash);
    
    $list ||= [];

    foreach my $xwid(keys(%$object_cache)){
        my $pid = $object_cache->{$xwid}->{'pid'};
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

    warn "Adding client $id" if $CACHE_DEBUG;
    $object_cache->{$id} = {
        'object'  => $client,
        'pid'     => $pid,
        'actions' => [ @actions ],
    };
    $self->{'_self_windows'}->{$id} = $id;

    return 1;
}

sub _internal_get_cache_with_id{
    my ($self, $id, $entry) = @_;

    if($id){
        $entry = $object_cache->{$id};
    }else{
        $entry = undef;
    }

    return $entry;
}

sub get_client_with_id{
    my ($self, $id) = @_;

    my $entry = $self->_internal_get_cache_with_id($id);
    return unless $entry;

    return $entry->{'object'};
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

    my $client = $self->_internal_get_client_for_action_pid($object_cache, $requested_action, $pid);

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
        warn "Client Window id != hash key id" if ($id ne $wid);
        delete $object_cache->{$id};
        delete $self->{'_self_windows'}->{$id};
    }

    return;
}

sub remove_clients_to_bad_windows{
    my ($self) = @_;

    warn "cleaning up any bad windows" if $CACHE_DEBUG;
    foreach my $id(keys(%$object_cache)){
        if(my $xr = $object_cache->{$id}->{'object'}){
            if ($xr->ping) {
                warn sprintf "  client '%s' not bad", $id if $CACHE_DEBUG;
            } else {
                warn sprintf "  removing bad client '%s'", $id if $CACHE_DEBUG;
                delete $object_cache->{$id};
                delete $self->{'_self_windows'}->{$id};
            }
        }else{
            delete $object_cache->{$id};
            delete $self->{'_self_windows'}->{$id};
        }
            
    }
    return;
}

sub create_client_with_pid_id_actions{
    my ($self, $requested_pid, $requested_id, @actions) = @_;
    my $cached_id;

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

    print Dumper $object_cache if $CACHE_DEBUG;

    return;
}

1;
