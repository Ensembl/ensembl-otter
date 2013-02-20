package Bio::Otter::ZMap;

=head1 NAME - Bio::Otter::ZMap

=head1 DESCRIPTION

For  connecting  to ZMap  and  makes  the  X11::XRemote module  more
useable as a server.

=cut

use strict;
use warnings;

use feature qw( switch );

use Carp;
use Scalar::Util qw( weaken );
use POSIX ();
use Try::Tiny;

use XML::Simple;
use X11::XRemote;
use Tk::X;

my $DEBUG_CALLBACK = 0;
my $DEBUG_EVENTS   = 0;

=head1 METHODS

=head2 new

Creates a new Bio::Otter::ZMap Object.

=cut

sub new{
    my ($pkg, %arg_hash) = @_;
    my $self = { };
    bless($self, $pkg);
    $self->init(\%arg_hash);
    return $self;
}

# NB: sub init() calls wait() because some initialisation happens in
# XRemote callbacks and we must not return until it is all done.

sub init{
    my ($self, $arg_hash) = @_;
    my ($tk, $arg_list) =
        @{$arg_hash}{qw( -tk -arg_list )};
    my $widget = $self->{'_widget'} = $self->_widget($tk);
    my $self_ = $self; weaken $self_;
    $widget->bind('<Property>', [ \&_do_callback , $self_ ] );
    $self->{'_conf_dir'} = $self->_conf_dir;
    $self->_make_conf;
    $self->_launch_zmap($arg_list);
    $self->wait;
    return;
}

sub _conf_dir {
    my $conf_dir = q(/var/tmp);
    my $user = getpwuid($<);
    my $dir_name = "otter_${user}";
    my $key = sprintf "%09d", int(rand(1_000_000_000));
    for ($dir_name, 'ZMap', $key) {
        $conf_dir .= "/$_";
        -d $conf_dir
            or mkdir $conf_dir
            or die sprintf "mkdir('%s') failed: $!", $conf_dir;
    }
    return $conf_dir;
}

my $conf = <<'CONF'

[ZMap]
show-mainwindow = false
CONF
    ;

sub _make_conf {
    my ($self) = @_;
    my $conf_file = sprintf "%s/ZMap", $self->conf_dir;
    open my $conf_file_h, '>', $conf_file
        or die sprintf
        "failed to open the configuration file '%s': $!"
        , $conf_file;
    print $conf_file_h $conf;
    close $conf_file_h
        or die sprintf
        "failed to close the configuration file '%s': $!"
        , $conf_file;
    return;
}

sub _launch_zmap {
    my ($self, $arg_list) = @_;

    if ($^O eq 'darwin') {
        # Sadly, if someone moves network after launching zmap, it
        # won't see new proxy variables.
        mac_os_x_set_proxy_vars(\%ENV);
    }

    my @e = (
        'zmap',
        '--conf_dir' => $self->conf_dir,
        '--win_id'   => $self->server_window_id,
        ($arg_list ? @{$arg_list} : ()),
    );

    warn "Running: @e\n";

    my $pid = fork;
    confess "Error: couldn't fork()\n" unless defined $pid;
    return if $pid;

    { exec @e; }
    # DUP: EditWindow::PfamWindow::initialize $launch_belvu
    # DUP: Hum::Ace::LocalServer
    warn "exec '@e' failed : $!";
    close STDERR; # _exit does not flush
    close STDOUT;
    POSIX::_exit(127); # avoid triggering DESTROY

    return; # unreached, quietens perlcritic
}

sub _kill_zmap {
    my ($self) = @_;
    my $xremote = $self->{'_xremote_client_app'};
    if ($xremote->ping) {
        warn "Ping OK - sending 'shutdown'";
        $xremote->send_commands('<zmap><request action="shutdown"/></zmap>');
    }
    else {
        # zmap probably died without sending us a message... seg fault...
        warn sprintf
            "Failed to ping %s, zmap probably crashed."
            , $xremote->window_id();
    }
    return;
}

sub register_client {
    my ($self, $request) = @_;
    my $id = $request->{'request'}{'client'}{'xwid'};
    $self->{'_xremote_client_app'} = $self->xremote_client_new($id);
    my $response_xml = $self->client_registered_response;
    return (200, $response_xml);
}

sub register_client_post {
    my ($self) = @_;
    my ($response, $status, $hash);
    my $command = qq!<zmap><request action="new_zmap"/></zmap>!;
    my $app_xremote = $self->{'_xremote_client_app'};
    ($response) = $self->send_commands($app_xremote, $command);
    ($status, $hash) = @{$response};
    $status =~ /^2/
        or die "register_client_post(): 'new_zmap' failed\n";
    my $id = $hash->{'response'}{'client'}{'xwid'}
    or die "register_client_post(): missing window ID\n";
    my $window_xremote = 
        $self->{'_xremote_client_window'} =
        $self->xremote_client_new($id);
    $self->send_commands($window_xremote, $self->connect_request);
    $self->wait_finish;
    return;
}

my $new_view_xml_format = <<'FORMAT'
<zmap>
 <request action="new_view">
  <segment sequence="%s" start="%d" end="%d" config-file="%s">
  </segment>
 </request>
