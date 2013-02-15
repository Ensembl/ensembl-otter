### MenuCanvasWindow::ZMapSeqChooser

package MenuCanvasWindow::ZMapSeqChooser;

use strict;
use warnings;
use Carp;
use Try::Tiny;
use Data::Dumper;
use XML::Simple;
use POSIX ();
use Scalar::Util qw( weaken );

use Hum::XmlWriter;

use X11::XRemote;
use Bio::Otter::ZMap::Connect;
use Bio::Otter::Utils::Config::Ini qw( config_ini_format );
use Bio::Vega::Utils::XmlEscape qw{ xml_escape };
use Bio::Vega::Utils::MacProxyConfig qw{ mac_os_x_set_proxy_vars };

my $ZMAP_DEBUG = $ENV{OTTERLACE_ZMAP_DEBUG};

$Data::Dumper::Terse = 1;
$Data::Dumper::Indent = 1;

sub new {
    my ($pkg, @args) = @_;
    my $new = bless { }, $pkg;
    $new->_init(@args);
    return $new;
}

sub _init {
    my ($self, $SessionWindow, %args) = @_;
    $self->{_SessionWindow} = $SessionWindow;
    weaken $self->{_SessionWindow};
    @{$self}{qw( conf_dir arg_list )} =
        @args{qw( -conf_dir -arg_list )};
    $self->{_zMap_ZMAP_CONNECTOR} =
        $self->zMapZmapConnectorNew;
    $self->{'action_client_hash'} = { };
    $self->{'name_client_hash'} = { };
    $self->_launchZMap;
    return;
}

=head2 launch_zmap

This is where it all starts.  This is the method which gets called
on 'Launch ZMap' menu item in the session window.

=cut

=head2 _launchZMap

The guts of the code to launch and display the features in a zmap.

=cut

sub _launchZMap {
    my ($self) = @_;

    if ($^O eq 'darwin') {
        # Sadly, if someone moves network after launching zmap, it
        # won't see new proxy variables.
        mac_os_x_set_proxy_vars(\%ENV);
    }

    my $win_id = $self->zMapZmapConnector->server_window_id;
    my $arg_list = $self->arg_list;

    my @e = (
        'zmap',
        '--conf_dir' => $self->conf_dir,
        '--win_id'   => $win_id,
        ($arg_list ? @{$arg_list} : ()),
    );

    warn "Running: @e\n";

    my $pid = fork;
    if ($pid) {
        $self->zMapPID($pid);
        return;
    }
    confess "Error: couldn't fork()\n" unless defined $pid;

    { exec @e; }
    # DUP: EditWindow::PfamWindow::initialize $launch_belvu
    # DUP: Hum::Ace::LocalServer
    warn "exec '@e' failed : $!";
    close STDERR; # _exit does not flush
    close STDOUT;
    POSIX::_exit(127); # avoid triggering DESTROY

    return; # unreached, quietens perlcritic
}

=head2 launch_zmap

Launches zmap, displaying the features of $self->slice_name(), killing
an existing one if it exists.

=cut

sub launch_zmap {
    my ($self) = @_;

    my $relaunch = 1;

    if (!$self->_kill_zmap($relaunch)) {
        $self->_launchZMap();
    }

    return;
}

sub send_commands {
    my ($self, @xml) = @_;

    my $xr = $self->zMapGetXRemoteClientByName($self->slice_name());
    unless ($xr) {
        my $for = $self->slice_name();
        die "send_commands cannot contact ZMap: no current window for $for";
    }
    warn "Sending window '", $xr->window_id, "' this xml:\n", @xml;

    my @a = $xr->send_commands(@xml);

    my @err;
    warn "OK?  There was no answer\n" unless @a;
    for(my $i = 0; $i < @xml; $i++){
        my ($status, $xmlHash) = zMapParseResponse($a[$i]);
        if ($status =~ /^2\d\d/) { # 200s
            warn "OK\n";
        } else {
            my $error = $xmlHash->{'error'}{'message'};
            warn "ERROR: $a[$i]\n$error\n";
            push @err, $error;
        }
    }
    if (@err) {
        my $msg = join "\n", map {"[$_]"} @err;
        $msg =~ s{\n*\z}{};
        die "ZMap commands failed: $msg\n";
    }

    return;
}

=head2 zMapFinalised

A  handler to  handle finalise  requests. ZMap  sends these  when it's
closing the  whole program. Depending  on whether we want  to relaunch
zmap might be launched again.

=cut

