# Disassemble and Reassemble objects to push them through a text channel

package Bio::Otter::Lace::ViaText;

use base ('Exporter');

our @EXPORT    = ();
our @EXPORT_OK = qw( %OrderOfOptions );

our %OrderOfOptions = (
    'HitDescription' => [
                ## Special treatment: 'name'
        qw(db_name taxon_id hit_length description)
    ],
    'AlignFeature' => [
        qw(start end strand hseqname hstart hend hstrand percent_id score),
                ## Special treatment: 'cigar_string', 'analysis->logic_name'
                ## Not sent (cached): 'seqname'
    ],

    'SimpleFeature' => [
        qw(start end strand display_label score),
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

    'RepeatFeature' => [
        qw(start end strand hstart hend score),
            ## Special treatment: repeat_consensus_id
            ## Not sent (cached): analysis, slice
    ],
    'RepeatConsensus' => [ # 'slave' to RepeatFeature
        qw(name repeat_class repeat_consensus length dbID),
    ],

    'PredictionTranscript' => [
        qw(start end dbID),
            ## Not sent (cached): analysis
    ],
    'PredictionExon' => [
        qw(start end strand phase p_value score),
            ## Special treatment: prediction_transcript_id
            ## Not sent (cached): analysis
    ],
);

1;