</zmap>
FORMAT
    ;

sub new_view {
    my ($self, $view) = @_;

    $view or confess "no view object supplied";
    $self->{'view'} = $view;
    weaken $self->{'view'};

    my ($response, $status, $hash);

    my $window_xremote = $self->{'_xremote_client_window'};
    my $parameter_hash = $view->zmap_new_view_parameter_hash;
    my @parameter_list = @{$parameter_hash}{qw( sequence start end config_file )};
    my $new_view_xml =
        sprintf $new_view_xml_format, map { xml_escape($_) } @parameter_list;
    ($response) = $self->send_commands($window_xremote, $new_view_xml);
    ($status, $hash) = @{$response};
    $status =~ /^2/
        or die "new_view(): 'new_view' failed\n";
    my $id = $hash->{'response'}{'client'}{'xwid'}
        or die "register_client_post(): missing window ID\n";

    my $view_xremote = $self->xremote_client_new($id);
    $self->send_commands($view_xremote, $self->connect_request);

    $view->xremote($view_xremote);

    return;
}

sub xremote_client_new {
    my ($self, $id) = @_;
    my $xremote =
        X11::XRemote->new(
            -id     => $id, 
            -server => 0,
        );
    return $xremote;
}

=head2 connect_request

This maybe  used to  get the  string for registering  the server  as a
remote window  of the  zmap client.  ZMap  should honour  this request
creating a  client with  the window  id of the  request widget  as its
remote window.

=cut

sub connect_request{
    my ($self) = @_;

    my $fmt = q!<zmap>
 <request action="%s">
  <client xwid="%s" request_atom="%s" response_atom="%s"/>
 </request>
</zmap>!;

    return sprintf($fmt, 
                   "register_client", 
                   $self->server_window_id, 
                   $self->request_name,
                   $self->response_name
                   );
}

sub client_registered_response{
    my ($self) = @_;

    my $out  = {
        response => {
            client => [
                {
                    created => 1,
                    exists  => 1,
                }
            ]
        }
    };
    $self->protocol_add_meta($out);
    my $reponse =make_xml($out);

    return $reponse;
}

=head2 server_window_id

Just the window id of the request widget.

=cut


sub server_window_id{
    my ($self) = @_;
    return $self->widget->id();
}

=head2 xremote

The xremote Object [C<<< X11::XRemote >>>].

=cut

sub xremote_server{
    my ($self, $id) = @_;
    my $xr = $self->{'_xremote_server'};
    return $xr;
}



=head1 ERROR

 Currently just the one to help the user with consistency.

=head2 basic_error

Some xml which should be used in callback for error messages.

 sub cb {
   ...
   # On error
   my $errno = 404;
   my $xml = $Connect->basic_error("Unknown Command"); 
   ...
   return ($errno, $xml);
 }

=cut

sub handled_response {
    my ($self, $value) = @_;

    my $hash = {
        response => {
                handled => $value ? 1 : 0,
            }
        };
#    $self->protocol_add_request($hash);
    $self->protocol_add_meta($hash);
    return make_xml($hash);
}

sub basic_error {
    my ($self, $message) = @_;

    $message ||=  (caller(1))[3] . " was lazy";

    my $hash   = { 
        error => {
            message => [ $message ],
        }
    }; 
    $self->protocol_add_request($hash);
    $self->protocol_add_meta($hash);
    return make_xml($hash);
}

sub protocol_add_request {
    my ($self, $hash) = @_;

    $hash->{'request'} = [ xml_escape($self->_current_request_string) ];

    return;
}

sub protocol_add_meta {
    my ($self, $hash) = @_;

    $hash->{'meta'} = {
        display     => $ENV{DISPLAY},
        windowid    => $self->server_window_id,
        application => $self->xremote_server->application,
        version     => $self->xremote_server->version,
    };

    return;
}

sub request_name{
    return X11::XRemote::client_request_name;
}

sub response_name{
    return X11::XRemote::client_response_name;
}

sub widget{
    my ($self) = @_;
    my $widget = $self->{'_widget'};
    return $widget;
}

sub _widget{
    my ($self, $tk) = @_;
    my $qName = $self->request_name();
    my $sName = $self->response_name();
    # we create a new widget so our binding stay alive
    # and our users bindings don't get trampled on.
    my $widget =
        $tk
        ->Label( -text => "${qName}|${sName}|Widget" )
        ->pack(-side => 'left');

    # we need to wait until the widget is mapped by the x server so that we 
    # can reliably initialise the xremote protocol so we must wait for the
    # <Map> event

    my $mapped; # a flag used in waitVariable below to indicate that the widget is mapped

    $widget->bind(
        '<Map>' =>
        sub {
            $widget->packForget;
            my $xr = $self->{'_xremote_server'} =
                X11::XRemote->new( -server => 1, -id => $widget->id, );
            $xr->request_name($self->request_name);
            $xr->response_name($self->response_name);
            $mapped = 1;
        });

    # this call will essentially block until the widget is mapped and the
    # xremote protocol is initialised (the tk event loop will continue though)
    $widget->waitVariable(\$mapped);

    return $widget;
}

