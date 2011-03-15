# Disassemble and Reassemble objects to push them through a text channel
#
# This file is common for both new and old schema

package Bio::Otter::Lace::ViaText;

use strict;
use warnings;
use Carp;

use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DnaDnaAlignFeature;
use Bio::EnsEMBL::DnaPepAlignFeature;
use Bio::EnsEMBL::PredictionTranscript;
use Bio::EnsEMBL::PredictionExon;
use Bio::EnsEMBL::RepeatConsensus;
use Bio::EnsEMBL::RepeatFeature;
use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::Map::MarkerSynonym;
use Bio::EnsEMBL::Map::Marker;
use Bio::EnsEMBL::Map::MarkerFeature;
use Bio::EnsEMBL::Map::Ditag;
use Bio::EnsEMBL::Map::DitagFeature;
use Bio::EnsEMBL::Variation::Variation;
use Bio::EnsEMBL::Variation::VariationFeature;
use Bio::Vega::DnaDnaAlignFeature;
use Bio::Vega::DnaPepAlignFeature;
use Bio::Vega::HitDescription;
use Bio::Vega::PredictionTranscript;

use base ('Exporter');
our @EXPORT_OK = qw( %LangDesc );

our %LangDesc = ( ## no critic(Variables::ProhibitPackageVars)
    'SimpleFeature' => {
        -constructor => 'Bio::EnsEMBL::SimpleFeature',
        -optnames    => [ qw(start end strand display_label score) ],
        -call_args   => [['analysis' => undef]],
        -gff_feature_type => 'misc_feature',
    },

    'HitDescription' => {
        -constructor => 'Bio::Vega::HitDescription',
        -optnames    => [ qw(hit_name db_name taxon_id hit_length description) ],
        -hash_by     => 'hit_name',
    },
    'DnaDnaAlignFeature'=> {
        -constructor => sub{ return Bio::EnsEMBL::DnaDnaAlignFeature->new_fast({}); },
        -optnames    => [ qw(start end strand hstart hend hstrand percent_id score cigar_string hseqname) ],
        -reference   => ['HitDescription', 'hseqname',
                                           sub{ my($af,$hd)=@_;
                                                    bless $af,'Bio::Vega::DnaDnaAlignFeature';
                                                    $af->{'_hit_description'} = $hd;
                                           },
                                           sub{ my($af)=@_;
                                                return $af->can('get_HitDescription') ? $af->get_HitDescription() : undef;
                                           } ],
         -call_args  => [['analysis' => undef], ['score' => undef], ['dbtype' => undef]],
         -gff_feature_type => 'similarity',
    },
    'DnaPepAlignFeature'=> {
        -constructor => sub{ return Bio::EnsEMBL::DnaPepAlignFeature->new_fast({}); },
        -optnames    => [ qw(start end strand hstart hend hstrand percent_id score cigar_string hseqname) ],
        -reference   => ['HitDescription', 'hseqname',
                                           sub{ my($af,$hd)=@_;
                                                    bless $af,'Bio::Vega::DnaPepAlignFeature';
                                                    $af->{'_hit_description'} = $hd;
                                           },
                                           sub{ my($af)=@_;
                                                return $af->can('get_HitDescription') ? $af->get_HitDescription() : undef;
                                           } ],
         -call_args  => [['analysis' => undef], ['score' => undef], ['dbtype' => undef]],
         -gff_feature_type => 'similarity',
    },

    'RepeatConsensus'=> {
        -constructor => 'Bio::EnsEMBL::RepeatConsensus',
        -optnames    => [ qw(name repeat_class repeat_consensus length dbID) ],
        -hash_by     => 'dbID',
    },
    'RepeatFeature'  => {
        -constructor => 'Bio::EnsEMBL::RepeatFeature',
        -optnames    => [ qw(start end strand hstart hend score) ],
        -reference   => [ 'RepeatConsensus', '', 'repeat_consensus' ],
        -call_args   => [['analysis' => undef], ['repeat_type' => undef], ['dbtype' => undef]],
    },

    'Marker'          => {
        -constructor  => 'Bio::EnsEMBL::Map::Marker',
        -optnames     => [ qw(left_primer right_primer min_primer_dist max_primer_dist dbID) ],
        -hash_by      => 'dbID',
        -get_all_cmps => 'get_all_MarkerSynonyms',
    },
    'MarkerSynonym'  => {
        -constructor => 'Bio::EnsEMBL::Map::MarkerSynonym',
        -optnames    => [ qw(source name) ],
        -add_one_cmp => [ 'Marker', 'add_MarkerSynonyms' ],
    },
    'MarkerFeature'  => {
        -constructor => 'Bio::EnsEMBL::Map::MarkerFeature',
        -optnames    => [ qw(start end map_weight) ],
        -reference   => [ 'Marker', '', 'marker' ],
        -call_args   => [['analysis' => undef], ['priority' => undef], ['map_weight' => undef]],
    },

    'Variation' => {
        -constructor => 'Bio::EnsEMBL::Variation::Variation',
        -optnames    => [ qw(name source dbID) ],
        -hash_by      => 'dbID',
    },
    'VariationFeature' => {
        -constructor => 'Bio::EnsEMBL::Variation::VariationFeature',
        -optnames    => [ qw(start end strand allele_string) ],
        -reference   => [ 'Variation', '', 'variation' ],
        -call_args   => [],
    },

    'Ditag' => {
        -constructor    => 'Bio::EnsEMBL::Map::Ditag',
        -optnames       => [ qw(name type sequence dbID) ],
        -hash_by        => 'dbID',
        -fast           => 1
    },
    'DitagFeature'   => {
        -constructor => 'Bio::EnsEMBL::Map::DitagFeature',
        -optnames    => [ qw(start end strand hit_start hit_end hit_strand ditag_side ditag_pair_id) ],
        -reference   => [ 'Ditag', '', 'ditag' ],
            # group_by is used *only* by the parser for storing things in arrays in the feature_hash
            #          Hashing is similar to hash_by, but there is an additinal level of structure.
        -group_by    => sub{ my ($self)=@_; return $self->ditag()->dbID().'.'.$self->ditag_pair_id();},
        -call_args   => [['ditypes', undef, qr/,/], ['analysis' => undef]],
    },

    # a dummy feature type, actually returns a list of DnaDnaAlignFeatures
    'ExonSupportingFeature' => {
        -call_args   => [['analysis' => undef]],
    },

    'PredictionTranscript' => {
        -constructor  => 'Bio::Vega::PredictionTranscript',
        -optnames     => [ qw(start end dbID truncated_5_prime truncated_3_prime) ],
        -hash_by      => 'dbID',
        -get_all_cmps => 'get_all_Exons',
        -call_args   => [['analysis' => undef], ['load_exons' => 1]],
    },
    'PredictionExon' => {
        -constructor => 'Bio::EnsEMBL::PredictionExon',
        -optnames    => [ qw(start end strand phase p_value score) ],
        -add_one_cmp => [ 'PredictionTranscript', 'add_Exon' ],
    },
);

1;

__END__

=head1 NAME - Bio::Otter::Lace::ViaText

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

