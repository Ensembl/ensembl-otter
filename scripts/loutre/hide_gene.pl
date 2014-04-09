#!/usr/bin/env perl

=head1 NAME

hide_gene.pl

=head1 SYNOPSIS

hide_gene.pl

=head1 DESCRIPTION

This script is used to make a gene invisible by clearing the is_current flag 
(and those of its child transcripts and exons).

Must provide a list of gene stable ids.

Here is an example commandline:

./hide_gene.pl -dataset mouse -stable_id OTTMUSG00000016621,OTTMUSG00000001145

=head1 OPTIONS

    -dataset    dataset to use, e.g. human

    -stable_id  list of gene stable ids, comma separated
    -author     author for locking
    -force      proceed without user confirmation
    -help|h     displays this documentation with PERLDOC

=head1 CONTACT

Michael Gray B<email> mg13@sanger.ac.uk

=cut

use strict;
use warnings;

use Sys::Hostname;

use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Otter::Lace::Defaults;
use Bio::Vega::ContigLockBroker;
use Bio::Vega::Author;

{
    my $dataset_name;
    my @ids;
    my $author = $ENV{USERNAME};
    my $force;

    my $usage = sub { exec( 'perldoc', $0 ); };

    Bio::Otter::Lace::Defaults::do_getopt(
        'dataset=s'     => \$dataset_name,
        'stable_id=s'   => \@ids,
        'author=s'      => \$author,
        'force'         => \$force,
        'h|help!'       => $usage,
    )
    or $usage->();

    $usage->() unless ($dataset_name and @ids and $author);

    # Client communicates with otter HTTP server
    my $cl = Bio::Otter::Lace::Defaults::make_Client();
    
    # DataSet interacts directly with an otter database
    my $ds = $cl->get_DataSet_by_name($dataset_name);

    # falls over on human_test, in _attach_DNA_DBAdaptor
    # my $otter_dba = $ds->get_cached_DBAdaptor;

    my $dba = $ds->make_Vega_DBAdaptor;

    my $gene_adaptor = $dba->get_GeneAdaptor;

    my $contig_broker = Bio::Vega::ContigLockBroker->new(-hostname => hostname);
    my $author_obj    = Bio::Vega::Author->new(-name => $author, -email => $author);

    my @sids;
    foreach my $id_list (@ids) { push(@sids , split(/,/x, $id_list)); }
                                 
  GSI: foreach my $id (@sids) {
    
      my $gene = $gene_adaptor->fetch_by_stable_id($id);
      if (!$gene) {
          print STDOUT "Cannot fetch gene stable id $id\n";
          next GSI;
      }

      printf STDOUT ("%s ID:%d Slice:%s <%d-%d:%d> Biotype:%s Source:%s is_current:%s\n",
                     $id, $gene->dbID,
                     $gene->seq_region_name, $gene->seq_region_start, $gene->seq_region_end, $gene->strand,
                     $gene->biotype, $gene->source, $gene->is_current ? 'yes':'no',
          );

# This is meaningless as fetch_latest... sorts by is_current first
# - would need to roll a sort-by-modified-date version to implement properly
#
#       my $latest_gene = $gene_adaptor->fetch_latest_by_stable_id($id);
#       unless ($latest_gene->dbID == $gene->dbID) {
#           printf STDOUT ("Gene is not latest version (latest gene_id %d) - SKIPPING\n");
#           next GSI;
#       }

      if ($force || &proceed() =~ /^y$|^yes$/x ) {

          my $lock_ok = eval { 
              $contig_broker->lock_by_object($gene, $author_obj);
              1;
          };
          unless ($lock_ok) {
              warning("Cannot lock for $id\n$@\n");
              next GSI;
          }

          my $ok = eval {
              $gene_adaptor->hide_db_gene($gene);
              1;
          };

          if ($ok) {
              print STDOUT "gene_stable_id $id is now hidden\n";
          } else {
              warning("Cannot hide $id\n$@\n");
          }

          my $unlock_ok = eval {
              $contig_broker->remove_by_object($gene, $author_obj);
              1;
          };
          unless ($unlock_ok) {
              warning("Cannot unlock for $id\n$@\n");
          }
      }
  } # GSI

    exit 0;
}

sub proceed {
    print STDOUT "make this gene hidden ? [no]";
    my $answer = <STDIN>;chomp $answer;
    $answer ||= 'no';
    return $answer;
}

__END__
