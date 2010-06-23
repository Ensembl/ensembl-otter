### MenuCanvasWindow::ZmapSeqChooser

package MenuCanvasWindow::XaceSeqChooser;

use strict;
use warnings;
use Carp qw{ cluck confess };
use ZMap::Connect qw{ :all };
use Sys::Hostname;
use ZMap::XRemoteCache;
use Data::Dumper;
use Hum::Conf qw{ PFETCH_SERVER_LIST };
use XML::Simple;
use File::Path 'mkpath';

my $ZMAP_DEBUG = 0;

#==============================================================================#
#
# WARNING: THESE ARE INJECTED METHODS!!!!
#  I HAVE PREFIXED THEM ALL WITH zMap SO NONE SHOULD CLASH
#  BUT ALL WILL NEED CHANGING LATER (RDS)
#
#==============================================================================#

=pod

=head1 WARNING

This modules injects methods into the MenuCanvasWindow::XaceSeqChooser
namespace.  All have  been prefixed with "zMap" to  avoid any clashes,
but this isn't a long term solution.

=head1 zMapLaunchZmap

This is where it all starts.  This is the method which gets called
on 'Launch ZMap' menu item in xaceseqchooser window.

=cut

sub zMap_make_exoncanvas_edit_window {
    my ($self, $sub) = @_;

    my $sub_name = $sub->name;
    warn "subsequence-name $sub_name ";

    #    warn "locus " . $sub->Locus->name ;
    my $canvas = $self->canvas;

    # Make a new window
    my $top = $canvas->Toplevel;

    # Make new MenuCanvasWindow::ExonCanvas object and initialize
    my $ec = MenuCanvasWindow::ZMapExonCanvas->new($top, 345, 50);
    $ec->name($sub_name);
    $ec->XaceSeqChooser($self);
    $ec->SubSeq($sub);
    $ec->initialize;

    $self->save_subseq_edit_window($sub_name, $ec);

    return $ec;
}

=head1 _launchZMap

The guts of the code to launch and display the features in a zmap.

=cut

sub _launchZMap {
    my ($self) = @_;

    my $zmap_conn = $self->zMapInsertZmapConnector();

    unless ($self->xremote_cache()) {
        $self->xremote_cache(ZMap::XRemoteCache->new());
    }

    my @e = (
        'zmap',
        '--conf_dir' => $self->zMapZmapDir,
        '--win_id'   => $zmap_conn->server_window_id
    );
    warn "Running @e";
    my $pid = fork_exec(\@e);

    if ($pid) {
        $self->zMapPID($pid);
    }
    else {
        my $mess = "Error: couldn't fork()\n";
        warn $mess;
        $self->message($mess);
    }
}

=head1 zMapLaunchZmap

Launches zmap, displaying the features of $self->slice_name(), killing
an existing one if it exists.

=cut

sub zMapLaunchZmap {
    my ($self) = @_;

    my $relaunch = 1;

    if (!$self->zMapKillZmap($relaunch)) {
        $self->_launchZMap();
    }

    return;
}

=head1 zMapLaunchInAZmap

Uses an existing ZMap to display the features of $self->slice_name().

=cut

sub zMapLaunchInAZmap {
    my ($self) = @_;

    # If we already have a Zmap attached, shut it down
    if (!$self->zMapKillZmap(0, 1)) {
        $self->_launchInAZMap();
    }
}

=head1 _launchInAZMap

The real part of zMapLaunchInAZmap()

=cut

