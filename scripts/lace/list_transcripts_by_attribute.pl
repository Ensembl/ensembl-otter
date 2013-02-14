#!/usr/bin/env perl

# In response to ticket #193917: List of NMD exceptions

use warnings;
use strict;

use Carp;
use Bio::Otter::Lace::Defaults;

{
    my $dataset_name = undef;
    my $attrib_pattern = undef;
    my $attrib_code = 'remark';

    my $total = 0;
    my $quiet = 0;

    my $usage = sub { exec('perldoc', $0) };
    # This do_getopt() call is needed to parse the otter config files
    # even if you aren't giving any arguments on the command line.
    Bio::Otter::Lace::Defaults::do_getopt(
        'h|help!'       => $usage,
        'dataset=s'     => \$dataset_name,
    'attrib=s'      => \$attrib_pattern,
    'code:s'        => \$attrib_code,
        'quiet!'        => \$quiet,
        'total!'        => \$total,
        ) or $usage->();
    $usage->() unless ($dataset_name and $attrib_pattern);

    # Client communicates with otter HTTP server
    my $cl = Bio::Otter::Lace::Defaults::make_Client();
    
    # DataSet interacts directly with an otter database
    my $ds = $cl->get_DataSet_by_name($dataset_name);
    my $otter_dba = $ds->get_cached_DBAdaptor;

    my $list_transcripts = $otter_dba->dbc->prepare(q{
        SELECT
                g.gene_id,
                g.stable_id,
                gan.value,
                t.transcript_id,
                t.stable_id,
                tan.value,
                ta.value,
                sr.name
        FROM
                transcript           t
           JOIN transcript_attrib    ta  USING (transcript_id)
           JOIN gene                 g   ON t.gene_id = g.gene_id
           JOIN gene_attrib          gan ON     g.gene_id = gan.gene_id 
                                    AND gan.attrib_type_id = (
                                        SELECT attrib_type_id
                                        FROM   attrib_type
                                        WHERE  code = 'name'
                                       )
           JOIN transcript_attrib    tan ON     t.transcript_id = tan.transcript_id
                                    AND tan.attrib_type_id = (
                                        SELECT attrib_type_id
                                        FROM   attrib_type
                                        WHERE  code = 'name'
                                       )
           JOIN seq_region           sr  ON g.seq_region_id = sr.seq_region_id
        WHERE
                t.is_current = 1
            AND ta.value LIKE ?
            AND ta.attrib_type_id = (
                                     SELECT attrib_type_id
                                     FROM   attrib_type
                                     WHERE  code = ?
                                    )
        ORDER BY g.stable_id, t.stable_id
    });
    $list_transcripts->execute($attrib_pattern, $attrib_code);

    my $count = 0;
    my $out_format = "%s\t%s\t%s\t%s\t%s\t%s\n";
    printf( $out_format,
        "Chromosome", "Gene name", "stable id",
        "Transcript name", "stable ID",
        "Attribute" ) unless $quiet;
    
    while (my ($gid, $gene_sid, $gene_name, 
           $tid, $transcript_sid, $transcript_name,
           $attrib_value, $seq_region_name) = $list_transcripts->fetchrow()) {
        ++$count;
        printf( $out_format,
                $seq_region_name, $gene_name, $gene_sid,
        $transcript_name, $transcript_sid,
        $attrib_value,
            ) unless $quiet;
    }
    printf "Total: %d\n", $count if $total;

}



__END__

=head1 NAME - list_transcripts_by_attribute.pl

=head1 SYNOPSIS

list_transcripts_by_attribute -dataset <DATASET NAME> -attrib <ATTRIB PATTERN> 
                              [-code <ATTRIB CODE>] [-quiet] [-total]

=head1 DESCRIPTION

Checks for current transcripts having the specified atttribute value 
in an attribute of the specified code.

The attribute value can contain SQL wildcards.
The attribute code defaults to 'remark'.

=head1 EXAMPLE

  list_transcripts_by_attribute.pl --dataset=mouse --attrib='NMD__xception'

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

