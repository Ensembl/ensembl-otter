# Disassemble and Reassemble objects to push them through a text channel

package Bio::Otter::Lace::ViaText;

use base ('Exporter');

our @EXPORT    = ();
our @EXPORT_OK = qw( %OrderOfOptions );

our %OrderOfOptions = (
    'AlignFeature' => [
            qw(start end strand hseqname hstart hend hstrand percent_id score dbID),
                ## Special treatment: 'cigar_string',
                ## Not sent (cached): 'analysis->logic_name', 'seqname'
    ],
    'HitDescription' => [
                ## Special treatment: 'name'
            qw(db_name taxon_id hit_length description)
    ],
);

1;

