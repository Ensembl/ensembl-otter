
### Bio::Vega::Transform::Otter

package Bio::Vega::Transform::Otter;

use strict;
use Carp;
use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Gene;
use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::Analysis;

use base 'Bio::Vega::Transform';
#use Data::Dumper;   # For debugging

# This misses the "$VAR1 = " bit out from the Dumper() output
#$Data::Dumper::Terse = 1;

my (
    %exon_list,
    %gene_list,
    %transcript_list,
    %feature_list,
    );

sub DESTROY {
    my ($self) = @_;

    delete $exon_list{$self};
    delete $gene_list{$self};
    delete $transcript_list{$self};
    
    # So that DESTROY gets called in baseclass:
    bless $self, 'Bio::Vega::Transform';
}

sub initialize {
    my ($self) = @_;

    # Register the tags that trigger the building of objects
    $self->object_builders(
        {
            exon                => 'build_Exon',
            transcript          => 'build_Transcript',
            locus               => 'build_Locus',
            sequence_fragment   => 'build_Contig',
            evidence            => 'build_Evidence',
            feature             => 'build_Feature',
            assembly_tag        => 'build_AssemblyTag',

            # We don't currently do anything on encountering
            # these end tags:
            sequence_set        => 'report_set_end',
            exon_set            => 'report_set_end',
            evidence_set        => 'report_set_end',
            otter               => 'report_set_end',
            feature_set   => 'report_set_end',
        }
    );
    $self->set_multi_value_tags(
        [
            [ locus             => qw{ remark synonym } ],
            [ transcript        => qw{ remark         } ],
            [ sequence_fragment => qw{ remark keyword } ],
        ]
    );
}

sub report_set_end {
    my ($self) = @_;
    
    # Do nothing
}

sub build_Contig {
    my ($self, $data) = @_;
    
}

sub build_Evidence {
    my ($self, $data) = @_;
    
}

sub build_Feature {
    my ($self, $data) = @_;
    #warn "\nCalling Feature builder to build ", Dumper($data);
    my( %logic_ana );
    my $ana = $logic_ana{$data->{'type'}} ||= Bio::EnsEMBL::Analysis->new(-LOGIC_NAME => $data->{'type'});
    my $feature = Bio::EnsEMBL::SimpleFeature->new(
        -start     => $data->{'start'},
        -end       => $data->{'end'},
        -strand    => $data->{'strand'},
	-analysis      => $ana,
	-score     => $data->{'score'},
	-display_label => $data->{'label'},
    );
    ##slice
    my $list = $feature_list{$self} ||= [];
    push @$list, $feature;
}

sub build_AssemblyTag {
    my ($self, $data) = @_;
    
}

sub build_Exon {
    my ($self, $data) = @_;

    my $exon = Bio::EnsEMBL::Exon->new(
        -start     => $data->{'start'},
        -end       => $data->{'end'},
        -strand    => $data->{'strand'},
        -stable_id => $data->{'stable_id'},
    );
    ### Need to add Slice here.
    my $list = $exon_list{$self} ||= [];
    push @$list, $exon;
}

sub build_Transcript {
    my ($self, $data) = @_;

    my $exons = delete $exon_list{$self};

    my $transcript = Bio::EnsEMBL::Transcript->new(
        -stable_id => $data->{'stable_id'},
        );
    
    foreach my $exon (@$exons) {
        $transcript->add_Exon($exon);
    }
    
    my $list = $transcript_list{$self} ||= [];
    push @$list, $transcript;
}

sub build_Locus {
    my ($self, $data) = @_;

    my $transcripts = delete $transcript_list{$self};

    my $gene = Bio::EnsEMBL::Gene->new(
        -stable_id => $data->{'stable_id'},
        );
    foreach my $tsct (@$transcripts) {
        ### Fails without slice attached
        #$gene->add_Transcript($tsct);
    }

    my $list = $gene_list{$self} ||= [];
    push @$list, $gene;
}

1;

__END__

=head1 NAME - Bio::Vega::Transform::Otter

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