sub zMapFinalised {
    my ($self, $xml) = @_;
    if ($self->{'_relaunch_zmap'}) {
        $self->_launchZMap();
        $self->{'_relaunch_zmap'} = 0;
    }
    return (200, "all closed");
}

=head2 _kill_zmap

Attempts  to kill  zmap,  return true  if  it succeeded  and false  on
failure.  If relaunch = true and _kill_zmap returns true then zmap
should relaunch, any other combination probably means no relaunch will
occur. There will still be a call to RelaunchZMap though as a finalised
request will be sent from zmap.

=cut

sub _kill_zmap {
    my ($self, $relaunch) = @_;

    ### We're only using the pid as marker for zmap having been started
    if (my $pid = $self->zMapPID) {
        my $rval             = 0;
        my $main_window_name = $self->main_window_name();

        warn "Looking for $main_window_name";

        if (my $xr = $self->zMapGetXRemoteClientByName($main_window_name)) {

            # check we can ping...
            if ($xr->ping()) {
                warn "Ping OK - sending 'shutdown'";
                $self->{'_relaunch_zmap'}    = $relaunch;

                $xr->send_commands('<zmap><request action="shutdown"/></zmap>');

                $rval = 1;    # everything has been as successful as can be
                ### Check shutdown by checking property set by ZMap?
                ### This is done in zMapFinalised...
            }
            else {

                # zmap probably died without sending us a message... seg fault...
                warn sprintf "Failed to ping %s, zmap probably crashed.", $xr->window_id();
                $rval = 0;
            }
        }

        warn sprintf "finishing %s", "_kill_zmap";

        return $rval;
    }

    return 0;
}

=head2 zMapPID

Stores the process id for zmap.

=cut

sub zMapPID {
    my ($self, $zmap_process_id) = @_;

    if ($zmap_process_id) {
        $self->{'_zMap_ZMAP_PROCESS_ID'} = $zmap_process_id;
    }
    return $self->{'_zMap_ZMAP_PROCESS_ID'};
}

sub zMapXRemoteClients {
    my ($self) = @_;
    return $self->{'_zMap_ZMAP_XREMOTE_CLIENTS'} ||= { };
}

=head2 zMapZmapConnector

This is the way we receive commands from zmap.

=cut

sub zMapZmapConnector {
    my ($self) = @_;
    my $zc = $self->{_zMap_ZMAP_CONNECTOR};
    return $zc;
}

sub zMapZmapConnectorNew {
    my ($self) = @_;
    my $mb = $self->SessionWindow->menu_bar();
    my $zc =
        Bio::Otter::ZMap::Connect->new(
            '-handler' => $self,
            '-tk'      => $mb,
        );
    return $zc;
}

#===========================================================

sub main_window_name {
    my ($self) = @_;
    my $name = 'ZMap port #' . $self->SessionWindow->AceDatabase->ace_server->port();
    return $name;
}

=head2 zMapRegisterClient

A handler to handle register_client requests.

=cut

sub zMapRegisterClient {
    my ($self, $xml) = @_;

    my $zc = $self->zMapZmapConnector;

    unless ($xml->{'request'}->{'client'}->{'xwid'}
        && $xml->{'request'}->{'client'}->{'request_atom'}
        && $xml->{'request'}->{'client'}->{'response_atom'})
    {
        warn "mismatched request for register_client:\n",
          "id, request and response required\n",
          "Got '${xml}'\n";
        return (403, $zc->basic_error("Bad Request!"));
    }

    $self->zMapProcessNewClientXML($xml, $self->main_window_name());

    $self->{'open_clones'} = 1;

    my $response_xml = $zc->client_registered_response;

    return (200, $response_xml);
}

=head2 zMapEdit

A handler to handle edit requests.  Returns a basic response.

=cut

sub zMapEdit {
    my ($self, $xml_hash) = @_;
    my $zc = $self->zMapZmapConnector;
    my $response = $self->_zMapEdit($xml_hash);
    return (200, $zc->handled_response($response));
}

sub _zMapEdit {
    my ($self, $xml_hash) = @_;
    $xml_hash->{'request'}->{'action'} eq 'edit'
        or confess "Not an 'edit' action";
    my $feat_hash = $xml_hash->{'request'}{'align'}{'block'}{'featureset'}{'feature'};
    $feat_hash or return 0;
    my ($name, $feat) = %$feat_hash;
    my ($style, $sub_list) = @{$feat}{qw( style subfeature )};
    return $self->SessionWindow->zircon_zmap_view_edit($name, $style, $sub_list);
}

=head2 zMapSingleSelect

A handler to handle single_select.  returns a basic response.

=cut

