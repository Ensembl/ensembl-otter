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
our @EXPORT_OK = qw( %LangDesc &ParseFeatures );

our %LangDesc = (
    'SimpleFeature' => {
        -constructor => 'Bio::EnsEMBL::SimpleFeature',
        -optnames    => [ qw(start end strand display_label score) ],
    },

    'HitDescription' => {
        -constructor => 'Bio::Otter::HitDescription',
        -optnames    => [ qw(hit_name db_name taxon_id hit_length description) ],
        -hash_by     => 'hit_name',
    },
    'DnaDnaAlignFeature'=> {
        -constructor => sub{ return Bio::EnsEMBL::DnaDnaAlignFeature->new_fast({}); },
        -optnames    => [ qw(start end strand hstart hend hstrand percent_id score cigar_string hseqname) ],
        -reference   => ['HitDescription', sub{ my($af,$hd)=@_;
                                                    bless $af,'Bio::Otter::DnaDnaAlignFeature';
                                                    $af->{'_hit_description'} = $hd;
                                           },
                                           sub{ my $af = shift @_;
                                                return $af->can('get_HitDescription') ? $af->get_HitDescription() : undef;
                                           } ],
    },
    'DnaPepAlignFeature'=> {
        -constructor => sub{ return Bio::EnsEMBL::DnaPepAlignFeature->new_fast({}); },
        -optnames    => [ qw(start end strand hstart hend hstrand percent_id score cigar_string hseqname) ],
        -reference   => ['HitDescription', sub{ my($af,$hd)=@_;
                                                    bless $af,'Bio::Otter::DnaPepAlignFeature';
                                                    $af->{'_hit_description'} = $hd;
                                           },
                                           sub{ my $af = shift @_;
                                                return $af->can('get_HitDescription') ? $af->get_HitDescription() : undef;
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
        -reference   => [ 'RepeatConsensus', 'repeat_consensus' ],
    },

    'MarkerObject'    => {
        -constructor  => 'Bio::EnsEMBL::Map::Marker',
        -optnames     => [ qw(left_primer right_primer min_primer_dist max_primer_dist dbID) ],
        -hash_by      => 'dbID',
        -get_all_cmps => [ 'MarkerSynonym', 'get_all_MarkerSynonyms' ],
    },
    'MarkerSynonym'  => {
        -constructor => 'Bio::EnsEMBL::Map::MarkerSynonym',
        -optnames    => [ qw(source name) ],
        -add_one_cmp => [ 'MarkerObject', 'add_MarkerSynonyms' ],
    },
    'MarkerFeature'  => {
        -constructor => 'Bio::EnsEMBL::Map::MarkerFeature',
        -optnames    => [ qw(start end map_weight) ],
        -reference   => [ 'MarkerObject', 'marker' ],
    },

    'DitagObject'    => {
        -constructor => sub{ return Bio::EnsEMBL::Map::Ditag->new_fast({}); },
        -optnames    => [ qw(name type sequence dbID) ],
        -hash_by     => 'dbID',
    },
    'DitagFeature'   => {
        -constructor => sub{ return Bio::EnsEMBL::Map::DitagFeature->new_fast({}); },
        -optnames    => [ qw(start end strand hit_start hit_end hit_strand ditag_side ditag_pair_id) ],
        -reference   => [ 'DitagObject', 'ditag' ],
        -hash_by     => sub{ my $self=shift; return $self->ditag()->dbID().'.'.$self->ditag_pair_id();},
    },

    'PredictionTranscript' => {
        -constructor  => 'Bio::EnsEMBL::PredictionTranscript',
        -optnames     => [ qw(start end dbID) ],
        -hash_by      => 'dbID',
        -get_all_cmps => [ 'PredictionExon', 'get_all_Exons' ],
    },
    'PredictionExon' => {
        -constructor => 'Bio::EnsEMBL::Exon', # there was no PredictionExon in EnsEMBL v.19 code
        -optnames    => [ qw(start end strand phase p_value score) ],
        -add_one_cmp => [ 'PredictionTranscript', 'add_Exon' ],
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
        
        if(my $ref_link = $feature_subhash->{-reference}) { # reference link is one-way (the referenced object doesn't know its referees)
            my ($referenced_feature_type, $ref_setter, $ref_getter ) = @$ref_link;
            my $referenced_id      = pop @optvalues;
            if(my $referenced_feature = $feature_hash{$referenced_feature_type}{$referenced_id}) {
                $feature->$ref_setter($referenced_feature);
            }
        } elsif(my $cmp_link = $feature_subhash->{-add_one_cmp}) { # component link is two-way (parent keeps a list of its components)
            my ($parent_feature_type, $add_sub) = @$cmp_link;
            my $parent_id      = pop @optvalues;
            if(my $parent_feature = $feature_hash{$parent_feature_type}{$parent_id}) {
                $parent_feature->$add_sub($feature);
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

            # --------- different ways of storing features: ----------------
        if(my $hash_by = $feature_subhash->{-hash_by}) {
            #
            ## Beware: this distinction by ref/nonref may look deceptive.
            ##         It was purely by coincidence that things hashed by subroutines have to be stored in a different way,
            ##         so I didn't bother to create another flag to indicate whether we want HoHoL or HoH type of storage.
            #
            if(ref $hash_by) { # double-hash-push it into HoHoL:
                push @{ $feature_hash{$feature_type}{&$hash_by($feature)} }, $feature;
            } else { # double-hash it into HoH:
                $feature_hash{$feature_type}{$feature->$hash_by()} = $feature;
            }
        } else { # push it into HoL:
            push @{ $feature_hash{$feature_type} }, $feature;
        }
    }
    return \%feature_hash;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::ViaText

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

