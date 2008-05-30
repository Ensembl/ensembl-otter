# Disassemble and Reassemble objects to push them through a text channel
#
# This file is common for both new and old schema

package Bio::Otter::Lace::ViaText;

use strict;
use warnings;

use base ('Exporter');
our @EXPORT    = ();
our @EXPORT_OK = qw( %OrderOfOptions &ParseSimpleFeatures &ParseAlignFeatures &ParseRepeatFeatures
                     &ParseMarkerFeatures &ParseDitagFeatureGroups &ParsePredictionTranscripts );

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
        qw(start end strand hseqname hstart hend hstrand percent_id score),
            ## Special treatment: 'cigar_string', 'analysis->logic_name'
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