sub _launchInAZMap {
    my ($self) = @_;

    my $xremote_cache = $self->xremote_cache;
    $xremote_cache ||= $self->xremote_cache(ZMap::XRemoteCache->new());

    if (my $pid_list = $xremote_cache->get_pid_list()) {
        if (scalar(@$pid_list) == 1) {
            my $pid = $pid_list->[0];
            if ($self->zMapGetXRemoteClientByName($self->slice_name())) {
                $self->message(sprintf("Already launched in zmap with pid %d", $pid));
            }
            elsif (my $xr = $xremote_cache->get_client_for_action_pid("new_view", $pid)) {
                $self->zMapPID($pid);

                my $sequence = $self->slice_name;
                my $server   = $self->AceDatabase->ace_server;
                my $protocol = 'acedb';

                my $url = sprintf(q{%s://%s:%s@%s:%d?use_methods=true},
                    $protocol, $server->user, $server->pass, $server->host, $server->port);

                my $config = $self->formatZmapDefaults('ZMap', sources => "$sequence");
                $config .= $self->zMapServerDefaults();
                $config =~ s/\&/&amp;/g;    # needs fully xml escaping really

                my $xml = sprintf(
                    q!<zmap>
 <request action="new_view">
  <segment sequence="%s" start="1" end="0">
   %s
  </segment>
 </request>
</zmap>
                                  !, $sequence, $config
                );
                warn $xml;
                $self->zMapDoRequest($xr, "new_view", $xml);

                if ($xr = $self->zMapGetXRemoteClientByName($self->slice_name())) {
                    $self->zMapRegisterClientRequest($xr);
                }
                else {
                    cluck "Failed to find the new xremote client";
                }
            }
            else {

                # couldn't find a client who can new_view, probably need to
                my $zmap = $self->zMapZmapConnector();
                open_clones($zmap, $self);
            }
        }
        elsif (scalar(@$pid_list) == 0) {
            cluck "Process id list is empty. Is zmap running?";
        }
        else {
            cluck "More than one process id in list, How to choose?";
        }
    }
    else { cluck "Failed to get a process id list from the cache. Is zmap running?"; }

    return;
}

=head1 post_response_client_cleanup

A function to cleanup any bad windows that might exist.
Primary user of this is the zMapRelaunchZMap function.

=cut

sub post_response_client_cleanup {
    my ($zmap, $self) = @_;
    $zmap->post_respond_handler();
    $self->xremote_cache->remove_clients_to_bad_windows();
    return;
}

=head1 post_response_client_cleanup_launch_in_a_zmap

Cleanup any bad windows that might exist & call _launchInAZMap

=cut

sub post_response_client_cleanup_launch_in_a_zmap {
    my ($zmap, $self) = @_;

    post_response_client_cleanup($zmap, $self);

    $self->_launchInAZMap();

    return;
}

=head1 zMapRelaunchZMap

A  handler to  handle finalise  requests. ZMap  sends these  when it's
closing the  whole program. Depending  on whether we want  to relaunch
zmap might be launched again.

=cut

sub zMapRelaunchZMap {
    my ($self, $xml) = @_;

    if ($self->{'_relaunch_zmap'}) {
        $self->_launchZMap();
        $self->{'_relaunch_zmap'} = 0;
        warn "Relaunching zmap..." if $ZMAP_DEBUG;
    }
    elsif ($self->{'_launch_in_a_zmap'}) {
        if (my $zmap = $self->zMapZmapConnector()) {
            $zmap->post_respond_handler(\&post_response_client_cleanup_launch_in_a_zmap, [$self]);
        }
        $self->{'_launch_in_a_zmap'} = 0;
    }
    else {
        if (my $zmap = $self->zMapZmapConnector()) {
            $zmap->post_respond_handler(\&post_response_client_cleanup, [$self]);
        }

        # calling this here creates a race condition.
        # $self->xremote_cache->remove_clients_to_bad_windows();
        warn "Relaunch was not requested..." if $ZMAP_DEBUG;
    }

    return (200, "all closed");
}

=head1 zMapKillZmap

Attempts  to kill  zmap,  return true  if  it succeeded  and false  on
failure.  If relaunch = true and zMapKillZmap returns true then zmap
should relaunch, any other combination probably means no relaunch will
occur. There will still be a call to RelaunchZMap though as a finalised
request will be sent from zmap.

=cut

sub zMapKillZmap {
    my ($self, $relaunch, $in_a_zmap) = @_;

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
                $self->{'_launch_in_a_zmap'} = $in_a_zmap;

                $xr->send_commands('<zmap><request action="shutdown"/></zmap>');

                $rval = 1;    # everything has been as successful as can be
                ### Check shutdown by checking property set by ZMap?
                ### This is done in zMapRelaunchZMap...
            }
            else {

                # zmap probably died without sending us a message... seg fault...
                warn sprintf "Failed to ping %s, zmap probably crashed.", $xr->window_id();
                $rval = 0;
            }

            warn sprintf "About to delete client %s", $xr->window_id;
            $self->xremote_cache->remove_client_with_id($xr->window_id());
        }

        warn sprintf "finishing %s", "zMapKillZmap";

        return $rval;
    }

    return 0;
}

=head1 zMapPID

Stores the process id for zmap.

=cut

sub zMapPID {
    my ($self, $zmap_process_id) = @_;

    if ($zmap_process_id) {
        $self->{'_zMap_ZMAP_PROCESS_ID'} = $zmap_process_id;
    }
    return $self->{'_zMap_ZMAP_PROCESS_ID'};
}

=head1 zMapInsertZmapConnector

This is the way we receive commands from zmap.

=cut

sub zMapInsertZmapConnector {
    my ($self) = @_;
    my $zc = $self->{'_zMap_ZMAP_CONNECTOR'};
    if (!$zc) {
        my $mb = $self->menu_bar();
        my $zmap = ZMap::Connect->new(-server => 1);
        $zmap->init($mb, \&RECEIVE_FILTER, [ $self, qw() ]);
        my $id = $zmap->server_window_id();
        $zc = $self->{'_zMap_ZMAP_CONNECTOR'} = $zmap;
    }
    return $zc;
}

sub zMapZmapConnector {
    return shift->zMapInsertZmapConnector(@_);
}

