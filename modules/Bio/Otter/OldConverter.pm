package Bio::Otter::OldConverter;

use strict;


sub StaticGoldenPath_to_XML {
  my ($contig,$path) = @_;

  my %clones;
  my %versions;

  my $xmlstr;

  $xmlstr .= "  <assembly_type>" . $path . "<\/assembly_type>\n";

  my $chr      = $contig->_chr_name;
  my $chrstart = $contig->_global_start;
  my $chrend   = $contig->_global_end;

  my @contig = $contig->_vmap->each_MapContig;

  @contig = sort {$a->start <=> $b->start} @contig;

  foreach my $p (@contig) {
    $xmlstr .= "<sequence_fragment>\n";

    $xmlstr .= "  <accession>" . $p->contig->id . "<\/id>\n";
    $xmlstr .= "  <chromosome>" . $chr . "<\/chromosome>\n";
    $xmlstr .= "  <assembly_start>" . ($chrstart + $p->start() - 1)
      . "<\/assembly_start>\n";
    $xmlstr .= "  <assembly_end>" . ($chrstart + $p->end() - 1)
      . "<\/assembly_end>\n";
    $xmlstr .= "  <fragment_ori>" . $p->orientation() . "<\/fragment_ori>\n";
    $xmlstr .=
      "  <fragment_offset>" . $p->rawcontig_start() . "<\/fragment_offset>\n";

    $xmlstr .= "<\/sequence_fragment>\n";

  }

  return $xmlstr;

}

sub VirtualContig_to_XML {
  my ($contig, $db, $writeseq ) = @_;

  my $xmlstr = "";

  $xmlstr .= "<otter>\n";
  $xmlstr .= "<sequence_set>\n";

  $xmlstr .= Bio::Otter::OldConverter::StaticGoldenPath_to_XML($contig,$db->static_golden_path_type);

  if (defined($writeseq)) {
    $xmlstr .= "<dna>\n";
    my $seqstr = $contig->seq;
    $seqstr =~ s/(.{72})/  $1\n/g;
    $xmlstr .= $seqstr . "\n";
    $xmlstr .= "</dna>\n";
  }

  $xmlstr .= "</sequence_set>\n";
  $xmlstr .= "</otter>\n";

  return $xmlstr;
}

1;

