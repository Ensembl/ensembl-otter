
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
    my $self = shift;

    if (@_) {
        
        my $featuresets;
        
        # featuresets should be an arrayref
        
        if ($_[0] =~ /,/) {
            # if its a comma delimited string, split it into an arrayref
            $featuresets = [split(/,/, $_[0])];
        }
        elsif (ref($_[0]) ne 'ARRAY') {
            # if the first arg isn't an arrayref we assume the rest of @_ 
            # is a real array and convert it
            $featuresets = [@_];
        }
        
        $self->{_featuresets} = $featuresets;
    }
    
    # the list of featuresets defaults to the name of this filter
    
    $self->{_featuresets} ||= [ $self->name ];
    
    return wantarray ? @{ $self->{_featuresets} } : $self->{_featuresets};
}

sub server_params {
    
    # this method defines the parameters and their corresponding values that are 
    # required by the otter server to retrieve data for this filter
    
    my ($self) = @_;
    
    return {
        analysis        => $self->analysis_name,
        kind            => $self->feature_kind,
        csver_remote    => $self->csver_remote,
        metakey         => $self->metakey,
        filter_module   => $self->filter_module,
        swap_strands    => $self->swap_strands,
        client          => 'otterlace',
    };
}



sub transcript_name_from_transcript_xref {}



1;

__END__

=head1 NAME - Bio::Otter::Filter

=head1 AUTHOR

Stephen Keenan B<email> keenan@sanger.ac.uk

James Gilbert B<email> jgrg@sanger.ac.uk

Graham Ritchie B<email> gr5@sanger.ac.uk