sub zMapWriteDotBlixemrc {
    my ($self) = @_;

    my $file = $ENV{'BLIXEM_CONFIG_FILE'};
    my ($dir) = $file =~ m{(.+)/[^/]+$};
    mkpath($dir);    # Fatal if fails
    open my $blixem_rc, '>', $file
      or confess "Can't write to '$file'; $!";
    print $blixem_rc $self->formatZmapDefaults('blixem',
        'default-fetch-mode' => $ENV{'PFETCH_WWW'} ? 'pfetch-http' : 'pfetch-socket',),
      $self->formatZmapDefaults(
        'pfetch-http',
        'pfetch-mode' => 'http',
        'pfetch'      => $self->AceDatabase->Client->url_root . '/nph-pfetch',
        'cookie-jar'  => $ENV{'OTTERLACE_COOKIE_JAR'},
        'port'        => 80,
      ),
      $self->formatZmapDefaults(
        'pfetch-socket',
        'pfetch-mode' => 'socket',
        'node'        => $PFETCH_SERVER_LIST->[0][0],
        'port'        => $PFETCH_SERVER_LIST->[0][1],
      );
}

sub zMapWriteDotZmap {
    my ($self) = @_;

    my $file = $self->zMapZmapDir . "/ZMap";

    open my $fh, '>', $file
      or confess "Can't write to '$file'; $!";
    print $fh $self->zMapDotZmapContent;
    close $fh
      or confess "Error writing to '$file'; $!";
}

sub zMapDotZmapContent {
    my ($self) = @_;

    return $self->zMapZMapDefaults . $self->zMapWindowDefaults . $self->zMapBlixemDefaults . $self->zMapServerDefaults;
}

