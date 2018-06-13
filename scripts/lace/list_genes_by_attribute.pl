#!/usr/bin/env perl
# Copyright [2018] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


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

    my $list_genes = $otter_dba->dbc->prepare(q{
        SELECT
                g.gene_id,
                gsi.stable_id,
                gan.value,
                ga.value,
                sr.name
        FROM
                gene                 g
           JOIN gene_attrib          ga  USING (gene_id)
           JOIN gene_stable_id       gsi ON g.gene_id = gsi.gene_id
           JOIN gene_attrib          gan ON     g.gene_id = gan.gene_id 
                                    AND gan.attrib_type_id = (
                                        SELECT attrib_type_id
                                        FROM   attrib_type
                                        WHERE  code = 'name'
                                       )
           JOIN seq_region           sr  ON g.seq_region_id = sr.seq_region_id
        WHERE
                g.is_current = 1
            AND ga.value LIKE ?
            AND ga.attrib_type_id = (
                                     SELECT attrib_type_id
                                     FROM   attrib_type
                                     WHERE  code = ?
                                    )
        ORDER BY gsi.stable_id
    });
    $list_genes->execute($attrib_pattern, $attrib_code);

    my $count = 0;
    my $out_format = "%s\t%s\t%s\t%s\n";
    printf( $out_format,
        "Chromosome", "Gene name", "stable id",
        "Attribute" ) unless $quiet;
    
    while (my ($gid, $gene_sid, $gene_name, 
           $attrib_value, $seq_region_name) = $list_genes->fetchrow()) {
        ++$count;
        printf( $out_format,
                $seq_region_name, $gene_name, $gene_sid,
        $attrib_value,
            ) unless $quiet;
    }
    printf "Total: %d\n", $count if $total;

}



__END__

=head1 NAME - list_genes_by_attribute.pl

=head1 SYNOPSIS

list_genes_by_attribute -dataset <DATASET NAME> -attrib <ATTRIB PATTERN> 
                              [-code <ATTRIB CODE>] [-quiet] [-total]

=head1 DESCRIPTION

Checks for current genes having the specified atttribute value 
in an attribute of the specified code.

The attribute value can contain SQL wildcards.
The attribute code defaults to 'remark'.

=head1 EXAMPLE

  list_genes_by_attribute.pl --dataset=mouse --attrib='frag%loc%'

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

