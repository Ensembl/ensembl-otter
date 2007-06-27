
package ZMap::XRemoteCache;

use strict;
use warnings;

use X11::XRemote;

# self = { 
#     _clients => {
#         '<WindowID>' => <X11::XRemote>instance
#     },
#     _name2id => {
#         '<Name>' => '<WindowID>',
#     }
# }

sub new{
    my $pkg = shift;
    my $self = {};
    $self->{'_clients'} ||= {};
    $self->{'_name2id'} ||= {};
    $self->{'_id2name'} ||= {};
    return bless($self, $pkg);
}

sub add_client_with_name{
    my ($self, $client, $name) = @_;

    warn "name is required"     if(!defined($name));
    warn "client is required"    if(!defined($client));
    
    my $id = $client->window_id();

    warn "Are you _really_ sure? (client with id '$id' already exists)"    if($self->get_client_with_id($id));
    
    $self->{'_clients'}->{$id}   = $client;
    $self->{'_name2id'}->{$name} = $id;
    $self->{'_id2name'}->{$id}   = $name;

    return 1;
}

sub get_client_with_id{
    my ($self, $id, $client) = @_;
    if($id){
        $client = $self->{'_clients'}->{$id};
    }else{
        $client = undef;
    }
    return $client;
}

sub get_client_with_name{
    my ($self, $name, $id) = @_;
    $id = $self->{'_name2id'}->{$name};
    return $self->get_client_with_id($id);
}

sub remove_client_with_id{
    my ($self, $id, $name) = @_;

    $name = $self->{'_id2name'}->{$id};

    $self->remove_client_with_name($name);

    return undef;
}

sub remove_client_with_name{
    my ($self, $name, $client) = @_;

    $client = $self->get_client_with_name($name);

    if($client){
        my $id = $client->window_id();
        delete $self->{'_id2name'}->{$id};
        delete $self->{'_name2id'}->{$name};
        delete $self->{'_clients'}->{$id};
    }

    return ;
}

sub create_client_with_name_id{
    my ($self, $requested_name, $requested_id) = @_;
    my ($cached_name, $cached_id);

    my $client = $self->get_client_with_name($requested_name);

    if($client){
        warn "Are you sure? (client with name '$requested_name' already exists)";
        $cached_id = $client->window_id();
        if($cached_id eq $requested_id){
            warn "identical";
        }else{
            warn "requested id != cached id so creating new X11::Xremote instance";
            $client = X11::XRemote->new(-id     => $requested_id, 
                                        -server => 0,
                                        -_DEBUG => 1);
            $self->add_client_with_name($client, $requested_name);            
        }
    }else{
        $client = $self->get_client_with_id($requested_id);
            
        if($client){
            warn "Are you sure? (client with id '$requested_id' already exists)";
            # cached_name cannot eq requested_name
        }else{
            $client = X11::XRemote->new(-id     => $requested_id, 
                                        -server => 0,
                                        -_DEBUG => 1);
            $self->add_client_with_name($client, $requested_name);
        }
    }

    return $client;
}

1;
