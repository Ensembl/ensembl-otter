### MenuCanvasWindow::ZmapSeqChooser

package MenuCanvasWindow::XaceSeqChooser;

use strict;
use Carp qw{ cluck confess };
use ZMap::Connect qw{ :all };
use Sys::Hostname;
use ZMap::XRemoteCache;
use Data::Dumper;
use Hum::Conf qw{ PFETCH_SERVER_LIST };
use XML::Simple;


my $ZMAP_DEBUG = 1;

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

sub zMap_make_exoncanvas_edit_window{
    my( $self, $sub ) = @_;
    
    my $sub_name = $sub->name;
    warn "subsequence-name $sub_name " ;
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

=head1 _launchZMapZMap

The guts of the code to launch and display the features in a zmap.

=cut

sub _launchZMap{
    my ($self) = @_;

    my $z = $self->zMapInsertZmapConnector();
    $self->zMapWriteDotZmap();
    $self->zMapWriteDotGtkrc();
    $self->isZMap(1);

    unless($self->xremote_cache()){
        $self->xremote_cache(ZMap::XRemoteCache->new());
    }

    my @e = ('zmap', 
             '--conf_dir' => $self->zMapZmapDir,
             '--win_id'   => $z->server_window_id);
    warn "export PATH=$ENV{PATH}\nexport LD_LIBRARY_PATH=$ENV{LD_LIBRARY_PATH}\n@e\n" if $ZMAP_DEBUG;

    # this makes it a lot easier to debug with ddd
    if(my $command_file = $ENV{DEBUG_WITH_DDD}){
        my $ddd_file = $self->zMapZmapDir() . "/xremote.ddd";
        eval{
            unlink($ddd_file);
            open(my $ddd, ">$ddd_file");
            open(my $input, "<$command_file");
            while(<$input>){ print $ddd $_ }
            close $input;
            my $ld_library_path = "/nfs/team71/acedb/zmap/prefix/LINUX/lib";
            print $ddd "set environment LD_LIBRARY_PATH $ld_library_path\n";
            print $ddd "run --conf_dir ".$self->zMapZmapDir." --win_id ".$z->server_window_id. "\n";
            close $ddd;
        };
        if(!$@){
            @e = ('ddd', '--nx', '--command', $ddd_file, 'zmap');
        }
        sleep(2);   ### Why?
    }

    my $pid = fork_exec(\@e);

    if($pid){
        $self->zMapPID($pid);
    }else{
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
    my( $self ) = @_;

    my $relaunch = 1;

    if(!$self->zMapKillZmap($relaunch)){
        $self->_launchZMap();
    }

    return ;
}

=head1 zMapLaunchInAZmap

Uses an existing ZMap to display the features of $self->slice_name().

=cut

sub zMapLaunchInAZmap{
    my ($self) = @_;

    # return undef if($self->zMapPID()); # 

    my $xremote_cache = $self->xremote_cache;
    $xremote_cache  ||= $self->xremote_cache(ZMap::XRemoteCache->new());
    $xremote_cache->remove_clients_to_bad_windows();

    if(my $pid_list = $xremote_cache->get_pid_list()){
        if(scalar(@$pid_list) == 1){
            my $pid = $pid_list->[0];
            if($self->zMapGetXRemoteClientByName($self->slice_name())){
                $self->message(sprintf("Already launched in zmap with pid %d", $pid));
            }elsif(my $xr = $xremote_cache->get_client_for_action_pid("new_view", $pid)){
                $self->zMapPID($pid);
                
                my $sequence = $self->slice_name;
                my $server   = $self->AceDatabase->ace_server;
                my $protocol = 'acedb';
                my $username = 'any';
                my $password = 'any';
                
                my $url = sprintf(q{%s://%s:%s@%s:%d},
                                  $protocol,
                                  $username, $password,
                                  $server->host, 
                                  $server->port);
                
                my $source_stanza = $self->zMapServerDefaults;
                $source_stanza =~ s/\&/&amp;/g; # needs fully xml escaping really

                my $config = sprintf(q!ZMap{
sequence_server = "%s %s"
}
%s
                                     !, $sequence, $url, $source_stanza);
                
                my $xml = sprintf(q!<zmap action="new_view">
 <segment sequence="%s" start="1" end="0">
%s
  </segment>
</zmap>
                                  !, $sequence, $config);
                
                $self->zMapDoRequest($xr, "new_view", $xml);
                
                if($xr = $self->zMapGetXRemoteClientByName($self->slice_name())){
                    $self->zMapRegisterClientRequest($xr);
                }else{
                    cluck "Failed to find the new xremote client";
                }
            }else{
                # couldn't find a client who can new_view, probably need to 
                my $zmap = $self->zMapZmapConnector();
                open_clones($zmap, $self);
            }
        }elsif(scalar(@$pid_list) == 0){
            cluck "Process id list is empty. Is zmap running?";
        }else{
            cluck "More than one process id in list, How to choose?";
        }
    }else{ cluck "Failed to get a process id list from the cache. Is zmap running?"; }

    return ;
}

=head1 post_response_client_cleanup

A function to cleanup any bad windows that might exist.
Primary user of this is the zMapRelaunchZMap function.

=cut

sub post_response_client_cleanup{
    my ($zmap, $self) = @_;
    $zmap->post_respond_handler();
    $self->xremote_cache->remove_clients_to_bad_windows();
    return ;
}

=head1 zMapRelaunchZMap

A  handler to  handle finalise  requests. ZMap  sends these  when it's
closing the  whole program. Depending  on whether we want  to relaunch
zmap might be launched again.

=cut

sub zMapRelaunchZMap{
    my ($self, $xml) = @_;

    my $relaunch = ($self->{'_relaunch_zmap'} ? 1 : 0);
    warn "In zMapRelaunchZMap $self $relaunch" if $ZMAP_DEBUG;

    if($self->{'_relaunch_zmap'}){
        $self->_launchZMap();
        $self->{'_relaunch_zmap'} = 0;
    }else { 
	if(my $zmap = $self->zMapZmapConnector()){
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
occur.

=cut

sub zMapKillZmap {
    my( $self, $relaunch ) = @_;
    
    ### We're only using the pid as marker for zmap having been started
    if (my $pid = $self->zMapPID) {
        my $rval = 0;
        my $main_window_name = $self->main_window_name();
        
        if(my $xr = $self->zMapGetXRemoteClientByName($main_window_name)){
            # check we can ping...
            if($xr->ping()){
                warn "Ping OK - sending 'shutdown'";
                $self->{'_relaunch_zmap'} = $relaunch;
                
                $xr->send_commands('<zmap action="shutdown" />');
                
                $rval = 1; # everything has been as successful as can be
                ### Check shutdown by checking property set by ZMap?
                ### This is done in zMapRelaunchZMap...
            }else{
                # zmap probably died without sending us a message... seg fault...
                warn sprintf "Failed to ping %s, zmap probably crashed.", $xr->window_id();
                $rval = 0;
            }

            warn sprintf "About to delete client %s", $xr->window_id;
            $self->xremote_cache->remove_client_with_id($xr->window_id());
        }

        # always remove the clients...
        #$self->xremote_cache->remove_clients_to_bad_windows();

        return $rval;
    }

    return 0;
}

=head1 zMapPID

Stores the process id for zmap.

=cut

sub zMapPID {
    my( $self, $zmap_process_id ) = @_;
    
    if ($zmap_process_id) {
        $self->{'_zMap_ZMAP_PROCESS_ID'} = $zmap_process_id;
    }
    return $self->{'_zMap_ZMAP_PROCESS_ID'};
}

=head1 zMapInsertZmapConnector

This is the way we receive commands from zmap.

=cut

sub zMapInsertZmapConnector{
    my ($self) = @_;
    my $zc = $self->{'_zMap_ZMAP_CONNECTOR'};
    if(!$zc){
        my $mb   = $self->menu_bar();
        my $zmap = ZMap::Connect->new( -server => 1 );
        $zmap->init($mb, \&RECEIVE_FILTER, [ $self, qw( register_client edit single_select multiple_select finalised feature_details) ]);
        my $id = $zmap->server_window_id();
        $zc = $self->{'_zMap_ZMAP_CONNECTOR'} = $zmap;
    }
    return $zc;
}

sub zMapZmapConnector{
    return shift->zMapInsertZmapConnector(@_);
}

sub zMapWriteDotZmap{
    my ($self) = @_;
    my $dir    = $self->zMapZmapDir();
    my $file   = "${dir}/ZMap";
    
    my $fh;
    eval{
        # directory should be made already
        open($fh, ">$file") or die "write_dot_zmap: error writing file '$file', $!";
    };
    warn "Error in :$@" if $@;
    unless($@){
        my $content = $self->zMapDotZmapContent();
        print $fh $content;
        return 1;
    }
    close $fh;
    return 0;
}

sub zMapDotZmapContent{
    my ($self) = @_;

    return
        $self->zMapZMapDefaults
      . $self->zMapWindowDefaults
      . $self->zMapBlixemDefaults
      . $self->zMapServerDefaults
      ;
}

sub zMapServerDefaults {
    my ($self) = @_;
    
    my $server = $self->AceDatabase->ace_server;
    
    my $protocol    = 'acedb';

    my $url = sprintf q{"%s://%s:%s@%s:%d"},
        $protocol,
        $server->user, $server->pass,
        $server->host, $server->port;
    
    return $self->formatZmapDefaults(
        'source',
        url             => $url,
        writeback       => 'false',
        sequence        => 'true',
        use_zmap_styles => 'false',
        # navigator_sets specifies the feature sets to draw in the navigator pane.
        # so far the requested columns are just scale, genomic_canonical and locus
        # in line with keeping the columns to a minimum to save screen space.
        navigator_sets => qq{"scale genomic_canonical locus"},

        featuresets => $self->double_quote_escaped_list([$self->zMapListMethodNames_ordered]),
        # Can specify a stylesfile instead of featuresets

    );
}

sub double_quote_escaped_list {
    my ($self, $list) = @_;
    
    return sprintf(q{"%s"},
        join ' ',
        map qq{\\"$_\\"},
        @$list);
}

sub zMapZMapDefaults {
    my ($self) = @_;

    # make this configurable for those users where zmap doesn't start
    # due to not having window id when doing XChangeProperty.
    my $show_main = Bio::Otter::Lace::Defaults::option_from_array(
        [qw(client zmap_main_window)]
      )
        ? 'true'
        : 'false';
    
    return $self->formatZmapDefaults(
        'ZMap',
        show_mainwindow  => $show_main,
        pfetch      => sprintf(qq{"%s"}, $self->AceDatabase->Client->url_root . '/nph-pfetch'),
        cookie_jar  => sprintf(qq{"$ENV{'OTTERLACE_COOKIE_JAR'}"}),
    );
}

sub zMapBlixemDefaults {
    my ($self) = @_;
    
    return $self->formatZmapDefaults(
        'blixem',
        netid  => qq{"$PFETCH_SERVER_LIST->[0][0]"},
        port   =>     $PFETCH_SERVER_LIST->[0][1],
        qw{
            script      "blixem"
            scope       200000
            homol_max   0
        },
        protein_featuresets => [qw{ SwissProt TrEMBL }],
        dna_featuresets    => [qw{ EST_Human EST_Mouse EST_Other vertebrate_mRNA }],
        transcript_featuresets => [qw{
            Coding
            Known_CDS
            Novel_CDS
            Putative_CDS
            Nonsense_meditated_decay
            }],
    );
    # script could also be "blixem_standalone" sh wrapper (if needed)
}

sub zMapWindowDefaults {
    my ($self) = @_;
    
    # Turn off warning about "possible comment in qw()"
    # caused by #hex colour names
    no warnings 'qw';

    # The canvas_maxsize probably needs some thought here.
    return $self->formatZmapDefaults(
        'ZMapWindow',
        qw{
            feature_line_width          1
            feature_spacing             4.0
            colour_column_highlight     "CornSilk"
            colour_item_highlight       "gold"
            colour_frame_0              "#ffe6e6"
            colour_frame_1              "#e6ffe6"
            colour_frame_2              "#e6e6ff"
            canvas_maxsize              10000
        }
    );
}

sub formatZmapDefaults {
    my ($self, $key, %defaults) = @_;
    
    my $def_str = "\n$key\n{\n";
    while (my ($setting, $value) = each %defaults) {
        $value = $self->double_quote_escaped_list($value)
            if ref($value);
        $def_str .= qq{$setting = $value\n};
    }
    $def_str .= "}\n";
    
    return $def_str;
}

sub formatGtkrcStyleDef{
    my ($self, $style_class, %defaults) = @_;

    my $style_string = qq`\nstyle "$style_class" {\n`;

    while (my ($style_element, $value) = each %defaults){
        $style_string .= qq`  $style_element = "$value" \n`;
    }

    $style_string .= qq`}\n`;

    return $style_string;
}
sub formatGtkrcWidgetDef{
    my ($self, $widget_path, $style_class) = @_;

    my $widget_string = qq`\nwidget "$widget_path" style "$style_class"\n`;

    return $widget_string;
}
sub formatGtkrcWidget{
    my ($self, $widget_path, $style_class, %style_def) = @_;


    my $full_def = $self->formatGtkrcStyleDef($style_class, %style_def);
    $full_def   .= $self->formatGtkrcWidgetDef($widget_path, $style_class);

    return $full_def;
}

sub zMapDotGtkrcContent{
    my ($self) = @_;

    # to create a coloured border for the focused view.
    my $full_content = $self->formatGtkrcWidget("*.zmap-focus-view", 
                                                "zmap-focus-view-frame",
                                                qw{
                                                    bg[NORMAL]      gold
                                                });
    # to make the info labels stand out and look like input boxes...
    $full_content   .= $self->formatGtkrcWidget("*.zmap-control-infopanel", 
                                                "infopanel-labels",
                                                qw{
                                                    bg[NORMAL]      white
                                                });
    # to make the context menu titles blue
    $full_content   .= $self->formatGtkrcWidget("*.zmap-menu-title.*", 
                                                "menu-titles",
                                                qw{
                                                    fg[INSENSITIVE] blue
                                                });
    # to create a coloured border for the view with an unknown species. (Not sure this works properly...)
    $full_content   .= $self->formatGtkrcStyleDef("default-species",
                                                  qw{
                                                      bg[NORMAL]    gold
                                                  });
    # foreach (species){ self->formatGtkrcStyleDef("species", ... ) }
}

sub zMapWriteDotGtkrc {
    my $self = shift;
    
    my $dir = $self->zMapZmapDir;
    my $file = "$dir/.gtkrc";
    
    my $fh;
    eval{
        # directory should be made already
        open($fh, ">$file") or die "write_dot_zmap: error writing file '$file', $!";
    };
    warn "Error in :$@" if $@;
    unless($@){
        my $content = $self->zMapDotGtkrcContent();
        print $fh $content;
    }
    close $fh;
}

sub zMapZmapDir {
    my $self = shift;

    confess "Cannot set ZMap directory directly" if @_;

    my $ace_path = $self->ace_path();
    my $path = "$ace_path/ZMap";
    unless(-d $path){
        mkdir $path;
        die "Can't mkdir('$path') : $!\n" unless -d $path;
    }
    return $path;
}

sub zMapListMethodNames_ordered{
    my $self = shift;
    my @list = ();
    my $collection = $self->Assembly->MethodCollection;
    $collection->order_by_right_priority;
    return map $_->name, @{$collection->get_all_Methods};
}

#===========================================================

sub xremote_cache{
    my ($self, $cache) = @_;

    if($cache){ $self->{'_xremote_cache'} = $cache; }
    else{       $cache = $self->{'_xremote_cache'}; }
    
    return $cache;
}

sub main_window_name{
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
            client => [{
                created => 0,
                exists  => 1,
            }]
        }
    };
    $zmap->protocol_add_meta($out);

    unless($xml->{'client'}->{'xwid'} 
           && $xml->{'client'}->{'request_atom'}
           && $xml->{'client'}->{'response_atom'}){
        warn "mismatched request for register_client:\n", 
          "id, request and response required\n",
          "Got '", Dumper($xml), "'\n";
        return (403, $zmap->basic_error("Bad Request!"));
    }

    $self->zMapProcessNewClientXML($xml, $self->main_window_name());

    $zmap->post_respond_handler(\&open_clones, [$self]);

    # this feels convoluted
    $out->{'response'}->{'client'}->[0]->{'created'} = 1;

    return (200, make_xml($out));
}

=head1 zMapEdit

A handler to handle edit requests.  Returns a basic response.

=cut

sub zMapEdit{
    my ($self, $xml_hash) = @_;

    my $response;
    my $z  = $self->zMapZmapConnector();
    if ($xml_hash->{"action"} eq 'edit') {
        #warn Dumper($xml_hash);
        my $feat_hash = $xml_hash->{'featureset'}{'feature'}
          or return return(200, $z->handled_response(0));
        
        # Are there any transcripts in the list of features?
        my ($genomic_canonical, @subseq_names);
      NAME: foreach my $name (keys %$feat_hash) {
            my $feat = $feat_hash->{$name};
            if (my $style = $feat->{'style'}) {
                if ($style eq 'Genomic_canonical') {
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
            return(200, $z->handled_response(1));
        }
        elsif (@subseq_names) {
            $self->edit_subsequences(@subseq_names);
            return(200, $z->handled_response(1));
        }
        else {
            return(200, $z->handled_response(0));
        }
    } else {
        confess "Not an 'edit' action:\n", Dumper($xml_hash);
    }
    
}

=head1 zMapHighlight

A  handler  to  handle  single_select  and  multiple_select  requests.
returns a basic response.

=cut

sub zMapHighlight{
    my ($self, $xml_hash) = @_;

    # Needs to do something interesting to find the object to highlight.
    if ($xml_hash->{"action"} eq 'single_select') {
        $self->deselect_all();
        my $feature = $xml_hash->{'featureset'}->{'feature'} || {};
        $self->set_clipboard_on_highlight(0);
        foreach my $name(keys(%$feature)){
            $self->highlight_by_name($name);
        }
        $self->set_clipboard_on_highlight(1);
    } elsif($xml_hash->{"action"} eq 'multiple_select') {
        my $feature = $xml_hash->{'featureset'}->{'feature'} || {};
        $self->set_clipboard_on_highlight(0);
        foreach my $name(keys(%$feature)){
            $self->highlight_by_name($name);
        }
        $self->set_clipboard_on_highlight(1);
    } else { confess "Not a 'select' action\n"; }

    return (200, q{<response handled="true" />});
}

=head1 zMapTagValues

A  handler  to handle  feature_details  request.   returns a  notebook
response.

=cut

sub zMapTagValues {
    my ($self, $xml_hash) = @_;

    # warn Dumper($xml_hash);

    my $pages = "";
    if ($xml_hash->{'action'} eq 'feature_details') {
        my $feature_hash = $xml_hash->{'featureset'}->{'feature'} || {};

        # There is only ever 1 feature in the XML from Zmap
        my ($name) = keys %$feature_hash;
        my $info = $feature_hash->{$name};

        unless ($name) {
            warn "No feature in featurset of XML";
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
    $xml->open_tag('response', {handled => $pages ? 'true' : 'false'});
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
        ($desc) = $txt->get_values('Title');
    }    
    
    return '' unless $taxon_id or $desc;
    
    my $xml = Hum::XmlWriter->new(5);
    
    # Put this on the "Details" page which already exists.
    $xml->open_tag('page', {name => 'Details'});
    $xml->open_tag('subsection', {name => 'Feature'});
    $xml->open_tag('paragraph', {type => 'tagvalue_table'});
    $xml->full_tag('tagvalue', {name => 'Taxon ID', type => 'simple'}, $taxon_id->[0])
        if $taxon_id;
    $xml->full_tag('tagvalue', {name => 'Description', type => 'scrolled_text'}, $desc->[0])
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
        #   Protein => [ qw(Sw:Q99IVF1) ]
        # }

        foreach my $evi_type (keys %$evi_hash) {
            my $evi_array = $evi_hash->{$evi_type};
            foreach my $evi_name (@$evi_array) {
                if ($feat_name eq $evi_name) {
                    push(@$used_subseq_names, $subseq->name);
                    next SUBSEQ;
                }
                # next unless $feat_name eq $evi_name;
                # # check overlapping to see if it really is used.
                # if (!(($info->{'start'} > $subseq->end) &&
                #      ($info->{'end'}    < $subseq->start)))
                # {
                #     push(@$used_subseq_names, $subseq->name);
                #     next SUBSEQ;
                # } else {
                #     warn sprintf("Transcript '%s' does not overlap '%s'",
                #         $subseq->name,
                #         $evi_name);
                # }
            }
        }
    }
    if (@$used_subseq_names) {
        my $xml = Hum::XmlWriter->new(5);    
        $xml->open_tag('page', {name => 'Details'});
        $xml->open_tag('subsection', {name => 'Feature'});
        $xml->open_tag('paragraph', {name => 'Evidence', type => 'homogenous'});
        foreach my $name (@$used_subseq_names) {
            $xml->full_tag('tagvalue', {name => 'for transcript', type => 'simple'}, $name);
        }
        $xml->close_all_open_tags;
        return $xml->flush;
    } else {
        return '';
    }
}



#===========================================================

sub RECEIVE_FILTER {
    my ($connect, $request, $obj, @list) = @_;

    # The table of actions and functions...
    # N.B. the action _must_ be in @list as well as this table
    my $lookup = {
        register_client => 'zMapRegisterClient',
        edit            => 'zMapEdit',
        single_select   => 'zMapHighlight',
        multiple_select => 'zMapHighlight',
        finalised       => 'zMapRelaunchZMap',
        feature_details => 'zMapTagValues',
    };

    # @list could be dynamically created...
    # @list = keys(%$lookup);

    # find the action in the request XML
    #warn "Request = '$request'";
    my $reqXML = parse_request($request);
    my $action = $reqXML->{'action'};

    warn "In RECEIVE_FILTER for action=$action\n" if $ZMAP_DEBUG;

    # The default response code and message.
    my ($status, $response) =
      (404, $obj->zMapZmapConnector->basic_error("Unknown Command"));

    # find the method to call...
    foreach my $valid (@list) {
        if (
            $action eq $valid
            && ($valid =
                $lookup->{$valid}) # N.B. THIS SHOULD BE ASSIGNMENT NOT EQUALITY
            && $obj->can($valid)
          )
        {
            # call the method to get the status and response
            #warn "Calling $obj->$valid($reqXML)";
            ($status, $response) = $obj->$valid($reqXML);
            last;                  # no need to go any further...
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

sub zMapGetXRemoteClientByName{
    my ($self, $key) = @_;

    my $cache = $self->xremote_cache();
    $cache  ||= $self->xremote_cache(ZMap::XRemoteCache->new());

    my $window_id = $cache->lookup_value($key);

    my $client = $cache->get_client_with_id($window_id);

    return $client;
}



sub zMapGetXRemoteClientByAction{
    my ($self, $action, $own_windows_only) = @_;

    my ($pid, $client, $method);

    my $cache = $self->xremote_cache();
    $cache  ||= $self->xremote_cache(ZMap::XRemoteCache->new());

    # warn Dumper $cache;

    $method = ($own_windows_only ? 
               'get_own_client_for_action_pid' : 
               'get_client_for_action_pid');

    if($cache){
        $pid    = $self->zMapPID();
        $client = $cache->$method($action, $pid);
    }

    return $client;
}

sub zMapGetXRemoteClientForView{
    my ($self) = @_;
    my $client = $self->zMapGetXRemoteClientByName($self->slice_name());
    if(!$client){ cluck sprintf("Missing a client for %s. Are you sure zmap is running?", $self->slice_name()); }
    return $client;
}

# open_clones - Displays the data in  a zmap.  This is not a method on
# self,  but  a  standalone  function  taking a  ZMap::Connect  and  a
# MenuCanvasWindow::XaceSeqChooser.

sub open_clones{
    my ($zmap, $self) = @_;

    unless(UNIVERSAL::isa($zmap, 'ZMap::Connect') &&
           UNIVERSAL::isa($self, 'MenuCanvasWindow::XaceSeqChooser')){
        cluck "Usage: open_clones(ZMap::Connect, MenuCanvasWindow::XaceSeqChooser)";
        return ;
    }

    $zmap->post_respond_handler(); # clear the handler...

    my ($chr, $start, $end) = split(/\.|\-/, $self->slice_name);
    warn "Running open_clones [$chr, $start, $end]...\n" if $ZMAP_DEBUG;

    # first open a zmap window...
    my $xremote = $self->zMapGetXRemoteClientByName($self->main_window_name());

    $self->zMapDoRequest($xremote, "new_zmap", qq!<zmap action="new_zmap" />!);

    # now open a view
    my $seg = newXMLObj(  'segment'  );
    setObjNameValue($seg, 'sequence', $self->slice_name);
    setObjNameValue($seg, 'start',    1);
    setObjNameValue($seg, 'end',     '0');

    $xremote = $self->zMapGetXRemoteClientByName("ZMap");

    $self->zMapRegisterClientRequest($xremote);

    $self->zMapDoRequest($xremote, "new_view", obj_make_xml($seg, "new_view"));

    $xremote = $self->zMapGetXRemoteClientByName($self->slice_name());

    $self->zMapRegisterClientRequest($xremote);

    return ;
}

sub zMapRegisterClientRequest{
    my ($self, $xremote) = @_;

    my $zmap = $self->zMapZmapConnector();

    $self->zMapDoRequest($xremote, "register_client", $zmap->connect_request());

    return ;
}

sub zMapDoRequest{
    my ($self, $xremote, $action, @commands) = @_;

    unless($xremote && UNIVERSAL::isa($xremote, 'X11::XRemote')){ 
        cluck "Usage: $self->zMapDoRequest(X11::XRemote, '<action>', (<commands>)" if $ZMAP_DEBUG;
        return 0;
    }
    
    if($ZMAP_DEBUG){
        my $substring = 1; # sometimes you don't need to see _all_ of the request
        if($substring){ 
            map{ warn substr($_, 0, 512), (length($_) > 512 ? "..." : "") } @commands; 
        }else{
            warn "@commands"; 
        }
    }
    
    my @a = $xremote->send_commands(@commands);

    for(my $i = 0; $i < @commands; $i++){
        warn "command $i '",substr($commands[$i], 0, index($commands[$i], '>') + 1),
        "' returned $a[$i] " if $ZMAP_DEBUG;
        my ($status, $xmlHash) = parse_response($a[$i]);
        if($status =~ /^2\d\d/){ # 200s
            $self->RESPONSE_HANDLER($action, $xmlHash);
        }else{
            $self->ERROR_HANDLER($action, $status, $xmlHash);
            last;
        }
    }

    return 1;
}

sub zMapProcessNewClientXML{
    my ($self, $xml, $lookup_key) = @_;

    my $cache = $self->xremote_cache();

    my ($client_tag, $id);

     if(exists($xml->{'response'})){
         $client_tag = $xml->{'response'}->{'client'};
     }else{
         $client_tag = $xml->{'client'};
     }

     if($client_tag){
         my $client_array = [];
         my $add_counter  = 0;
         my $counter      = 0;
         my $full_key     = $lookup_key;

         if(ref($client_tag) eq 'ARRAY'){
             $client_array = $client_tag;
             $add_counter  = 1;
         }else{
             $client_array = [$client_tag];
         }
         
         foreach my $client(@{$client_array}){
             $full_key = "$lookup_key.$counter" if($add_counter);
             if($id = $client->{'xwid'}){
                 # get actions array from xml.
                 my @actions = qw();
                 my $subtag  = q!action!;
                 if(ref($client->{$subtag}) eq 'ARRAY'){
                     push(@actions, @{$client->{$subtag}});
                 }elsif(defined($client->{$subtag}) && !ref($client->{$subtag})){
                     push(@actions, $client->{$subtag});             
                 }else{
                     warn "Odd for a client to not have actions.";
                 }
                 if(!$cache->get_client_with_id($id)){
                     $cache->create_client_with_pid_id_actions($self->zMapPID(), $id, @actions);
                 }
                 $cache->insert_lookup($full_key, $id);
             }
             $counter++;
         }
     }else{
         cluck "malformed register client xml [no window id]";
     }

    return ;
}

sub RESPONSE_HANDLER{
    my ($self, $action, $xml) = @_;

    warn "In RESPONSE_HANDLER for action=$action\n" if $ZMAP_DEBUG;

    # should have something to get the actions from the xml!

    if ($action eq 'new_zmap'){
        $self->zMapProcessNewClientXML($xml, "ZMap");
    } elsif($action eq 'new_view') {
        $self->zMapProcessNewClientXML($xml, $self->slice_name());
    } elsif ($action eq 'list_windows'){
        $self->zMapProcessNewClientXML($xml, "ZMapWindow");
    } elsif($action eq 'register_client' || 
            $action eq 'other actions') {
        # do these
        warn "handled action '$action'" if $ZMAP_DEBUG;
    } elsif($action eq 'zoom_to'){
        #$self->message($xml->{'response'});
    } else {
        cluck "RESPONSE_HANDLER knows nothing about how to handle actions of type '$action'";
    }

    return ;
}

sub ERROR_HANDLER{
    my ($self, $action, $status, $xml) = @_;
    my $message = "";
    if(exists($xml->{'error'})){
        if((ref($xml->{'error'}) eq 'HASH') && 
           (exists($xml->{'error'}->{'message'}))){
            $message = $xml->{'error'}->{'message'};
        }else{
            $message = $xml->{'error'};
        }
    }
    
    warn "action=$action status=$status error=$message" if $ZMAP_DEBUG;

    if($status == 400){

    }elsif($status == 401){

    }elsif($status == 402){

    }elsif($status == 403){

    }elsif($status == 404){
        # could do something clever here so that we don't send the same window this command again.
    }elsif($status == 412){
        $self->xremote_cache->remove_clients_to_bad_windows();
    }elsif($status == 500){
    
    }elsif($status == 501){
    
    }elsif($status == 502){
    
    }elsif($status == 503){
    
    }else{
        warn "I know nothing about status $status\n";
    }
    return ;
}



1;

__END__


=pod

=head1 NAME - MenuCanvasWindow::ZmapSeqChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


=cut

__DATA__