sub zMapSingleSelect {
    my ($self, $xml_hash) = @_;
    my $zc = $self->zMapZmapConnector;
    my $features_hash =
        $xml_hash->{'request'}{'align'}{'block'}{'featureset'}{'feature'} || {};
    $self->SessionWindow->zircon_zmap_view_single_select(
        [ keys %$features_hash ]);
    return (200, $zc->handled_response(1));
}

=head2 zMapMultipleSelect

A handler to handle multiple_select requests.  returns a basic
response.

=cut

sub zMapMultipleSelect {
    my ($self, $xml_hash) = @_;
    my $zc = $self->zMapZmapConnector;
    my $features_hash =
        $xml_hash->{'request'}{'align'}{'block'}{'featureset'}{'feature'} || {};
    $self->SessionWindow->zircon_zmap_view_multiple_select(
        [ keys %$features_hash ]);
    return (200, $zc->handled_response(1));
}

=head2 zMapFeatureDetails

A  handler  to handle  feature_details  request.   returns a  notebook
response.

=cut

sub zMapFeatureDetails {
    my ($self, $xml_hash) = @_;

    my $feature_details_xml =
        $self->_zMapFeatureDetailsXml($xml_hash);
    my $handled = $feature_details_xml ? 'true' : 'false';

    my $xml = Hum::XmlWriter->new;
    $xml->open_tag('response', { handled => $handled });
    $xml->add_raw_data($feature_details_xml)
        if $feature_details_xml;
    $xml->close_all_open_tags;

    return (200, $xml->flush);
}

sub _zMapFeatureDetailsXml {
    my ($self, $xml_hash) = @_;
    return unless $xml_hash->{'request'}->{'action'} eq 'feature_details';
    my $feature_hash = $xml_hash->{'request'}{'align'}{'block'}{'featureset'}{'feature'};
    return unless $feature_hash && keys %{$feature_hash};
    my $feature_details_xml =
        $self->SessionWindow->zircon_zmap_view_feature_details_xml(%{$feature_hash});
    return $feature_details_xml;
}

sub zMapViewClosed {
    my ($self, $xml) = @_;
    my $zc = $self->zMapZmapConnector;
    return (200, $zc->handled_response(1));
}

sub zMapFeaturesLoaded {
    my ($self, $xml) = @_;

    my @featuresets = split(/;/, $xml->{'request'}{'featureset'}{'names'});

    my $status  = $xml->{'request'}{'status'}{'value'};
    my $message = $xml->{'request'}{'status'}{'message'};

    $self->SessionWindow->zircon_zmap_view_features_loaded($status, $message, @featuresets);

    return (200, $self->zMapZmapConnector->handled_response(1));
}

sub zMapIgnoreRequest {
    my ($self) = @_;

    return(200, $self->zMapZmapConnector->handled_response(0));
}

my $action_method_hash = {
    register_client => 'zMapRegisterClient',
    edit            => 'zMapEdit',
    single_select   => 'zMapSingleSelect',
    multiple_select => 'zMapMultipleSelect',
    finalised       => 'zMapFinalised',
    feature_details => 'zMapFeatureDetails',
    view_closed     => 'zMapViewClosed',
    features_loaded => 'zMapFeaturesLoaded',
};

sub xremote_callback {
    my ($self, $reqXML) = @_;

    my $action = $reqXML->{'request'}{'action'};
    warn sprintf
        "\n_zmap_request_callback:\naction: %s\nrequest:\n>>>\n%s\n<<<\n",
        $action, Dumper($reqXML)
        if $ZMAP_DEBUG;

    my $method = $action_method_hash->{$action};
    my @result =
        $method
        ? $self->$method($reqXML)
        : (404, $self->zMapZmapConnector->basic_error("Unknown Command"));

    warn sprintf
        "\n_zmap_request_callback\nstatus:%d\nresponse\n>>>\n%s\n<<<\n"
        , @result
        if $ZMAP_DEBUG;

    return @result;
}

sub xremote_callback_post {
    my ($self) = @_;
    defined $self or return;
    if ($self->{'open_clones'}) {
        $self->{'open_clones'} = 0;
        $self->zMapOpenClones;
    }
    return;
}

sub zMapGetXRemoteClientByName {
    my ($self, $key) = @_;
    my $client = $self->{'name_client_hash'}{$key};
    return $client;
}

sub zMapGetXRemoteClientByAction {
    my ($self, $key) = @_;
    my $client = $self->{'action_client_hash'}{$key};
    return $client;
}

