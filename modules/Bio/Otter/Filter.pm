
### Bio::Otter::Filter

package Bio::Otter::Filter;

use strict;
use warnings;

use Carp;

sub new {
    my ($obj_or_class, @args) = @_;
    
    confess "No arguments to new" if @args;

    return bless {}, ref($obj_or_class) || $obj_or_class;
}

sub server_script {
    my ($self, $server_script) = @_;
    $self->{_server_script} = $server_script if defined $server_script;
    return $self->{_server_script};
}

sub wanted { # it's a flag showing whether the user wants this filter to be loaded
             # ( initialized from ['species'.use_filters] section of otter_config )
    my ($self, $wanted) = @_;

    if(defined($wanted)) {
        $self->{_wanted} = $wanted;
    }
    return $self->{_wanted};
}

sub name {
    # the canonical name for this filter
    my ($self, $name) = @_;
    $self->{_name} = $name if $name;
    return $self->{_name};
}

sub url_string {
    my($self, $url_string) = @_;

    if($url_string) {
        $self->{_url_string} = $url_string;
    }
    return $self->{_url_string};
}

sub description {
    my($self, $description) = @_;

    if($description) {
        $self->{_description} = $description;
    }
    return $self->{_description};
}

sub analysis_name {
    my ($self, $analysis_name) = @_;

    if($analysis_name) {
        $self->{_analysis_name} = $analysis_name;
    }

    # the analysis name defaults to the filter name

    return $self->{_analysis_name} || $self->name;
}

sub metakey {
    my ($self, $metakey) = @_;

    if($metakey) {
        $self->{_metakey} = $metakey;
    }
    return $self->{_metakey};
}

sub csver_remote {
    my ($self, $csver_remote) = @_;

    if($csver_remote) {
        $self->{_csver_remote} = $csver_remote;
    }
    return $self->{_csver_remote};
}

sub feature_kind {
    my ($self, $feature_kind) = @_;
    $self->{_feature_kind} = $feature_kind if $feature_kind;
    return $self->{_feature_kind};
}

sub filter_module {
    my ($self, $filter_module) = @_;
    $self->{_filter_module} = $filter_module if $filter_module;
    return $self->{_filter_module};
}

sub swap_strands {
    my ($self, $swap_strands) = @_;
    $self->{_swap_strands} = $swap_strands if defined $swap_strands;
    return $self->{_swap_strands};
}

sub featuresets {
    my ($self, $featuresets) = @_;

    if ($featuresets) {
        $self->{_featuresets} =
            ref $featuresets ? $featuresets : [split(/,/, $featuresets)];
    }
    
    # the list of featuresets defaults to the name of this filter
    
    $self->{_featuresets} ||= [ $self->name ];
    
    return $self->{_featuresets};
}

sub zmap_column {
    my ($self, $zmap_column) = @_;
    
    if ($zmap_column) {
        $self->{'_zmap_column'} = $zmap_column;
    }
    return $self->{'_zmap_column'};
}

sub zmap_style {
    my ($self, $zmap_style) = @_;
    
    if ($zmap_style) {
        $self->{'_zmap_style'} = $zmap_style;
    }
    return $self->{'_zmap_style'};
}

sub ditypes {
    my ($self, $ditypes) = @_;
    
    if ($ditypes) {
        $self->{'_ditypes'} = $ditypes;
    }
    return $self->{'_ditypes'};
}

sub process_gff_file {
    my($self, $flag) = @_;
    
    if (defined $flag) {
        $self->{'_process_gff_file'} = $flag ? 1 : 0;
    }
    return $self->{'_process_gff_file'};
}

sub server_params {
    
    # this method defines the parameters and their corresponding values that are 
    # required by the otter server to retrieve data for this filter
    
    my ($self) = @_;
    
    return {

        # common
        analysis        => $self->analysis_name,
        kind            => $self->feature_kind,
        csver_remote    => $self->csver_remote,
        metakey         => $self->metakey,
        filter_module   => $self->filter_module,
        swap_strands    => $self->swap_strands,
        url_string      => $self->url_string,

        # GFF
        ditypes         => $self->ditypes,

    };
}


1;

__END__

=head1 NAME - Bio::Otter::Filter

=head1 AUTHOR

Stephen Keenan B<email> keenan@sanger.ac.uk

James Gilbert B<email> jgrg@sanger.ac.uk

Graham Ritchie B<email> gr5@sanger.ac.uk
