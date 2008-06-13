# Disassemble and Reassemble objects to push them through a text channel
#
# This file is common for both new and old schema

package Bio::Otter::Lace::ViaText;

use strict;
use warnings;

    # objects that can be created by the parser:
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DnaDnaAlignFeature;
use Bio::EnsEMBL::DnaPepAlignFeature;
use Bio::EnsEMBL::PredictionTranscript;
use Bio::EnsEMBL::RepeatConsensus;
use Bio::EnsEMBL::RepeatFeature;
use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::Map::MarkerSynonym;
use Bio::EnsEMBL::Map::Marker;
use Bio::EnsEMBL::Map::MarkerFeature;
use Bio::EnsEMBL::Map::Ditag;
use Bio::EnsEMBL::Map::DitagFeature;
use Bio::Otter::DnaDnaAlignFeature;
use Bio::Otter::DnaPepAlignFeature;
use Bio::Otter::HitDescription;

use base ('Exporter');
our @EXPORT    = ();
our @EXPORT_OK = qw( %OrderOfOptions %LangDesc &ParseFeatures );

our %LangDesc = (
    'SimpleFeature' => {
        -constructor => 'Bio::EnsEMBL::SimpleFeature',
        -optnames    => [ qw(start end strand display_label score) ],
    },

    'HitDescription' => {
        -constructor => 'Bio::Otter::HitDescription',
        -optnames    => [ qw(db_name taxon_id hit_length description) ],
        -hash_by     => 'db_name',
    },
    'DnaAlignFeature'=> {
        -constructor => sub{ return Bio::EnsEMBL::DnaDnaAlignFeature->new_fast({}); },
        -optnames    => [ qw(start end strand hstart hend hstrand percent_id score cigar_string hseqname) ],
        -link        => ['HitDescription', sub{ my($af,$hd)=@_;
                                                 if($hd) {
                                                    bless $af,'Bio::Otter::DnaDnaAlignFeature';
                                                    $af->{'_hit_description'} = $hd;
                                                 }
                                              } ],
    },
    'PepAlignFeature'=> {
        -constructor => sub{ return Bio::EnsEMBL::DnaPepAlignFeature->new_fast({}); },
        -optnames    => [ qw(start end strand hstart hend hstrand percent_id score cigar_string hseqname) ],
        -link        => ['HitDescription', sub{ my($af,$hd)=@_;
                                                 if($hd) {
                                                    bless $af,'Bio::Otter::DnaPepAlignFeature';
                                                    $af->{'_hit_description'} = $hd;
                                                 }
                                              } ],
    },

    'RepeatConsensus'=> {
        -constructor => 'Bio::EnsEMBL::RepeatConsensus',
        -optnames    => [ qw(name repeat_class repeat_consensus length dbID) ],
        -hash_by     => 'dbID',
    },
    'RepeatFeature'  => {
        -constructor => 'Bio::EnsEMBL::RepeatFeature',
        -optnames    => [ qw(start end strand hstart hend score) ],
        -link        => [ 'RepeatConsensus', sub{ my($rf,$rc)=@_; $rf->repeat_consensus($rc);} ],
    },

    'MarkerObject'   => {
        -constructor => 'Bio::EnsEMBL::Map::Marker',
        -optnames    => [ qw(left_primer right_primer min_primer_dist max_primer_dist dbID) ],
        -hash_by     => 'dbID',
    },
    'MarkerSynonym'  => {
        -constructor => 'Bio::EnsEMBL::Map::MarkerSynonym',
        -optnames    => [ qw(source name) ],
        -link        => [ 'MarkerObject', sub{ my($ms,$mo)=@_; $mo->add_MarkerSynonyms($ms);} ],
    },
    'MarkerFeature'  => {
        -constructor => 'Bio::EnsEMBL::Map::MarkerFeature',
        -optnames    => [ qw(start end map_weight) ],
        -link        => [ 'MarkerObject', sub{ my($mf,$mo)=@_; $mf->marker($mo);} ],
    },

    'DitagObject'    => {
        -constructor => sub{ return Bio::EnsEMBL::Map::Ditag->new_fast({}); },
        -optnames    => [ qw(name type sequence dbID) ],
        -hash_by     => 'dbID',
    },
    'DitagFeature'   => {
        -constructor => sub{ return Bio::EnsEMBL::Map::DitagFeature->new_fast({}); },
        -optnames    => [ qw(start end strand hit_start hit_end hit_strand ditag_side ditag_pair_id) ],
        -link        => [ 'DitagObject', sub{ my($df,$do)=@_; $df->ditag($do);} ],
        -hash_by     => sub{ my $self=shift; return $self->ditag()->dbID().'.'.$self->ditag_pair_id();},
    },

    'PredictionTranscript' => {
        -constructor => 'Bio::EnsEMBL::PredictionTranscript',
        -optnames    => [ qw(start end display_label) ],
        -hash_by     => 'display_label',
    },
    'PredictionExon' => {
        -constructor => 'Bio::EnsEMBL::Exon', # there was no PredictionExon in EnsEMBL v.19 code
        -optnames    => [ qw(start end strand phase p_value score) ],
        -link        => [ 'PredictionTranscript', sub{ my($pe,$pt)=@_; $pt->add_Exon($pe);} ],
    },
);