sub zMapOpenClones {
    my ($self) = @_;
    my $xremote = $self->zMapGetXRemoteClientByName($self->main_window_name());
    return unless $self->zMapDoRequest($xremote, "new_zmap", qq!<zmap><request action="new_zmap"/></zmap>!);
    $xremote = $self->zMapGetXRemoteClientByName("ZMap");
    $self->zMapRegisterClientRequest($xremote);
    $self->zMapNewView($xremote);
    return;
}

sub zMapRegisterClientRequest {
    my ($self, $xremote) = @_;

    my $zmap = $self->zMapZmapConnector;
    $self->zMapDoRequest($xremote, "register_client", $zmap->connect_request());

    return;
}

sub get_mark {

    my ($self) = @_;

    if (my $client = $self->zMapGetXRemoteClientByAction('get_mark')) {

        my $xml = qq(<zmap><request action="get_mark" /></zmap>);

        my ($response) = $client->send_commands($xml);

        my ($status, $hash) = zMapParseResponse($response);

        if ($status =~ /^2/ && $hash->{response}->{mark}->{exists} eq "true") {

            my $start = abs($hash->{response}->{mark}->{start});
            my $end   = abs($hash->{response}->{mark}->{end});

            if ($end < $start) {
                ($start, $end) = ($end, $start);
            }

            return ($start, $end);
        }
    }
    else {
        warn "Failed to get client for 'get_mark'";
    }

    return;
}

sub load_features {
    my ($self, @featuresets) = @_;

    if (my $client = $self->zMapGetXRemoteClientByAction('load_features')) {

        my $xml = Hum::XmlWriter->new;
        $xml->open_tag('zmap');
        $xml->open_tag('request',
                       {
                           action => 'load_features',
                           # load => 'mark', # not used at the moment
                       });
        $xml->open_tag('align');
        $xml->open_tag('block');
        foreach my $fs_name (@featuresets) {
            $xml->open_tag('featureset', { name => $fs_name });
            $xml->close_tag;
        }
        $xml->close_all_open_tags;

        my ($response) = $client->send_commands($xml->flush);

        my ($status, $hash) = zMapParseResponse($response);

        unless ($status =~ /^2/) {
            warn "Problem loading featuresets";
        }
    }
    else {
        warn "Failed to get client for 'load_features'";
    }

    return;
}

sub delete_featuresets {
    my ($self, @featuresets) = @_;

    if (my $client = $self->zMapGetXRemoteClientByAction('delete_feature')) {

        my $xml = Hum::XmlWriter->new;
        $xml->open_tag('zmap');
        $xml->open_tag('request', { action => 'delete_feature' });
        $xml->open_tag('align');
        $xml->open_tag('block');

        for my $featureset (@featuresets) {
            $xml->open_tag('featureset', { name => $featureset });
            $xml->close_tag;
        }
        $xml->close_all_open_tags;

        my ($response) = $client->send_commands($xml->flush);

        my ($status, $hash) = zMapParseResponse($response);

        unless ($status =~ /^2/) {
            unless ($hash->{error}->{message} =~ /Unknown FeatureSet/) {

                # XXX: temporarily ignore this error message, as we want to be able to call
                # delete_feature on featuresets that aren't currently in the zmap window
                warn "Problem deleting featuresets: " . $hash->{error}->{message};
            }
        }
    }
    else {
        warn "Failed to get client for 'delete_feature'";
    }

    return;
}

sub zoom_to_subseq {

    my ($self, $subseq) = @_;

    if (my $client = $self->zMapGetXRemoteClientByAction('zoom_to')) {
        my $xml = Hum::XmlWriter->new;
        $xml->open_tag('zmap');
        $xml->open_tag('request', { action => 'zoom_to' });
        $xml->open_tag('align');
        $xml->open_tag('block');
        $xml->open_tag('featureset', { name => $subseq->GeneMethod->name });
        $subseq->zmap_xml_feature_tag($xml, $self->SessionWindow->AceDatabase->offset);
        $xml->close_all_open_tags;

        my $command = $xml->flush;
        my ($response) = $client->send_commands($command);
        my ($status, $hash) = zMapParseResponse($response);
        if ($status =~ /^2/ && $hash->{response} =~ /executed/) {
            return 1;
        }
    }
    else {
        warn "Failed to get client for 'zoom_to'";
    }

    return 0;
}

my $zmap_new_view_xml_format = <<'FORMAT'
<zmap>
 <request action="new_view">
  <segment sequence="%s" start="%d" end="%d">
%s
  </segment>
 </request>
</zmap>
FORMAT
    ;

