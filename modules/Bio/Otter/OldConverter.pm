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
    $xmlstr .= "<sequencefragment>\n";

    $xmlstr .= "  <id>" . $p->contig->id . "<\/id>\n";
    $xmlstr .= "  <chromosome>" . $chr . "<\/chromosome>\n";
    $xmlstr .= "  <assemblystart>" . ($chrstart + $p->start() - 1)
      . "<\/assemblystart>\n";
    $xmlstr .= "  <assemblyend>" . ($chrstart + $p->end() - 1)
      . "<\/assemblyend>\n";
    $xmlstr .= "  <assemblyori>" . $p->orientation() . "<\/assemblyori>\n";
    $xmlstr .=
      "  <assemblyoffset>" . $p->rawcontig_start() . "<\/assemblyoffset>\n";

    $xmlstr .= "<\/sequencefragment>\n";

  }

  return $xmlstr;

}

sub VirtualContig_to_XML {
  my ($contig, $db, $writeseq ) = @_;

  my $xmlstr = "";

  $xmlstr .= "<otter>\n";
  $xmlstr .= "<sequenceset>\n";

  $xmlstr .= Bio::Otter::OldConverter::StaticGoldenPath_to_XML($contig,$db->static_golden_path_type);

  if (defined($writeseq)) {
    $xmlstr .= "<dna>\n";
    my $seqstr = $contig->seq;
    $seqstr =~ s/(.{72})/  $1\n/g;
    $xmlstr .= $seqstr . "\n";
    $xmlstr .= "</dna>\n";
  }

  $xmlstr .= "</sequenceset>\n";
  $xmlstr .= "</otter>\n";

  return $xmlstr;
}

1;

