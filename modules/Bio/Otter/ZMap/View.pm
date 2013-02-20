### Bio::Otter::ZMap::View

package Bio::Otter::ZMap::View;

use strict;
use warnings;
use Carp;
use Try::Tiny;
use Scalar::Util qw( weaken );

use Hum::XmlWriter;

use Bio::Otter::ZMap;
use Bio::Otter::Utils::Config::Ini qw( config_ini_format );
use Bio::Vega::Utils::MacProxyConfig qw{ mac_os_x_set_proxy_vars };

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
        Bio::Otter::ZMap->new(
            '-view'     => $self,
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
    my $method = $action_method_hash->{$action};
    my @result =
        $method
        ? $self->$method($reqXML)
        : (404, $self->zmap->basic_error("Unknown Command"));
    return @result;
}

sub get_mark {
    my ($self) = @_;
    my $hash = $self->send_command('get_mark');
    $hash->{response}->{mark}->{exists} eq "true" or return;
    my $start = abs($hash->{response}->{mark}->{start});
    my $end   = abs($hash->{response}->{mark}->{end});
    if ($end < $start) {
        ($start, $end) = ($end, $start);
    }
    return ($start, $end);
}

sub load_features {
    my ($self, @featuresets) = @_;
    my $hash = $self->send_command(
        'load_features',
        sub {
            my ($xml) = @_;
            $xml->open_tag('align');
            $xml->open_tag('block');
            foreach my $fs_name (@featuresets) {
                $xml->open_tag('featureset', { name => $fs_name });
                $xml->close_tag;
            }
        });
    return;
}

sub delete_featuresets {
    my ($self, @featuresets) = @_;
    my $hash = $self->send_command(
        'delete_feature',
        sub {
            my ($xml) = @_;
            $xml->open_tag('align');
            $xml->open_tag('block');
            for my $featureset (@featuresets) {
                $xml->open_tag('featureset', { name => $featureset });
                $xml->close_tag;
            }
        });
    return;
}

sub zoom_to_subseq {
    my ($self, $subseq) = @_;
    my $hash = $self->send_command(
        'zoom_to',
        sub {
            my ($xml) = @_;
            $xml->open_tag('align');
            $xml->open_tag('block');
            $xml->open_tag('featureset', { name => $subseq->GeneMethod->name });
            $subseq->zmap_xml_feature_tag($xml, $self->SessionWindow->AceDatabase->offset);
        });
    return $hash->{response} =~ /executed/ ? 1 : 0;
}

sub send_command {
    my ($self, $command, $xml_sub) = @_;
    my $xml = Hum::XmlWriter->new;
    $xml->open_tag('zmap');
    $xml->open_tag('request', { action => $command });
    $xml_sub->($xml) if $xml_sub;
    $xml->close_all_open_tags;
    my ($response) = $self->send_commands($xml->flush);
    my ($status, $hash) = @{$response};
    $status =~ /^2/
        or die sprintf
        "XRemote command '%s' failed: status = %s\n"
        , $command, $status;
    return $hash;
}

sub zmap_new_view_parameter_hash {
    my ($self) = @_;
    my $slice = $self->SessionWindow->AceDatabase->smart_slice;
    my $hash = {
        'sequence' => $slice->ssname,
        'start'    => $slice->start,
        'end'      => $slice->end,
    };
    return $hash;
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


=head1 NAME - Bio::Otter::ZMap::View

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut
