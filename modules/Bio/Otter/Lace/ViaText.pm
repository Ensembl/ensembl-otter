# Disassemble and Reassemble objects to push them through a text channel

package Bio::Otter::Lace::ViaText;

use base ('Exporter');

our @EXPORT    = ();
our @EXPORT_OK = qw( %OrderOfOptions );

our %OrderOfOptions = (
    'AlignFeature' => [
        qw(start end strand hseqname hstart hend hstrand percent_id score),
                ## Special treatment: 'cigar_string',
                ## Not sent (cached): 'analysis->logic_name', 'seqname'
    ],
    'HitDescription' => [
                ## Special treatment: 'name'
        qw(db_name taxon_id hit_length description)
    ],
    'SimpleFeature' => [
        qw(start end strand display_label score),
    ],
    'RepeatFeature' => [
        qw(start end strand hstart hend score),
            ## Special treatment: repeat_consensus_id
            ## Not sent (cached): analysis, slice
    ],
    'RepeatConsensus' => [
        qw(name repeat_class repeat_consensus length dbID),
    ],
);

1;