sub zMapServerDefaults {
    my ($self) = @_;

    my $server = $self->AceDatabase->ace_server;

    my $protocol = 'acedb';

    my $url = sprintf q{%s://%s:%s@%s:%d}, $protocol, $server->user, $server->pass, $server->host, $server->port;

    return $self->formatZmapDefaults(
        $self->slice_name,
        url             => $url,
        writeback       => 'false',
        sequence        => 'true',
        'legacy-styles' => 'true',

        # navigatorsets specifies the feature sets to draw in the navigator pane.
        # so far the requested columns are just scale, genomic_canonical and locus
        # in line with keeping the columns to a minimum to save screen space.
        navigatorsets => $self->semi_colon_separated_list([qw{ scale genomic_canonical locus }]),

        # Can specify a stylesfile instead of featuresets
        featuresets => $self->semi_colon_separated_list([ $self->zMapListMethodNames_ordered ]),
    );
}

sub semi_colon_separated_list {
    my ($self, $list) = @_;

    return sprintf(q{%s}, join ' ; ', map qq{$_}, @$list);
}

sub zMapZMapDefaults {
    my ($self) = @_;

    # make this configurable for those users where zmap doesn't start
    # due to not having window id when doing XChangeProperty.
    my $show_main =
      Bio::Otter::Lace::Defaults::option_from_array([qw(client zmap_main_window)])
      ? 'true'
      : 'false';

    my @config = (
        'ZMap',
        'sources'         => $self->slice_name,
        'show-mainwindow' => $show_main,
        'cookie-jar'      => $ENV{'OTTERLACE_COOKIE_JAR'},
    );

    if ($ENV{'PFETCH_WWW'}) {
        push(
            @config,
            'pfetch-mode' => 'http',
            'pfetch'      => $self->AceDatabase->Client->url_root . '/nph-pfetch',
        );
    }
    else {
        push(
            @config,
            'pfetch-mode' => 'pipe',
            'pfetch'      => 'pfetch',
        );
    }

    push @config, %{ Bio::Otter::Lace::Defaults::fetch_zmap_stanza() };

    return $self->formatZmapDefaults(@config);
}

sub zMapBlixemDefaults {
    my ($self) = @_;

    return $self->formatZmapDefaults(
        'blixem',
        'config-file' => $ENV{'BLIXEM_CONFIG_FILE'},
        qw{
          script      blixemh
          scope       200000
          homol-max   0
          },
        'protein-featuresets'    => [qw{ SwissProt TrEMBL }],
        'dna-featuresets'        => [qw{ EST_Human EST_Mouse EST_Other vertebrate_mRNA }],
        'transcript-featuresets' => [
            'Coding Transcripts',
            'Known CDS Transcripts',
            'Novel CDS Transcripts',
            'Putative and NMD',
        ],
        %{ Bio::Otter::Lace::Defaults::fetch_blixem_stanza() },
    );

    # script could also be "blixem_standalone" sh wrapper (if needed)
}

sub zMapWindowDefaults {
    my ($self) = @_;

    # Turn off warning about "possible comment in qw()"
    # caused by #hex colour names
    no warnings 'qw';    ## no critic(TestingAndDebugging::ProhibitNoWarnings)

    # The canvas_maxsize probably needs some thought here.
    return $self->formatZmapDefaults(
        'ZMapWindow',
        qw{
          feature-line-width          1
          feature-spacing             4.0
          colour-column-highlight     cornsilk
          colour-frame-0              #ffe6e6
          colour-frame-1              #e6ffe6
          colour-frame-2              #e6e6ff
          canvas-maxsize              10000
          }
    );
}

sub formatZmapDefaults {
    my ($self, $key, %defaults) = @_;

    my $def_str = "\n[$key]\n";
    while (my ($setting, $value) = each %defaults) {
        $value = $self->semi_colon_separated_list($value)
          if ref($value);
        $def_str .= qq{$setting = $value\n};
    }
    $def_str .= "\n";

    return $def_str;
}

sub formatGtkrcStyleDef {
    my ($self, $style_class, %defaults) = @_;

    my $style_string = qq`\nstyle "$style_class" {\n`;

    while (my ($style_element, $value) = each %defaults) {
        $style_string .= qq`  $style_element = "$value" \n`;
    }

    $style_string .= qq`}\n`;

    return $style_string;
}

sub formatGtkrcWidgetDef {
    my ($self, $widget_path, $style_class) = @_;

    my $widget_string = qq`\nwidget "$widget_path" style "$style_class"\n`;

    return $widget_string;
}

sub formatGtkrcWidget {
    my ($self, $widget_path, $style_class, %style_def) = @_;

    my $full_def = $self->formatGtkrcStyleDef($style_class, %style_def);
    $full_def .= $self->formatGtkrcWidgetDef($widget_path, $style_class);

    return $full_def;
}

sub zMapDotGtkrcContent {
    my ($self) = @_;

    # to create a coloured border for the focused view.
    my $full_content = $self->formatGtkrcWidget(
        "*.zmap-focus-view",
        "zmap-focus-view-frame",
        qw{
          bg[NORMAL]      gold
          }
    );

    # to make the info labels stand out and look like input boxes...
    $full_content .= $self->formatGtkrcWidget(
        "*.zmap-control-infopanel",
        "infopanel-labels",
        qw{
          bg[NORMAL]      white
          }
    );

    # to make the context menu titles blue
    $full_content .= $self->formatGtkrcWidget(
        "*.zmap-menu-title.*",
        "menu-titles",
        qw{
          fg[INSENSITIVE] blue
          }
    );

    # to create a coloured border for the view with an unknown species. (Not sure this works properly...)
    $full_content .= $self->formatGtkrcStyleDef(
        "default-species",
        qw{
          bg[NORMAL]    gold
          }
    );

    # foreach (species){ self->formatGtkrcStyleDef("species", ... ) }
}

sub zMapWriteDotGtkrc {
    my $self = shift;

    my $dir  = $self->zMapZmapDir;
    my $file = "$dir/.gtkrc";

    my $fh;
    eval {

        # directory should be made already
        open $fh, '>', $file
          or die "write_dot_zmap: error writing file '$file', $!";
    };
    warn "Error in :$@" if $@;
    unless ($@) {
        my $content = $self->zMapDotGtkrcContent();
        print $fh $content;
    }
    close $fh;
}

sub zMapZmapDir {
    my $self = shift;

    confess "Cannot set ZMap directory directly" if @_;

    my $ace_path = $self->ace_path();
    my $path     = "$ace_path/ZMap";
    unless (-d $path) {
        mkdir $path;
        die "Can't mkdir('$path') : $!\n" unless -d $path;
    }
    return $path;
}

sub zMapListMethodNames_ordered {
    my $self       = shift;
    my @list       = ();
    my $collection = $self->Assembly->MethodCollection;
    return map $_->name, $collection->get_all_top_level_Methods;
}

#===========================================================

sub xremote_cache {
    my ($self, $cache) = @_;

    if   ($cache) { $self->{'_xremote_cache'} = $cache; }
    else          { $cache                    = $self->{'_xremote_cache'}; }

    return $cache;
}

sub main_window_name {
    my ($self, $name) = @_;

    $name = 'ZMap port #' . $self->AceDatabase->ace_server->port();

    return $name;
}

=head1 zMapRegisterClient

A handler to handle register_client requests.

=cut

sub zMapRegisterClient {
    my ($self, $xml) = @_;

    my $zmap = $self->zMapZmapConnector();
    my $out  = {
        response => {
            client => [
                {
                    created => 0,
                    exists  => 1,
                }
            ]
        }
    };
    $zmap->protocol_add_meta($out);

    unless ($xml->{'request'}->{'client'}->{'xwid'}
        && $xml->{'request'}->{'client'}->{'request_atom'}
        && $xml->{'request'}->{'client'}->{'response_atom'})
    {
        warn "mismatched request for register_client:\n",
          "id, request and response required\n",
          "Got '", Dumper($xml), "'\n";
        return (403, $zmap->basic_error("Bad Request!"));
    }

    $self->zMapProcessNewClientXML($xml, $self->main_window_name());

    $zmap->post_respond_handler(\&open_clones, [$self]);

    # this feels convoluted
    $out->{'response'}->{'client'}->[0]->{'created'} = 1;

    my $response_xml = make_xml($out);

    warn "Sending response to register_client:\n$response_xml\n" if $ZMAP_DEBUG;

    return (200, $response_xml);
}

=head1 zMapEdit

A handler to handle edit requests.  Returns a basic response.

=cut

sub zMapEdit {
    my ($self, $xml_hash) = @_;

    my $response;
    my $z = $self->zMapZmapConnector();
    if ($xml_hash->{'request'}->{'action'} eq 'edit') {

        #warn Dumper($xml_hash);
        my $feat_hash = $xml_hash->{'request'}->{'align'}->{'block'}->{'featureset'}{'feature'}
          or return return (200, $z->handled_response(0));

        # Are there any transcripts in the list of features?
        my ($genomic_canonical, @subseq_names);
      NAME: foreach my $name (keys %$feat_hash) {
            my $feat = $feat_hash->{$name};
            if (my $style = $feat->{'style'}) {
                if (lc($style) eq 'genomic_canonical') {
                    $genomic_canonical = $name;
                    last NAME;
                }
            }
            my $subs = $feat->{'subfeature'}
              or next;
            unless (ref $subs eq 'ARRAY') {
                die "Unexpected feature format: ", Dumper($feat);
            }
            foreach my $s (@$subs) {

                # Only transcripts have exons
                if ($s->{'ontology'} eq 'exon') {
                    push(@subseq_names, $name);
                    next NAME;
                }
            }
        }

        if ($genomic_canonical) {
            $self->edit_Clone($genomic_canonical);
            return (200, $z->handled_response(1));
        }
        elsif (@subseq_names) {
            $self->edit_subsequences(@subseq_names);
            return (200, $z->handled_response(1));
        }
        else {
            return (200, $z->handled_response(0));
        }
    }
    else {
        confess "Not an 'edit' action:\n", Dumper($xml_hash);
    }

}

=head1 zMapHighlight

A  handler  to  handle  single_select  and  multiple_select  requests.
returns a basic response.

=cut

sub zMapHighlight {
    my ($self, $xml_hash) = @_;

    my $z = $self->zMapZmapConnector();

    # Needs to do something interesting to find the object to highlight.
    if ($xml_hash->{'request'}->{'action'} eq 'single_select') {
        $self->deselect_all();
        my $feature = $xml_hash->{'request'}->{'align'}->{'block'}->{'featureset'}->{'feature'} || {};
        foreach my $name (keys(%$feature)) {
            $self->highlight_by_name_without_owning_clipboard($name);
        }
    }
    elsif ($xml_hash->{'request'}->{'action'} eq 'multiple_select') {
        my $feature = $xml_hash->{'request'}->{'align'}->{'block'}->{'featureset'}->{'feature'} || {};
        foreach my $name (keys(%$feature)) {
            $self->highlight_by_name_without_owning_clipboard($name);
        }
    }
    else { confess "Not a 'select' action\n"; }

    return (200, $z->handled_response(1));
}

=head1 zMapTagValues

A  handler  to handle  feature_details  request.   returns a  notebook
response.

=cut

sub zMapTagValues {
    my ($self, $xml_hash) = @_;

    # warn Dumper($xml_hash);

    my $pages = "";
    if ($xml_hash->{'request'}->{'action'} eq 'feature_details') {
        my $feature_hash = $xml_hash->{'request'}->{'align'}->{'block'}->{'featureset'}->{'feature'} || {};

        # There is only ever 1 feature in the XML from Zmap
        my ($name) = keys %$feature_hash;
        my $info = $feature_hash->{$name};

        unless ($name) {
            warn "No feature in featureset of XML";
        }
        elsif (my $subseq = $self->get_SubSeq($name)) {
            $pages .= $subseq->zmap_info_xml;
        }
        else {
            $pages .= $self->zmap_feature_details_xml($name, $info);
            $pages .= $self->zmap_feature_evidence_xml($name, $info);
        }
    }

    my $xml = Hum::XmlWriter->new;
    $xml->open_tag('response', { handled => $pages ? 'true' : 'false' });
    if ($pages) {
        $xml->open_tag('notebook');
        $xml->open_tag('chapter');
        $xml->add_raw_data($pages);
    }
    $xml->close_all_open_tags;

    return (200, $xml->flush);
}

sub zmap_feature_details_xml {
    my ($self, $name, $info) = @_;

    my $ace = $self->ace_handle;
    my ($taxon_id, $desc);
    foreach my $class (qw{ Sequence Protein }) {
        $ace->raw_query(qq{find $class "$name"});
        my $txt = Hum::Ace::AceText->new($ace->raw_query(qq{show -a}));

        # print STDERR $$txt;
        next unless $txt->get_values($class);
        ($taxon_id) = $txt->get_values('Taxon_id');
        ($desc)     = $txt->get_values('Title');
    }

    return '' unless $taxon_id or $desc;

    my $xml = Hum::XmlWriter->new(5);

    # Put this on the "Details" page which already exists.
    $xml->open_tag('page',       { name => 'Details' });
    $xml->open_tag('subsection', { name => 'Feature' });
    $xml->open_tag('paragraph',  { type => 'tagvalue_table' });
    $xml->full_tag('tagvalue', { name => 'Taxon ID', type => 'simple' }, $taxon_id->[0])
      if $taxon_id;
    $xml->full_tag('tagvalue', { name => 'Description', type => 'scrolled_text' }, $desc->[0])
      if $desc;

    $xml->close_all_open_tags;

    return $xml->flush;
}

sub zmap_feature_evidence_xml {
    my ($self, $feat_name, $info) = @_;

    my $subseq_list = [];
    foreach my $name ($self->list_all_SubSeq_names) {
        if (my $subseq = $self->get_SubSeq($name)) {
            push(@$subseq_list, $subseq);
        }
    }
    my $used_subseq_names = [];
  SUBSEQ: foreach my $subseq (@$subseq_list) {

        #warn "Looking at: ", $subseq->name;
        my $evi_hash = $subseq->evidence_hash();

        # evidence_hash looks like this
        # evidence = {
        #   type    => [ qw(evidence names) ],
        #   EST     => [ qw(Em:BC01234.1 Em:CR01234.2) ],
        #   cDNA    => [ qw(Em:AB01221.3) ],
        #   ncRNA	=> [ qw(Em:AF480562.1) ],
        #   Protein => [ qw(Sw:Q99IVF1) ]
        # }

        foreach my $evi_type (keys %$evi_hash) {
            my $evi_array = $evi_hash->{$evi_type};
            foreach my $evi_name (@$evi_array) {
                if ($feat_name eq $evi_name) {
                    push(@$used_subseq_names, $subseq->name);
                    next SUBSEQ;
                }
            }
        }
    }
    if (@$used_subseq_names) {
        my $xml = Hum::XmlWriter->new(5);
        $xml->open_tag('page',       { name => 'Details' });
        $xml->open_tag('subsection', { name => 'Feature' });
        $xml->open_tag('paragraph',  { name => 'Evidence', type => 'homogenous' });
        foreach my $name (@$used_subseq_names) {
            $xml->full_tag('tagvalue', { name => 'for transcript', type => 'simple' }, $name);
        }
        $xml->close_all_open_tags;
        return $xml->flush;
    }
    else {
        return '';
    }
}

sub zMapRemoveView {
    my ($self, $xml) = @_;

    # I guess all we need to do here is remove the associated xid from the cache...

    my ($client_tag, $xid);

    my $z = $self->zMapZmapConnector();

    if ($client_tag = $xml->{'request'}->{'client'}) {
        $xid = $client_tag->{'xwid'};
    }

    if ($xid) {
        warn sprintf "... going to remove %s", $xid;
        $self->xremote_cache->remove_client_with_id($xid);
    }

    return (200, $z->handled_response(1));
}

sub zMapIgnoreRequest {
    my ($self) = @_;
    
    return(200, $self->zMapZmapConnector->handled_response(0));
}

#===========================================================

sub RECEIVE_FILTER {
    my ($connect, $request, $obj) = @_;

    # The table of actions and functions...
    my $lookup = {
        register_client => 'zMapRegisterClient',
        edit            => 'zMapEdit',
        single_select   => 'zMapHighlight',
        multiple_select => 'zMapHighlight',
        finalised       => 'zMapRelaunchZMap',
        feature_details => 'zMapTagValues',
        view_closed     => 'zMapRemoveView',
        features_loaded => 'zMapIgnoreRequest'
    };

    # @list could be dynamically created...
    my @list = keys(%$lookup);

    # find the action in the request XML
    #warn "Request = '$request'";
    my $reqXML = parse_request($request);

    unless ($reqXML->{'request'}) {

        #for my $k (keys %$reqXML) {
        #	$reqXML->{'request'}->{$k} = $reqXML->{$k};
        #	delete $reqXML->{$k};
        #}

        warn "INVALID REQUEST: no <request> block\n";
    }

    my $action = $reqXML->{'request'}->{'action'};

    warn "REQUEST FROM ZMAP: $request\n" if $ZMAP_DEBUG;

    warn "PARSED REQUEST: " . Dumper($reqXML) . "\n" if $ZMAP_DEBUG;

    warn "In RECEIVE_FILTER for action=$action\n" if $ZMAP_DEBUG;

    # The default response code and message.
    my ($status, $response) = (404, $obj->zMapZmapConnector->basic_error("Unknown Command"));

    # find the method to call...
    foreach my $valid (@list) {
        if (
            $action eq $valid
            && ($valid = $lookup->{$valid})    # N.B. THIS SHOULD BE ASSIGNMENT NOT EQUALITY
            && $obj->can($valid)
          )
        {

            # call the method to get the status and response
            #warn "Calling $obj->$valid($reqXML)";
            ($status, $response) = $obj->$valid($reqXML);
            last;                              # no need to go any further...
        }
    }

    warn "Response:\n$response";

    return ($status, $response);
}

=head1 zMapGetXRemoteClientByName

The XRemoteCache caches objects based on their window ids. This module
needs some  way to get  the object cached  for a particular  window id
based on a name. e.g. the window that's displaying the features.

=cut

sub zMapGetXRemoteClientByName {
    my ($self, $key) = @_;

    my $cache = $self->xremote_cache();
    $cache ||= $self->xremote_cache(ZMap::XRemoteCache->new());

    my $window_id = $cache->lookup_value($key);

    my $client = $cache->get_client_with_id($window_id);

    return $client;
}

sub zMapGetXRemoteClientByAction {
    my ($self, $action, $own_windows_only) = @_;

    my ($pid, $client, $method);

    my $cache = $self->xremote_cache();
    $cache ||= $self->xremote_cache(ZMap::XRemoteCache->new());

    # warn Dumper $cache;

    $method = (
        $own_windows_only
        ? 'get_own_client_for_action_pid'
        : 'get_client_for_action_pid'
    );

    if ($cache) {
        $pid = $self->zMapPID();
        $client = $cache->$method($action, $pid);
    }

    return $client;
}

sub zMapGetXRemoteClientForView {
    my ($self) = @_;
    my $client = $self->zMapGetXRemoteClientByName($self->slice_name());
    if (!$client) { cluck sprintf("Missing a client for %s. Are you sure zmap is running?", $self->slice_name()); }
    return $client;
}

# open_clones - Displays the data in  a zmap.  This is not a method on
# self,  but  a  standalone  function  taking a  ZMap::Connect  and  a
# MenuCanvasWindow::XaceSeqChooser.

sub open_clones {
    my ($zmap, $self) = @_;

    unless (UNIVERSAL::isa($zmap, 'ZMap::Connect')
        && UNIVERSAL::isa($self, 'MenuCanvasWindow::XaceSeqChooser'))
    {
        cluck "Usage: open_clones(ZMap::Connect, MenuCanvasWindow::XaceSeqChooser)";
        return;
    }

    #sleep 20;
    $zmap->post_respond_handler();    # clear the handler...

    # first open a zmap window...
    my $xremote = $self->zMapGetXRemoteClientByName($self->main_window_name());

    my $zmap_success = $self->zMapDoRequest($xremote, "new_zmap", qq!<zmap><request action="new_zmap"/></zmap>!);

    if ($zmap_success == 0) {

        # now open a view
        my $seg = newXMLObj('segment');
        setObjNameValue($seg, 'sequence', $self->slice_name);
        setObjNameValue($seg, 'start',    1);
        setObjNameValue($seg, 'end',      '0');

        $xremote = $self->zMapGetXRemoteClientByName("ZMap");

        $self->zMapRegisterClientRequest($xremote);

        my $view_success = $self->zMapDoRequest($xremote, "new_view", obj_make_xml($seg, "new_view"));

        if ($view_success == 0) {
            $xremote = $self->zMapGetXRemoteClientByName($self->slice_name());

            $self->zMapRegisterClientRequest($xremote);
        }
        else {
            warn "new_view request failed!";
        }
    }
    else {
        warn "new_zmap request failed!";
    }

    return;
}

sub zMapRegisterClientRequest {
    my ($self, $xremote) = @_;

    my $zmap = $self->zMapZmapConnector();

    my $register_success = $self->zMapDoRequest($xremote, "register_client", $zmap->connect_request());

    if ($register_success != 0) {
        warn "register_client failed";
    }

    return;
}

sub zMapGetMark {

    my ($self) = @_;

    if (my $client = $self->zMapGetXRemoteClientByAction('get_mark', 1)) {

        my $xml = qq(<zmap><request action="get_mark" /></zmap>);

        my @response = $client->send_commands($xml);

        my ($status, $hash) = parse_response($response[0]);

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

sub _zMapLoadFeatures {
    my ($self, $featuresets, $use_mark) = @_;

    if (my $client = $self->zMapGetXRemoteClientByAction('load_features', 1)) {

        my $xml = Hum::XmlWriter->new;
        $xml->open_tag('zmap');
        $xml->open_tag('request', { action => 'load_features', $use_mark ? (load => 'mark') : () });
        $xml->open_tag('align');
        $xml->open_tag('block');
        for my $featureset (@$featuresets) {
            $xml->open_tag('featureset', { name => $featureset });
            $xml->close_tag;
        }
        $xml->close_all_open_tags;

        my @response = $client->send_commands($xml->flush);

        my ($status, $hash) = parse_response($response[0]);

        unless ($status =~ /^2/) {
            warn "Problem loading featuresets";
        }
    }
    else {
        warn "Failed to get client for 'load_features'";
    }
}

sub zMapLoadFeatures {
    my ($self, @featuresets) = @_;
    return $self->_zMapLoadFeatures(\@featuresets, 0);
}

sub zMapLoadFeaturesInMark {
    my ($self, @featuresets) = @_;
    return $self->_zMapLoadFeatures(\@featuresets, 1);
}

sub zMapDeleteFeaturesets {
    my ($self, @featuresets) = @_;

    if (my $client = $self->zMapGetXRemoteClientByAction('delete_feature', 1)) {

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

        my @response = $client->send_commands($xml->flush);

        my ($status, $hash) = parse_response($response[0]);

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
}

sub zMapZoomToSubSeq {

    my ($self, $subseq) = @_;

    if (my $client = $self->zMapGetXRemoteClientByAction('zoom_to', 1)) {
        my $xml = Hum::XmlWriter->new;
        $xml->open_tag('zmap');
        $xml->open_tag('request', { action => 'zoom_to' });
        $xml->open_tag('align');
        $xml->open_tag('block');
        $xml->open_tag('featureset', { name => $subseq->GeneMethod->name });
        $subseq->zmap_xml_feature_tag($xml);
        $xml->close_all_open_tags;

        my @response = $client->send_commands($xml->flush);

        my ($status, $hash) = parse_response($response[0]);

        if ($status =~ /^2/ && $hash->{response} =~ /executed/) {
            return 1;
        }
    }
    else {
        warn "Failed to get client for 'zoom_to'";
    }

    return;
}

=head1 zMapDoRequest

return = -1, 0, 1 for fail, response, or error respectively

=cut

sub zMapDoRequest {
    my ($self, $xremote, $action, @commands) = @_;

    my $response_error_fail = -1;

    unless ($xremote && UNIVERSAL::isa($xremote, 'X11::XRemote')) {
        cluck "Usage: $self->zMapDoRequest(X11::XRemote, '<action>', (<commands>)" if $ZMAP_DEBUG;
        return $response_error_fail;
    }

    if ($ZMAP_DEBUG) {
        my $substring = 1;    # sometimes you don't need to see _all_ of the request
        if ($substring) {
            map { warn substr($_, 0, 512), (length($_) > 512 ? "..." : "") } @commands;
        }
        else {
            warn "@commands";
        }
    }

    my @a = $xremote->send_commands(@commands);

    for (my $i = 0; $i < @commands; $i++) {
        warn "command $i '", substr($commands[$i], 0, index($commands[$i], '>') + 1), "' returned $a[$i] "
          if $ZMAP_DEBUG;
        my ($status, $xmlHash) = parse_response($a[$i]);
        if ($status =~ /^2\d\d/) {    # 200s
            $self->RESPONSE_HANDLER($action, $xmlHash);
            $response_error_fail = 0;
        }
        else {
            $self->ERROR_HANDLER($action, $status, $xmlHash);
            $response_error_fail = 1;
            last;
        }
    }

    return $response_error_fail;
}

sub zMapProcessNewClientXML {
    my ($self, $xml, $lookup_key) = @_;

    my $cache = $self->xremote_cache();

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
                if (!$cache->get_client_with_id($id)) {
                    $cache->create_client_with_pid_id_actions($self->zMapPID(), $id, @actions);
                }
                $cache->insert_lookup($full_key, $id);
            }
            $counter++;
        }
    }
    else {
        cluck "malformed register client xml [no window id]";
    }

    return;
}

sub RESPONSE_HANDLER {
    my ($self, $action, $xml) = @_;

    warn "In RESPONSE_HANDLER for action=$action\n" if $ZMAP_DEBUG;

    # should have something to get the actions from the xml!

    if ($action eq 'new_zmap') {
        $self->zMapProcessNewClientXML($xml, "ZMap");
    }
    elsif ($action eq 'new_view') {
        $self->zMapProcessNewClientXML($xml, $self->slice_name());
    }
    elsif ($action eq 'list_windows') {
        $self->zMapProcessNewClientXML($xml, "ZMapWindow");
    }
    elsif ($action eq 'register_client'
        || $action eq 'other actions')
    {

        # do these
        warn "handled action '$action'" if $ZMAP_DEBUG;
    }
    elsif ($action eq 'zoom_to') {

        #$self->message($xml->{'response'});
    }
    elsif ($action eq 'get_mark') {

    }
    else {
        cluck "RESPONSE_HANDLER knows nothing about how to handle actions of type '$action'";
    }

    return;
}

sub ERROR_HANDLER {
    my ($self, $action, $status, $xml) = @_;
    my $message = "";
    if (exists($xml->{'error'})) {
        if (   (ref($xml->{'error'}) eq 'HASH')
            && (exists($xml->{'error'}->{'message'})))
        {
            $message = $xml->{'error'}->{'message'};
        }
        else {
            $message = $xml->{'error'};
        }
    }

    warn "action=$action status=$status error=$message" if $ZMAP_DEBUG;

    if ($status == 400) {

    }
    elsif ($status == 401) {

    }
    elsif ($status == 402) {

    }
    elsif ($status == 403) {

    }
    elsif ($status == 404) {

        # could do something clever here so that we don't send the same window this command again.
    }
    elsif ($status == 412) {
        $self->xremote_cache->remove_clients_to_bad_windows();
    }
    elsif ($status == 500) {

    }
    elsif ($status == 501) {

    }
    elsif ($status == 502) {

    }
    elsif ($status == 503) {

    }
    else {
        warn "I know nothing about status $status\n";
    }
    return;
}

1;

__END__


=pod

=head1 NAME - MenuCanvasWindow::ZmapSeqChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


=cut

__DATA__



