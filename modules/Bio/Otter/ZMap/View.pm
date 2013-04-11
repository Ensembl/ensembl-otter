### Bio::Otter::ZMap::View

package Bio::Otter::ZMap::View;

use strict;
use warnings;
use Carp;
use Try::Tiny;
use Scalar::Util qw( weaken );

use Hum::XmlWriter;

sub new {
    my ($pkg, %arg_hash) = @_;
    my $new = bless { }, $pkg;
    $new->_init(\%arg_hash);
    return $new;
}

sub _init {
    my ($self, $arg_hash) = @_;
    @{$self}{qw( _name _zmap _xremote _SessionWindow )} =
        @{$arg_hash}{qw( -name -zmap -xremote -SessionWindow )};
    $self->{'_zmap_proxy'} = $self->zmap->proxy;
    weaken $self->{_SessionWindow};
    return;
}

sub send_command_and_xml {
    my ($self, $command, @xml) = @_;

    my $debug = Bio::Otter::Debug->debug('XRemote');

    my $request = Hum::XmlWriter->new;
    $request->open_tag('zmap');
    $request->open_tag('request', { action => $command });
    if (@xml) {
        $request->open_tag('align');
        $request->open_tag('block');
        foreach my $x (@xml) {
            $request->add_raw_data_with_indent($x);
        }
    }
    $request->close_all_open_tags;
    my $request_xml = $request->flush;

    my $xremote = $self->xremote;
    if ($debug) {
        warn sprintf "Sending window '%s' this xml:\n%s", $xremote->window_id, $request_xml;
    }
    my ($response) = $self->zmap->send_commands($xremote, $request_xml);
    my ($status, $xmlHash) = @$response;
    if ($status =~ /^2\d\d/) {
        if ($debug) {
            warn sprintf "XRemote command OK:\n%s\n", $command
        }
        return $xmlHash;
    }
    else {
        my $error = $xmlHash->{'error'}{'message'};
        if ($debug) {
            warn sprintf "XRemote command FAILED: status='%s'; %s\n%s",
                $status, $error, $command;
        }
        die "ZMap commands failed\n";
    }
}

=head2 zmap

A Bio::Otter::ZMap object which is used to communicate with zmap.

=cut

sub zmap {
    my ($self) = @_;
    my $zmap = $self->{'_zmap'};
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
    my $hash = $self->send_command_and_xml('get_mark');
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
    
    my $xml = Hum::XmlWriter->new;
    foreach my $fs_name (@featuresets) {
        $xml->open_tag('featureset', { name => $fs_name });
        $xml->close_tag;
    }
    
    $self->send_command_and_xml('load_features', $xml->flush);
    return;
}

sub delete_featuresets {
    my ($self, @featuresets) = @_;

    my $xml = Hum::XmlWriter->new;
    foreach my $featureset (@featuresets) {
        $xml->open_tag('featureset', { name => $featureset });
        $xml->close_tag;
    }
    $self->send_command_and_xml('delete_feature', $xml->flush);
    return;
}

sub zoom_to_subseq {
    my ($self, $subseq) = @_;

    my $xml = Hum::XmlWriter->new;
    $xml->open_tag('featureset', { name => $subseq->GeneMethod->name });
    $subseq->zmap_xml_feature_tag($xml, $self->SessionWindow->AceDatabase->offset);
    $xml->close_all_open_tags;
    my $hash = $self->send_command_and_xml('zoom_to', $xml->flush);
    return $hash->{response} =~ /executed/ ? 1 : 0;
}

sub name {
    my ($self) = @_;
    my $name = $self->{'_name'};
    return $name;
}

sub xremote {
    my ($self, @args) = @_;
    my $xremote = $self->{'_xremote'};
    return $xremote;
}

sub SessionWindow {
    my ($self) = @_;
    my $SessionWindow = $self->{'_SessionWindow'};
    return $SessionWindow;
}

sub id {
    my ($self) = @_;
    my $id = $self->xremote->window_id;
    return $id;
}

sub DESTROY {
    my ($self) = @_;
    # we do not delete _zmap or _zmap_proxy so as to ensure that the
    # ZMap object is destroyed *after* all of its views
    $self->zmap->close_view($self);
    return;
}

1;

__END__


=head1 NAME - Bio::Otter::ZMap::View

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut
