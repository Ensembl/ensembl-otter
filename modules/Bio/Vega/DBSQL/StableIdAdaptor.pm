package Bio::Vega::DBSQL::StableIdAdaptor;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::Author;

use base 'Bio::EnsEMBL::DBSQL::BaseAdaptor';


sub fetch_new_gene_stable_id {
    my ($self) = @_;

    return $self->_fetch_new_by_type('gene', 'G');
}

sub fetch_new_transcript_stable_id {
    my ($self) = @_;

    return $self->_fetch_new_by_type('transcript', 'T');
}

sub fetch_new_exon_stable_id {
    my ($self) = @_;

    return $self->_fetch_new_by_type('exon', 'E');
}

sub fetch_new_translation_stable_id {
    my ($self) = @_;

    return $self->_fetch_new_by_type('translation', 'P');
}


sub _fetch_new_by_type {

  my( $self, $type, $type_prefix ) = @_;

  my $id     = $type . "_id";
  my $poolid = $type . "_pool_id";
  my $table  = $type . "_stable_id_pool";

  my $sql = "insert into $table () values()";
  my $sth = $self->prepare($sql);
  $sth->execute;
  my $num = $sth->{'mysql_insertid'};

  my $meta_container = $self->db->get_MetaContainer();
  my $min_id  = $meta_container->get_stable_id_min();

  if (defined($min_id)) {

    if ($min_id > $num) {
      my $sql = "update $table set $poolid=$min_id where $poolid=$num";
      my $sth = $self->prepare($sql);
      $sth->execute;
      $num = $min_id;

      $sql = "alter table $table auto_increment= " . ($min_id+1);
      $sth = $self->prepare($sql);
      $sth->execute;
    }
  }
  my $prefix = $meta_container->get_primary_prefix() || "OTT";

  my $stableid = $prefix;

  my $species_prefix = $meta_container->get_species_prefix();
  if (defined($species_prefix)) {
    $stableid .= $species_prefix;
  }
  $stableid .= ($type_prefix . sprintf('%011d', $num));

  return $stableid;
}

sub fetch_new_stable_ids_for_Gene {
    my( $self, $gene ) = @_;
    $gene->stable_id($self->fetch_new_gene_stable_id)
      unless $gene->stable_id;

    foreach my $trans (@{$gene->get_all_Transcripts}) {
        $trans->stable_id($self->fetch_new_transcript_stable_id)
          unless $trans->stable_id;
        if (my $translation = $trans->translation) {
            $translation->stable_id($self->fetch_new_translation_stable_id)
              unless $translation->stable_id;
        }
    }

    foreach my $exon (@{$gene->get_all_Exons}) {
        $exon->stable_id($self->fetch_new_exon_stable_id)
          unless $exon->stable_id;
    }

    return;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

