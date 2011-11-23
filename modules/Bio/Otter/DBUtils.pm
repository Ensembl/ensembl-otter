
### Bio::Otter::DBUtils

package Bio::Otter::DBUtils;

use strict;
use warnings;
use base 'Exporter';

# Subroutines to export on request:
our @EXPORT_OK = qw{    
    delete_genes_by_exon_id_list
    };

# This subroutine had its origins in Stephen's delete genes by chromosome script
sub delete_genes_by_exon_id_list {
    my( $dbh, $exon_id_list ) = @_;

    print STDERR "Deleting ", scalar(@$exon_id_list), " exons ... ";
    foreach my $e_id (@$exon_id_list) {
        foreach my $table (qw{ exon supporting_feature exon_transcript exon_stable_id }) {
            $dbh->do(qq{DELETE FROM $table WHERE exon_id = $e_id});
        }
    }
    print STDERR "done\n"; 

    my $transcript_ids = $dbh->selectall_arrayref(qq{
    SELECT t.transcript_id
    FROM transcript t
    LEFT JOIN exon_transcript et
      ON t.transcript_id = et.transcript_id
    WHERE et.transcript_id IS NULL});

    print STDERR "Deleting ", scalar(@$transcript_ids), " distinct transcripts ... "; 
    foreach my $t_id (@$transcript_ids) {
       $dbh->do(qq{delete from transcript where transcript_id = $t_id->[0]}); 
       $dbh->do(qq{delete from transcript_stable_id where transcript_id = $t_id->[0]});
    }
    print STDERR "done\n"; 

    my $translation_ids = $dbh->selectall_arrayref(qq{
    SELECT trans.translation_id
    FROM translation trans
    LEFT JOIN transcript t
      ON trans.translation_id = t.translation_id
    WHERE  t.translation_id IS NULL});

    print STDERR "Deleting ", scalar(@$translation_ids), " distinct translations ... "; 
    foreach my $trans_id (@$translation_ids) {
       $dbh->do(qq{delete from translation where translation_id = $trans_id->[0]}); 
       $dbh->do(qq{delete from translation_stable_id where translation_id = $trans_id->[0]});
       $dbh->do(qq{delete from protein_feature where translation_id = $trans_id->[0]})
    }
    print STDERR "done\n"; 

    my $gene_ids = $dbh->selectall_arrayref(qq{
    SELECT g.gene_id
    FROM gene g
    LEFT JOIN transcript t
      ON g.gene_id = t.gene_id
    WHERE  t.gene_id IS NULL});

    print STDERR "Deleting ", scalar(@$gene_ids), " distinct genes ... "; 
    foreach my $gene_id (@$gene_ids) {
       $dbh->do(qq{delete from gene where gene_id = $gene_id->[0]});
       $dbh->do(qq{delete from gene_stable_id where gene_id = $gene_id->[0]});
       $dbh->do(qq{delete from gene_description where gene_id = $gene_id->[0]});
    }
    print STDERR "done\n"; 

    my $gene_info_ids = $dbh->selectall_arrayref(qq{
    SELECT gi.gene_info_id
    FROM gene_info gi
    LEFT JOIN gene_stable_id gsi
      ON gsi.stable_id = gi.gene_stable_id
      WHERE  gsi.stable_id IS NULL});

    print STDERR "Deleting ", scalar(@$gene_info_ids), " distinct gene_infos ... "; 
    foreach my $gene_info_id(@$gene_info_ids) {
       $dbh->do(qq{delete from gene_info where gene_info_id = $gene_info_id->[0]});
       $dbh->do(qq{delete from gene_name where gene_info_id = $gene_info_id->[0]});
       $dbh->do(qq{delete from gene_remark where gene_info_id = $gene_info_id->[0]});
       $dbh->do(qq{delete from gene_synonym where gene_info_id = $gene_info_id->[0]});
       $dbh->do(qq{delete from current_gene_info where gene_info_id = $gene_info_id->[0]});
    }
    print STDERR "done\n";

    my $trans_info_ids = $dbh->selectall_arrayref(qq{
    SELECT ti.transcript_info_id
    FROM transcript_info ti
    LEFT JOIN transcript_stable_id tsi
      ON  tsi.stable_id = ti.transcript_stable_id
      WHERE  tsi.stable_id IS NULL});

    print STDERR "Deleting ", scalar(@$trans_info_ids), " distinct transcript_infos ... "; 
    foreach my $trans_info_id(@$trans_info_ids) {
       $dbh->do(qq{delete from transcript_info where transcript_info_id = $trans_info_id->[0]});
       $dbh->do(qq{delete from transcript_remark where transcript_info_id = $trans_info_id->[0]});
       $dbh->do(qq{delete from current_transcript_info where transcript_info_id = $trans_info_id->[0]});
       $dbh->do(qq{delete from evidence where transcript_info_id = $trans_info_id->[0]});
    }
    print STDERR "done\n";

    print STDERR "Deleting gene Xrefs ... ";
    my $gene_xref_ids = $dbh->selectall_arrayref(qq{
    SELECT ox.xref_id,
    ox.ensembl_id,
    ox.object_xref_id
    FROM object_xref ox
    LEFT JOIN gene g
      ON  ox.ensembl_id = g.gene_id
      WHERE 
      ox.ensembl_object_type = 'Gene'
      AND  g.gene_id IS NULL});

    foreach my $gene_xref_id (@$gene_xref_ids) {
        $dbh->do(qq{DELETE FROM xref WHERE xref_id = $gene_xref_id->[0]});
        $dbh->do(qq{DELETE FROM object_xref WHERE ensembl_object_type = 'Gene' AND ensembl_id = $gene_xref_id->[1]});
        $dbh->do(qq{DELETE FROM external_synonym WHERE xref_id = $gene_xref_id->[0]});
        $dbh->do(qq{DELETE FROM identity_xref WHERE object_xref_id = $gene_xref_id->[2]});
    }
    print STDERR "done\n";

    print STDERR "Deleting transcript Xrefs ... ";
    my $trans_xref_ids = $dbh->selectall_arrayref(qq{
    SELECT ox.xref_id,
    ox.ensembl_id,
    ox.object_xref_id
    FROM object_xref ox
    LEFT JOIN transcript t
      ON  ox.ensembl_id = t.transcript_id
      WHERE 
      ox.ensembl_object_type = 'Transcript'
      AND  t.transcript_id IS NULL});
    foreach my $trans_xref_id (@$trans_xref_ids) {
        $dbh->do(qq{DELETE FROM xref WHERE xref_id = $trans_xref_id->[0]});
        $dbh->do(qq{DELETE FROM object_xref WHERE ensembl_object_type = 'Transcript' AND ensembl_id = $trans_xref_id->[1]});
        $dbh->do(qq{DELETE FROM external_synonym WHERE xref_id = $trans_xref_id->[0]});
        $dbh->do(qq{DELETE FROM identity_xref WHERE object_xref_id = $trans_xref_id->[2]});
    }
    print STDERR "done\n";

    return;
}

1;

__END__

=head1 NAME - Bio::Otter::DBUtils

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

