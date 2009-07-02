# Disassemble and Reassemble objects to push them through a text channel
#
# This file is common for both new and old schema

package Bio::Otter::Lace::ViaText;

use strict;
use warnings;
use Carp;

    # objects that can be created by the parser:
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
use Bio::Otter::DnaDnaAlignFeature;
use Bio::Otter::DnaPepAlignFeature;
use Bio::Otter::HitDescription;

use base ('Exporter');
our @EXPORT    = ();
our @EXPORT_OK = qw( %LangDesc &ParseFeatures &GenerateFeatures );

our %LangDesc = (
    'SimpleFeature' => {
        -constructor => 'Bio::EnsEMBL::SimpleFeature',
        -optnames    => [ qw(start end strand display_label score) ],
        -call_args   => [['analysis' => undef]],
        -gff_feature_type => 'misc_feature',
    },

    'HitDescription' => {
        -constructor => 'Bio::Otter::HitDescription',
        -optnames    => [ qw(hit_name db_name taxon_id hit_length description) ],
        -hash_by     => 'hit_name',
    },
    'DnaDnaAlignFeature'=> {
        -constructor => sub{ return Bio::EnsEMBL::DnaDnaAlignFeature->new_fast({}); },
        -optnames    => [ qw(start end strand hstart hend hstrand percent_id score cigar_string hseqname) ],
        -reference   => ['HitDescription', 'hseqname',
                                           sub{ my($af,$hd)=@_;
                                                    bless $af,'Bio::Otter::DnaDnaAlignFeature';
                                                    $af->{'_hit_description'} = $hd;
                                           },
                                           sub{ my $af = shift @_;
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
                                                    bless $af,'Bio::Otter::DnaPepAlignFeature';
                                                    $af->{'_hit_description'} = $hd;
                                           },
                                           sub{ my $af = shift @_;
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
        -group_by    => sub{ my $self=shift; return $self->ditag()->dbID().'.'.$self->ditag_pair_id();},
        -call_args   => [['ditypes'  => undef], ['analysis' => undef]],
    },

    # a dummy feature type, actually a list of BaseAlignFeatures
    'TranscriptBestSupportingFeature' => {
        -call_args   => [['load_exons' => 1]],
    },

    'PredictionTranscript' => {
        -constructor  => 'Bio::EnsEMBL::PredictionTranscript',
        -optnames     => [ qw(start end dbID) ],
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

# a Bio::EnsEMBL::Slice method to handle the dummy TranscriptBestSupportingFeature feature type
sub Bio::EnsEMBL::Slice::get_all_TranscriptBestSupportingFeatures {
    my $self = shift;
    my $load_exons = 1;
    my $logic_name = shift;
    my $dbtype     = shift;
    if(!$self->adaptor()) {
	warning('Cannot get Transcripts without attached adaptor');
	return [];
    }

    my $transcripts =
	$self->get_all_Transcripts($load_exons, $logic_name, $dbtype);
    my $transcript_feature_list =
	[ map {
	    my $supporting_features =
		$_->get_all_supporting_features;
	    my $exons =
		$_->get_all_Exons;
	    my $exon_supporting_features =
		[ map @{$_->get_all_supporting_features}, @$exons ];
	    [ $_, $supporting_features, $exons, $exon_supporting_features, ];
	} @$transcripts ];
    my $bogus_transcript_count =
	grep((@{$_->[0]} != 1), @$transcript_feature_list);

    my $method = "get_all_TranscriptBestSupportingFeatures";
    my $format = <<FORMAT;
%s::%s()
  number of transcripts: %d
  number of transcripts without exactly 1 supporting feature: %d
  transcript: sequence(#(supporting features), #exons, #(exon supporting features))
    %s
Died
FORMAT
;
    chomp $format;
    die sprintf $format, __PACKAGE__, $method,
    scalar(@$transcript_feature_list),
    $bogus_transcript_count,
    join "\n    ",
    map sprintf("%s(%d, %d, %d)",
		$_->[0]->seqname,
		scalar(@{$_->[1]}),
		scalar(@{$_->[2]}),
		scalar(@{$_->[3]}),
		),
    @$transcript_feature_list[0...10];
}

sub GenerateFeatures {
    my ($features, $analysis_name) = @_;

    my %seen_hash     = (); # we don't store objects here, just count them
    my $cumulative_output = ''; # alternatively we can print things out into a FileHandle/Socket as they arrive

    foreach my $feature (@$features) {
        my ($feature_output, $hash_key) = generate_unless_hashed($feature, '', \%seen_hash, $analysis_name);
        $cumulative_output .= $feature_output;
    }

    return $cumulative_output;
}

sub generate_unless_hashed {
    my ($feature, $parent_hash_key, $seen_hash, $analysis_name) = @_;

    ref($feature) =~ /::(\w+)$/;
    my $feature_type = $1;

    my $feature_subhash = $LangDesc{$feature_type};

    my $hash_key;    # will be included in @optvalues if set

    if(my $hash_by = $feature_subhash->{-hash_by}) { # only output hashable feature once:
        $hash_key = $feature->$hash_by();
        if($seen_hash->{$feature_type}{$hash_key}++) {
            return ('', $hash_key);
        }
    }

    my $cumulative_output = ''; # alternatively we can print things out into a FileHandle/Socket as they arrive

        ## now let's generate our own fields:

    my $optnames  = $feature_subhash->{-optnames};
    my @optvalues = ($feature_type);
    for my $opt (@$optnames) {
        push @optvalues, $feature->$opt() || 0;
    }

    if(my $ref_link = $feature_subhash->{-reference}) { # reference link is one-way (the referenced object doesn't know its referees)
        my ($referenced_feature_type, $ref_field, $ref_setter, $ref_getter ) = @$ref_link;
        $ref_getter ||= $ref_setter; # let's avoid duplication, since in most cases getter is the same method as setter

        my $ref_hash_key;
        if(my $referenced_feature = $feature->$ref_getter()) { # we allow it to be false too
            my $reference_output;
            ($reference_output, $ref_hash_key) =  generate_unless_hashed($referenced_feature, '', $seen_hash, $analysis_name);
            $cumulative_output .= $reference_output;
        }

        if(not $ref_field) {
            push @optvalues, $ref_hash_key || 0;
        }
    }

    if($parent_hash_key) {
        push @optvalues, $parent_hash_key;
    }
	my @analysis = split(/,/,$analysis_name);
    if($feature->can('analysis') && (!$analysis_name || scalar(@analysis) > 1)) {
        push @optvalues, $feature->analysis()->logic_name();
    }

    $cumulative_output .= join("\t", @optvalues)."\n";

        # after outputting itself a parent lists all of its components:
        #
    if(my $cmps_getter = $feature_subhash->{-get_all_cmps}) { # component link is two-way (parent keeps a list of its components)
        foreach my $component_feature (@{ $feature->$cmps_getter() }) {
            my ($component_output, $to_be_ignored) = generate_unless_hashed($component_feature, $hash_key, $seen_hash, $analysis_name);
            $cumulative_output .= $component_output;
        }
    }

    return ($cumulative_output, $hash_key);
}

sub ParseFeatures {
    my ($response_ref, $seqname, $analysis_name) = @_;

    my %feature_hash = (); # first level hashed by type, second level depends on -hash_by (pushed if undefined)

    my %analysis_hash = ();

        # we should switch over to processing the stream, when it becomes possible
    my $resplines_ref = [ split(/\n/,$$response_ref) ];

    foreach my $respline (@$resplines_ref) {
        my @optvalues  = split(/\t/, $respline);

        unless (@optvalues) {
            confess "Blank line in output - due to newline on end of hit description?";
        }


        my $feature_type    = shift @optvalues; # 'SimpleFeature'|'HitDescription'|...|'PredictionExon'
        my $feature_subhash = $LangDesc{$feature_type};

        my $constructor = $feature_subhash->{-constructor};
        my $optnames    = $feature_subhash->{-optnames};
        my $feature;
        if (ref $constructor) {
            $feature = $constructor->();
            for(my $i=0; $i < @$optnames; $i++) {
                my $method = $optnames->[$i];
                $feature->$method($optvalues[$i]);
            }
        } else {
            my @args = ();
            for (my $i = 0; $i < @$optnames; $i++) {
                my $method = $optnames->[$i];
                my $value  = $optvalues[$i];
                # EnsEMBL appears to stick to the convention that the labelled
                # arguments to new are of the form "-method_name"
                push(@args, "-$method", $value);
            }
            $feature = $constructor->new(@args);
        }

        my $logic_name = $analysis_name;
        my @analysis = split(/,/,$analysis_name);
        if($feature->can('analysis') && (!$analysis_name || scalar(@analysis) > 1 )) {
        	$logic_name = pop @optvalues;
    	}

        if(my $ref_link = $feature_subhash->{-reference}) { # reference link is one-way (the referenced object doesn't know its referees)
            my ($referenced_feature_type, $ref_field, $ref_setter, $ref_getter ) = @$ref_link;
            my $referenced_id  = $ref_field ? $feature->$ref_field() : pop @optvalues; # it can either be named or nameless
            if(my $referenced_feature = $feature_hash{$referenced_feature_type}{$referenced_id}) {
                $feature->$ref_setter($referenced_feature);
            }
        } elsif(my $cmp_uplink = $feature_subhash->{-add_one_cmp}) { # component link is two-way (parent keeps a list of its components)
            my ($parent_feature_type, $add_sub) = @$cmp_uplink;
            my $parent_id = pop @optvalues; # always nameless
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
        if(my $hash_by = $feature_subhash->{-hash_by}) { # double-hash it into HoH (referenced objects):
            
            $feature_hash{$feature_type}{$feature->$hash_by()} = $feature;

        } elsif(my $group_by = $feature_subhash->{-group_by}) { # double-hash-push it into HoHoL (ditag_features):

            push @{ $feature_hash{$feature_type}{$feature->$group_by()} }, $feature;

        } else { # push it into HoL (any non-ditag '*_features'):

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