# ======================================================== #
#                      INTERNALS                           #
# ======================================================== #

my @xml_request_parse_parameters =
    (
     KeyAttr    => { feature => 'name' },
     ForceArray => [ 'feature', 'subfeature' ],
    );

sub _do_callback{
    my ($tk, $self) = @_;
    defined $self or return;
    my $id    = $tk->id();
    my $ev    = $tk->XEvent(); # Get the event
    my $state = ($ev->s ? $ev->s : 0); # assume zero (PropertyDelete I think)
    my $reqnm = $self->request_name(); # atom name of the request
    if ($state == PropertyDelete){
        warn "Event had state 'PropertyDelete', returning...\n" if $DEBUG_EVENTS;
        return ; # Tk->break
    }
    #====================================================================
    # DEBUG STUFF
    warn "//========== _do_callback ========== window id: $id\n" if $DEBUG_CALLBACK;
    if($DEBUG_EVENTS){
        foreach my $m('a'..'z','A'..'Z','#'){
            warn "Event on method '$m' - ". $ev->$m() . " " .sprintf("0x%lx", $ev->$m) . " \n" if $ev->$m();
        }
    }
    unless($ev->T eq 'PropertyNotify'){ warn "Odd Not a propertyNotify\n"; }
    unless($ev->d eq $reqnm){
        warn "Event was NOT for this.\n" if $DEBUG_CALLBACK;
        return ; # Tk->break
    }
    my $request_string = $self->xremote_server->request_string();
    $self->_current_request_string($request_string);
    warn "Event has request string $request_string\n" if $DEBUG_CALLBACK;
    #=========================================================
    my $request = XMLin($request_string, @xml_request_parse_parameters);
    my $action = $request->{'request'}{'action'};
    my $view = $self->{'view'};
    my $reply =
        sprintf $self->xremote_server->format_string,
        ( try {
            X11::XRemote::block();
            for ($action) {
                when ('register_client') { return $self->register_client($request); }
                when ('finalised') { return (200, "all closed"); }
                default { return $view->xremote_callback($request); }
            }
          }
          catch {
              return ( 500, $self->basic_error("Internal Server Error $_") );
          } );

    $self->_drop_current_request_string;
    warn "Connect $reply\n" if $DEBUG_CALLBACK;
    $self->xremote_server->send_reply($reply);

    $self->register_client_post
        if defined $action && $action eq 'register_client';

    return;
}

sub _drop_current_request_string {
    my ($self) = @_;

    $self->{'_current_request_string'} = undef;

    return;
}

sub _current_request_string {
    my ($self, $str) = @_;

    if ($str) {
        $self->{'_current_request_string'} = $str;
    }
    return $self->{'_current_request_string'};
}

sub send_commands {
    my ($self, $xremote, @xml) = @_;
    my @response_list = map { parse_response($_) } $xremote->send_commands(@xml);
    return @response_list;
}

sub parse_response {
    my ($response) = @_;
    my $delimit  = X11::XRemote::delimiter();
    my ($status, $xml) = split(/$delimit/, $response, 2);
    my $hash = XMLin($xml);
    my $parse = [ $status, $hash ];
    return $parse;
}

sub wait {
    my ($self) = @_;
    $self->{'_wait'} = 1;
    $self->widget->waitVariable(\ $self->{'_wait'});
    return;
}

sub wait_finish {
    my ($self) = @_;
    $self->{'_wait'} = 0;
    delete $self->{'_wait'};
    return;
}

sub DESTROY{
    my ($self) = @_;
    warn "Destroying $self";
    $self->_kill_zmap;
    return;
}

sub make_xml{
    my ($hash) = @_;
    my $xml = XMLout($hash, rootname => q{}, keeproot => 1);
    return $xml;
}

my $xml_escape_parser = XML::Simple->new(NumericEscape => 1);
sub xml_escape{
    my ($data) = shift;
    my $escaped = $xml_escape_parser->escape_value($data);
    return $escaped;
}

sub conf_dir {
    my ($self) = @_;
    my $conf_dir = $self->{'_conf_dir'};
    return $conf_dir;
}

1;
__END__

=head1 A WORD OF WARNING

When  writing the callback to  be called  on receipt of a command, be
careful not to  send the origin window of the  command a command. This
will lead  to a race condition.   The original sender  will be waiting
for the reply  from the callback, while your window  will be sending a
command to a window which cannot respond.

The prevention of this race condition has been coded into this module
and the L<X11::XRemote> module and you will be warned of an C<Avoided 
race condition>.
problem.

The recommended solution to this common problem is to send yourself a
generated event.  This is very easy using L<Tk::event> and the C<<<
$widget->eventGenerate('<EVENT>', -when => 'tail') >>> function should
be sufficient for most cases.

 Example:

 my $callback = sub {
    my ($this, $request, $obj) = @_;
    if($request =~ /something_two_way/){
      $obj->widget->eventGenerate('<ButtonPress>', -when => 'tail');
    }
    return (200, "everything went well");
 };


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=head1 SEE ALSO

L<X11::XRemote>, L<Tk::event>, L<perl>.

=cut