sub ParseFeatures {
    my ($response_ref, $seqname, $analysis_name) = @_;

    my %feature_hash = (); # first level hashed by type, second level depends on -hash_by (pushed if undefined)

    my %analysis_hash = ();

        # we should switch over to processing the stream, when it becomes possible
    my $resplines_ref = [ split(/\n/,$$response_ref) ];

    foreach my $respline (@$resplines_ref) {
        my @optvalues  = split(/\t/,$respline);

        my $logic_name = $analysis_name || pop @optvalues;

        my $feature_type    = shift @optvalues; # 'SimpleFeature'|'HitDescription'|...|'PredictionExon'
        my $feature_subhash = $LangDesc{$feature_type};

        my $constructor     = $feature_subhash->{-constructor};
        my $feature = ref $constructor ? &$constructor() : $constructor->new();

        my $optnames        = $feature_subhash->{-optnames};
        for(my $i=0; $i < @$optnames; $i++) {
            my $method = $optnames->[$i];
            $feature->$method($optvalues[$i]);
        }
        
        if(my $link = $feature_subhash->{-link}) {
            my ($linked_feature_type, $link_sub) = @$link;
            my $linked_id      = pop @optvalues;
            if(my $linked_feature = $feature_hash{$linked_feature_type}{$linked_id}) {
                &$link_sub($feature,$linked_feature);
            }
        }

        if($feature->can('analysis')) {
            $feature->analysis(
                $analysis_hash{$logic_name} ||= Bio::EnsEMBL::Analysis->new(-logic_name => $logic_name)
            );
        }

        if($feature->can('seqname')) {
            $feature->seqname($seqname);
        }

            # either double-hash it or hash-push it:
        if(my $hash_by = $feature_subhash->{-hash_by}) {
            $feature_hash{$feature_type}{$feature->$hash_by()} = $feature;
        } else {
            push @{ $feature_hash{$feature_type} }, $feature;
        }
    }
    return \%feature_hash;
}

our %OrderOfOptions = (

    'SimpleFeature' => [
        qw(start end strand display_label score),
            ## Not sent (passed): 'seqname'
    ],

        # Fixme: hit_name is a linking field and should be sent last in the line
    'HitDescription' => [
            ## Special treatment: 'name'
        qw(db_name taxon_id hit_length description)
    ],
    'AlignFeature' => [
        qw(start end strand hstart hend hstrand percent_id score cigar_string hseqname),
            ## Not sent (passed): 'seqname'
    ],

    'RepeatFeature' => [
        qw(start end strand hstart hend score),
            ## Special treatment: repeat_consensus_id
            ## Not sent (cached): analysis, slice
    ],
    'RepeatConsensus' => [ # 'slave' to RepeatFeature
        qw(name repeat_class repeat_consensus length dbID),
    ],

    'MarkerFeature' => [
        qw(start end map_weight),
            ## Special treatment: marker_object_id
            ## Not sent (cached): analysis, slice
    ],
    'MarkerObject' => [ # 'slave' to MarkerFeature
        qw(left_primer right_primer min_primer_dist max_primer_dist dbID),
    ],
    'MarkerSynonym' => [ # 'slave' to MarkerObject
        qw(source name),
    ],

    'DitagFeature' => [
        qw(start end strand hit_start hit_end hit_strand ditag_side ditag_pair_id),
            ## Special treatment: ditag_id
            ## Not sent (cached): analysis, slice
    ],
    'DitagObject'  => [ # 'slave' to DitagFeature
        qw(name type sequence dbID),
    ],

    'PredictionTranscript' => [
        qw(start end),
            ## Special treatment: label = display_label() || dbID()
            ## Not sent (cached): analysis
    ],
    'PredictionExon' => [
        qw(start end strand phase p_value score),
            ## Special treatment: label = pt->display_label() || pt->dbID()
            ## Not sent (cached): analysis
    ],
);

1;

__END__

=head1 NAME - Bio::Otter::Lace::ViaText

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

