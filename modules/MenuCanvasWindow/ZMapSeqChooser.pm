### MenuCanvasWindow::ZMapSeqChooser

package MenuCanvasWindow::ZMapSeqChooser;

use strict;
use warnings;
use Carp;
use Try::Tiny;
use Data::Dumper;
use Scalar::Util qw( weaken );

use Hum::XmlWriter;

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
    $self->{_zmap} = $self->_zmap;
    return;
}

sub send_commands {
    my ($self, @xml) = @_;
    my $xremote = $self->xremote;
    warn "Sending window '", $xremote->window_id, "' this xml:\n", @xml;
    my @response_list = $self->zmap->send_commands($xremote, @xml);
    warn "OK?  There was no answer\n" unless @response_list;
    my $fail = 0;
    for (@response_list) {
        my ($status, $xmlHash) = @{$_};
        if ($status !~ /^2\d\d/) {
            my $error = $xmlHash->{'error'}{'message'};
            warn "ERROR: $error\n";
            $fail = 1;
        }
    }
    die "ZMap commands failed\n" if $fail;
    return @response_list;
}

=head2 zmap

This is the way we receive commands from zmap.

=cut

sub zmap {
    my ($self) = @_;
    my $zmap = $self->{_zmap};
    return $zmap;
}

sub _zmap {
    my ($self) = @_;
    my $mb = $self->SessionWindow->menu_bar();
    my $zmap =
        Bio::Otter::ZMap::Connect->new(
            '-handler'  => $self,
            '-tk'       => $mb,
            '-conf_dir' => $self->conf_dir,
            '-arg_list' => $self->arg_list,
        );
    return $zmap;
}

#===========================================================

=head2 zMapEdit

A handler to handle edit requests.  Returns a basic response.

=cut

sub zMapEdit {
    my ($self, $xml_hash) = @_;
    my $response = $self->_zMapEdit($xml_hash);
    return (200, $self->zmap->handled_response($response));
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
    my $features_hash =
        $xml_hash->{'request'}{'align'}{'block'}{'featureset'}{'feature'} || {};
    $self->SessionWindow->zircon_zmap_view_single_select(
        [ keys %$features_hash ]);
    return (200, $self->zmap->handled_response(1));
}

=head2 zMapMultipleSelect

A handler to handle multiple_select requests.  returns a basic
response.

=cut

sub zMapMultipleSelect {
    my ($self, $xml_hash) = @_;
    my $features_hash =
        $xml_hash->{'request'}{'align'}{'block'}{'featureset'}{'feature'} || {};
    $self->SessionWindow->zircon_zmap_view_multiple_select(
        [ keys %$features_hash ]);
    return (200, $self->zmap->handled_response(1));
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
    return (200, $self->zmap->handled_response(1));
}

sub zMapFeaturesLoaded {
    my ($self, $xml) = @_;

    my @featuresets = split(/;/, $xml->{'request'}{'featureset'}{'names'});

    my $status  = $xml->{'request'}{'status'}{'value'};
    my $message = $xml->{'request'}{'status'}{'message'};

    $self->SessionWindow->zircon_zmap_view_features_loaded($status, $message, @featuresets);

    return (200, $self->zmap->handled_response(1));
}

sub zMapIgnoreRequest {
    my ($self) = @_;

    return(200, $self->zmap->handled_response(0));
}

my $action_method_hash = {
    edit            => 'zMapEdit',
    single_select   => 'zMapSingleSelect',
    multiple_select => 'zMapMultipleSelect',
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
        : (404, $self->zmap->basic_error("Unknown Command"));

    warn sprintf
        "\n_zmap_request_callback\nstatus:%d\nresponse\n>>>\n%s\n<<<\n"
        , @result
        if $ZMAP_DEBUG;

    return @result;
}

sub get_mark {
    my ($self) = @_;
    my $xml = qq(<zmap><request action="get_mark" /></zmap>);
    my ($response) = $self->send_commands($xml);
    my ($status, $hash) = @{$response};
    if ($status =~ /^2/ && $hash->{response}->{mark}->{exists} eq "true") {
        my $start = abs($hash->{response}->{mark}->{start});
        my $end   = abs($hash->{response}->{mark}->{end});
        if ($end < $start) {
            ($start, $end) = ($end, $start);
        }
        return ($start, $end);
    }
    return;
}

sub load_features {
    my ($self, @featuresets) = @_;
    my $xml = Hum::XmlWriter->new;
    $xml->open_tag('zmap');
    $xml->open_tag('request', { action => 'load_features' });
    $xml->open_tag('align');
    $xml->open_tag('block');
    foreach my $fs_name (@featuresets) {
        $xml->open_tag('featureset', { name => $fs_name });
        $xml->close_tag;
    }
    $xml->close_all_open_tags;
    my ($response) = $self->send_commands($xml->flush);
    my ($status, $hash) = @{$response};
    unless ($status =~ /^2/) {
        warn "Problem loading featuresets";
    }
    return;
}

sub delete_featuresets {
    my ($self, @featuresets) = @_;
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
    my ($response) = $self->send_commands($xml->flush);
    my ($status, $hash) = @{$response};
    unless ($status =~ /^2/) {
        unless ($hash->{error}->{message} =~ /Unknown FeatureSet/) {
            warn "Problem deleting featuresets: " . $hash->{error}->{message};
        }
    }
    return;
}

sub zoom_to_subseq {
    my ($self, $subseq) = @_;
    my $xml = Hum::XmlWriter->new;
    $xml->open_tag('zmap');
    $xml->open_tag('request', { action => 'zoom_to' });
    $xml->open_tag('align');
    $xml->open_tag('block');
    $xml->open_tag('featureset', { name => $subseq->GeneMethod->name });
    $subseq->zmap_xml_feature_tag($xml, $self->SessionWindow->AceDatabase->offset);
    $xml->close_all_open_tags;
    my ($response) = $self->send_commands($xml->flush);
    my ($status, $hash) = @{$response};
    if ($status =~ /^2/ && $hash->{response} =~ /executed/) {
        return 1;
    }
    return 0;
}

my $zmap_new_view_xml_format = <<'FORMAT'
<zmap>
 <request action="new_view">
  <segment sequence="%s" start="%d" end="%d">
  </segment>
 </request>
</zmap>
FORMAT
    ;

sub zmap_new_view_xml {
    my ($self) = @_;

    my $slice = $self->SessionWindow->AceDatabase->smart_slice;

    my $segment = $slice->ssname;
    my $start   = $slice->start;
    my $end     = $slice->end;

    my @fields = ( $segment, $start, $end );
    my @xml_escaped_fields = map { xml_escape($_) } @fields;
    my $xml = sprintf $zmap_new_view_xml_format, @xml_escaped_fields;

    return $xml;
}

sub xremote {
    my ($self, @args) = @_;
    ($self->{'_xremote'}) = @args if @args;
    my $xremote = $self->{'_xremote'};
    return $xremote;
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
    delete $self->{_zmap};
    return;
}

1;

__END__


=head1 NAME - MenuCanvasWindow::ZmapSeqChooser

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut
