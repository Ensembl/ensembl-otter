use strict;
use warnings;

use X11::XRemote;
use Data::Dumper;
use Tk;

my $mw = MainWindow->new;

my $w = $mw->Label->pack;

$mw->withdraw;

my $app_xr;
my $disp_xr;
my $view_xr;
my $seq_xr;

my $xrs;

my $callback = sub { 
    my ($tk) = @_;
    print "in callback\n";

    my $evt = $tk->XEvent;

    return unless ($evt->d eq X11::XRemote::client_request_name);

    print "event was for us, request:\n",$xrs->request_string;
    
    my ($action) = $xrs->request_string =~ /action="(.+)"/;

    print "ACTION: $action\n";

    {
        no strict 'refs';
        X11::XRemote::block();
        &$action($xrs->request_string);
    }
}; 

$w->bind('<Property>', [$callback]);

my $win_id = $w->id;
$xrs = X11::XRemote->new(-server => 1, -id => $win_id);
$xrs->request_name(X11::XRemote::client_request_name);
$xrs->response_name(X11::XRemote::client_response_name);

if (my $pid = fork) {
    Tk::MainLoop;
}
else {
    print "win_id = $win_id\n";
    exec '/nfs/team71/analysis/gr5/new_zmap/bin/zmap', 
    '--conf_dir' => '/nfs/team71/analysis/gr5/for_ed/columns_order', 
    '--win_id'   => $win_id;
}

sub register_client {
    my $xml = shift;

    my ($id) = $xml =~ /client xwid="(.+)"/;
    $app_xr = X11::XRemote->new(-id => $id);

    my $response = qq(
        <zmap>
            <response>
                <client created="1" exists="1" />
            </response>
        </zmap>
    );

    $xrs->send_reply('200:'.$response);

    start_zmap();
}

sub multiple_select {
    return single_select(@_);
}

sub finalised {
    print "FINALISED\n";
    $xrs->send_reply('200:<zmap><response handled="true" /></zmap>');
}

sub single_select {

    my $xml = shift;

    print "USER CLICKED ON: \n$xml\n";

    my $response = qq(
        <zmap>
            <response handled="true" />
        </zmap>
    );

    $xrs->send_reply('200:'.$response);

    select_other();
}

sub select_other {

    my ($result) = $view_xr->send_commands(qq(
        <zmap> 
          <request action="delete_feature">
            <align>
              <block>
                <featureset name="vertebrate_mRNA">
                  <feature name="AK124141.1" strand="+" start="45045" end="49173"/>
                </featureset>
              </block>
            </align>
          </request>
        </zmap>
    ));

    print "MARK:\n",$result,"\n";
}

sub start_zmap {
    
    my $xml;

    ($xml) = $app_xr->send_commands(qq(<zmap><request action="new_zmap"/></zmap>));

    print "GOT THIS BACK: ",$xml,"\n";
    
    my ($id) = $xml =~ /client xwid="([^"]+)"/;
    $disp_xr = X11::XRemote->new(-id => $id);

    ($xml) = $disp_xr->send_commands(qq(
        <zmap>
            <request action="new_view">
                <segment sequence="chr11-03_64807407-64995340" start="1" end="" />
            </request>
        </zmap>
    ));
    
    ($id) = $xml =~ /client xwid="(.+)"/;
    $view_xr = X11::XRemote->new(-id => $id);

    my $req = qq(
        <zmap>
            <request action="register_client">
                <client xwid="$win_id" request_atom="%s" response_atom="%s"/>
            </request>
        </zmap>
    );

    ($xml) = $view_xr->send_commands(sprintf($req, X11::XRemote::client_request_name, X11::XRemote::client_response_name));
}