sub _zmap_new_view_xml {
    my ($self, $config) = @_;

    my $slice = $self->SessionWindow->AceDatabase->smart_slice;

    my $segment = $slice->ssname;
    my $start   = $slice->start;
    my $end     = $slice->end;

    my @fields = ( $segment, $start, $end, $config );
    my @xml_escaped_fields = map { xml_escape($_) } @fields;
    my $xml = sprintf $zmap_new_view_xml_format, @xml_escaped_fields;

    return $xml;
}

sub zMapNewView {
    my ($self, $xremote, $config) = @_;

    $config = "" unless defined $config;

    my $new_view_xml = $self->_zmap_new_view_xml($config);
    unless ($self->zMapDoRequest($xremote, "new_view", $new_view_xml)) {
        warn "Failed to create a new view";
        return;
    }

    my $xremote_new = $self->zMapGetXRemoteClientByName($self->slice_name);
    unless ($xremote_new) {
        warn "Failed to find the new xremote client";
        return;
    }
    $self->zMapRegisterClientRequest($xremote_new);

    return;
}

=head2 zMapDoRequest

return true for success

=cut

sub zMapDoRequest {
    my ($self, $xremote, $action, $command) = @_;

    warn sprintf "\nzMapDoRequest:command\n>>>\n%s\n<<<\n", $command if $ZMAP_DEBUG;
    my ($response) = $xremote->send_commands($command);
    warn sprintf "\nzMapDoRequest:response\n>>>\n%s\n<<<\n", $response if $ZMAP_DEBUG;

    my ($status, $xmlHash) = zMapParseResponse($response);
    if ($status =~ /^2\d\d/) {    # 200s
        if ($action eq 'new_zmap') {
            $self->zMapProcessNewClientXML($xmlHash, "ZMap");
        }
        elsif ($action eq 'new_view') {
            $self->zMapProcessNewClientXML($xmlHash, $self->slice_name());
        }
        elsif ($action eq 'list_windows') {
            $self->zMapProcessNewClientXML($xmlHash, "ZMapWindow");
        }
        return 1;
    }
    else {
        return 0;
    }
}

sub zMapProcessNewClientXML {
    my ($self, $xml, $lookup_key) = @_;

    my ($client_tag, $id);

    if (exists($xml->{'response'})) {
        $client_tag = $xml->{'response'}->{'client'};
    }
    else {
        $client_tag = $xml->{'request'}->{'client'};
    }

    if ($client_tag) {
        my $client_array = [];
        my $add_counter  = 0;
        my $counter      = 0;
        my $full_key     = $lookup_key;

        if (ref($client_tag) eq 'ARRAY') {
            $client_array = $client_tag;
            $add_counter  = 1;
        }
        else {
            $client_array = [$client_tag];
        }

        foreach my $client (@{$client_array}) {
            $full_key = "$lookup_key.$counter" if ($add_counter);
            if ($id = $client->{'xwid'}) {

                # get actions array from xml.
                my @actions = qw();
                my $subtag  = q!action!;
                if (ref($client->{$subtag}) eq 'ARRAY') {
                    push(@actions, @{ $client->{$subtag} });
                }
                elsif (defined($client->{$subtag}) && !ref($client->{$subtag})) {
                    push(@actions, $client->{$subtag});
                }
                else {
                    warn "Odd for a client to not have actions.";
                }

                my $xr =
                    X11::XRemote->new(
                        -id     => $id, 
                        -server => 0,
                    );
                $self->{'action_client_hash'}{$_} = $xr for @actions;
                $self->{'name_client_hash'}{$full_key} = $xr;
            }
            $counter++;
        }
    }
    else {
        warn "malformed register client xml [no window id]";
    }

    return;
}

sub zMapParseResponse {
    my ($response) = @_;
    my $delimit  = X11::XRemote::delimiter();
    my ($status, $xml) = split(/$delimit/, $response, 2);
    my $hash   = XMLin($xml);
    return ($status, $hash);
}

sub slice_name {
    my ($self) = @_;
    my $slice_name = $self->SessionWindow->slice_name;
    return;
}

sub SessionWindow {
    my ($self) = @_;
    my $SessionWindow = $self->{'_SessionWindow'};
    return $SessionWindow;
}

sub conf_dir {
    my ($self) = @_;
    my $conf_dir = $self->{'conf_dir'};
    return $conf_dir;
}

sub arg_list {
    my ($self) = @_;
    my $arg_list = $self->{'arg_list'};
    return $arg_list;
}

sub DESTROY {
    my ($self) = @_;
    $self->_kill_zmap;
    delete $self->{_zMap_ZMAP_CONNECTOR};
    return;
}

1;

__END__


=head1 NAME - MenuCanvasWindow::ZmapSeqChooser

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut
