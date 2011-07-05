package Bio::Otter::EnsEMBL2SQL::Compara;

use strict;
use warnings;

use base qw(Bio::Otter::EnsEMBL2SQL::Base);


sub new {
  my ($class,@args) = @_;

  my $self = $class->SUPER::new(@args);

  my ($species_name) = $self->_rearrange(['SPECIES'], @args);  


  if (!defined($species_name)) {
      $self->throw("No species name input");
  }

  $self->species_name($species_name);

  return $self;
}


sub get_dnafrag_region_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump dnafrag_region SQL with no slice");
    }

    my $dnafragstr = $self->get_dnafrag_str;

    if ($dnafragstr  ne "") {
	my $str = $self->query("select * from dnafrag_region where dnafrag_id in $dnafragstr");

	return $str;
    }
    
}

sub get_dnafrag_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump dnafrag SQL with no slice");
    }

    my $dnafragstr = $self->get_dnafrag_str;

    if ($dnafragstr  ne "") {
	my $str = $self->query("select distinct * from dnafrag df, dnafrag_region dfr where dfr.dnafrag_id = dfr.dnafrag_id and dfr.dnafrag_id in $dnafragstr");

	return $str;
    }
}

sub get_synteny_region_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump synteny_region SQL with no slice");
    }

    my $dnafragstr = $self->get_dnafrag_str;

    if ($dnafragstr  ne "") {
	my $str = $self->query("select distinct sr.* from synteny_region sr, dnafrag_region dfr where dfr.synteny_region_id = sr.synteny_region_id and dfr.dnafrag_id in $dnafragstr");

	return $str;
    }
}

sub get_gene_relationship_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump gene_relationship SQL with no slice");
    }

    my $query = "select distinct gr.* from genome_db gdb, gene_relationship gr, gene_relationship_member grm1, gene_relationship_member grm2 where grm1.gene_relationship_id = gr.gene_relationship_id and gr.gene_relationship_id = grm2.gene_relationship_id and grm1.chromosome = '" . $self->chromosome . "' and grm1.chrom_start >= " . $self->start  . " and grm1.chrom_end <= " . $self->end . " and gdb.genome_db_id = grm1.genome_db_id and gdb.name = '" . $self->species_name . "' and grm1.genome_db_id != grm2.genome_db_id";

    my $str = $self->query($query);

    return $str;
}

sub get_gene_relationship_member_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump gene_relationship_member SQL with no slice");
    }

    my $query = "select distinct grm.* from genome_db gdb, gene_relationship gr, gene_relationship_member grm where gr.gene_relationship_id = grm.gene_relationship_id and grm.chromosome = '" . $self->chromosome . "' and grm.chrom_start >= " . $self->start  . " and grm.chrom_end <= " . $self->end . " and gdb.genome_db_id = grm.genome_db_id and gdb.name = '" . $self->species_name . "'";

    my $str = $self->query($query);

    return $str;
}

sub get_genomic_align_block_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump gene_relationship_member SQL with no slice");
    }

    my $dnafragstr = $self->get_dnafrag_str;

    if ($dnafragstr ne "") {
	my $query = "select * from genomic_align_block gab where consensus_dnafrag_id in $dnafragstr";
	
	my $str = $self->query($query);

	return $str;

    }
}

sub get_dnafrag_str {
    my ($self) = @_;

    if (!defined($self->{_dnafrag_str})) {
	my @ids = @{$self->get_dnafrag_ids};

	if (scalar(@ids) == 0) {
	    return;
	}

	my $str = " (";

	foreach my $id (@ids) {
	    $str .= "$id,";
	}

	chop($str);

	$str .= ") ";

	$self->{_dnafrag_str} = $str;
    }

    return $self->{_dnafrag_str};
}

	
sub get_dnafrag_ids {
    my ($self) = @_;

    if (!defined($self->{_dnafrag_ids})) {
	$self->{_dnafrag_ids} = [];

	my $query = "select dfr.dnafrag_id from genome_db gdb, dnafrag_region dfr, dnafrag df where df.dnafrag_id = dfr.dnafrag_id and df.name = '" . $self->chromosome . "' and gdb.genome_db_id = df.genome_db_id and gdb.name = '" . $self->species_name . "'";

	my $sth = $self->prepare($query);
	my $res = $sth->execute;

	my @ids;

	while (my $ref = $sth->fetchrow_arrayref) {
	    push(@ids,$ref->[0]);
	}

	push(@{$self->{_dnafrag_ids}},@ids);
    }

    return $self->{_dnafrag_ids};

}


sub species_name {
    my ($self,$value) = @_;

    if (defined($value)) {
	$self->{_species_name} = $value;
    }

    return $self->{_species_name};
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

