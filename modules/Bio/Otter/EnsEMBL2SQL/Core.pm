package Bio::Otter::EnsEMBL2SQL::Core;

use strict;
use warnings;

use base qw(Bio::Otter::EnsEMBL2SQL::Base);


sub new {
  my ($class,@args) = @_;

  my $self = $class->SUPER::new(@args);

  return $self;
}


sub get_chromosome_SQL {
    my ($self) = @_;

    my $chr = $self->chromosome;

    if (!defined($chr)) {
	$self->throw("Must enter chromosome for get_chromosome_SQL call\n");
    }

    my $str = $self->query("select * from chromosome where name = '$chr'");

    return $str;
}

sub get_assembly_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump assembly SQL with no slice");
    }

    my $chrid = $self->slice->get_Chromosome->dbID;

    if (!defined($chrid)) {
	$self->throw("Can't dump assembly SQL with no chromosome dbID");
    }

    my $contigstr = $self->get_raw_contig_string;
    
    if ($contigstr ne "") {
	my $str = $self->query("select * from assembly where contig_id in $contigstr");

	return $str;
    }
}


sub get_contig_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump contig SQL with no slice");
    }

    my $contigstr = $self->get_raw_contig_string;

    if ($contigstr ne "") {
	my $str = $self->query("select * from contig where contig_id in $contigstr");

	return $str;
    }
}

sub get_clone_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump clone SQL with no slice");
    }

    my $contigstr = $self->get_raw_contig_string;

    if ($contigstr ne "") {
	my $str = $self->query("select distinct clone.* from clone,contig where clone.clone_id = contig.clone_id and contig.contig_id in $contigstr");

	return $str;
    }
}

sub get_dna_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump dna SQL with no slice");
    }

    my $contigstr = $self->get_raw_contig_string;
    
    if ($contigstr ne "") {
	my $str = $self->query("select dna.* from dna,contig where dna.dna_id = contig.dna_id and contig.contig_id in $contigstr");
	
	return $str;
    }

}

sub get_dna_align_feature_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump dna align feature SQL with no slice");
    }

    my $contigstr = $self->get_raw_contig_string;

    if ($contigstr ne "") {
	my $str = $self->query("select * from dna_align_feature where contig_id in $contigstr");

	return $str;
    }
}

sub get_protein_align_feature_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump protein align feature SQL with no slice");
    }

    my $contigstr = $self->get_raw_contig_string;

    if ($contigstr ne "") {
	my $str = $self->query("select * from protein_align_feature where contig_id in $contigstr");

	return $str;
    }
}

sub get_simple_feature_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump simple feature SQL with no slice");
    }

    my $contigstr = $self->get_raw_contig_string;

    if ($contigstr ne "") {
	my $str = $self->query("select * from simple_feature where contig_id in $contigstr");

	return $str;
    }
}


sub get_prediction_transcript_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump prediction transcript SQL with no slice");
    }

    my $contigstr = $self->get_raw_contig_string;

    if ($contigstr ne "") {
	my $str = $self->query("select * from prediction_transcript where contig_id in $contigstr");

	return $str;
    }
}

sub get_exon_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump exon SQL with no slice");
    }

    my $contigstr = $self->get_raw_contig_string;

    if ($contigstr ne "") {
	my $str = $self->query("select * from exon where contig_id in $contigstr");

	return $str;
    }
}

sub get_exon_transcript_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump exon_transcript SQL with no slice");
    }

    my $exonstr = $self->get_exon_string;

    if ($exonstr ne "") {
	my $str = $self->query("select distinct * from exon_transcript where exon_id in $exonstr");

	return $str;
    }
}

sub get_transcript_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump transcript SQL with no slice");
    }

    my $exonstr = $self->get_exon_string;

    if ($exonstr ne "") {
	my $str = $self->query("select distinct transcript.* from exon_transcript et, transcript where et.transcript_id  = transcript.transcript_id and et.exon_id in $exonstr");
    
	return $str;
    }

}

sub get_translation_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump translation SQL with no slice");
    }

    my $exonstr = $self->get_exon_string;

    if ($exonstr ne "") {
	my $str = $self->query("select distinct translation.* from exon_transcript et, transcript t,translation where t.translation_id = translation.translation_id and et.transcript_id  = t.transcript_id and et.exon_id in $exonstr");

	return $str;
    }
}

sub get_gene_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump gene SQL with no slice");
    }

    my $exonstr = $self->get_exon_string;

    if ($exonstr ne "") {
	my $str = $self->query("select distinct gene.* from exon_transcript et, transcript t, gene where gene.gene_id = t.gene_id and et.transcript_id  = t.transcript_id and et.exon_id in $exonstr");

	return $str;
    }
}

sub get_gene_description_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump gene description SQL with no slice");
    }

    my $exonstr = $self->get_exon_string;

    if ($exonstr ne "") {
	my $str = $self->query("select distinct gd.* from gene_description gd,exon_transcript et, transcript t, gene where gd.gene_id = gene.gene_id and gene.gene_id = t.gene_id and et.transcript_id  = t.transcript_id and et.exon_id in $exonstr");

	return $str;
    }
}

sub get_gene_stable_id_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump gene stable id SQL with no slice");
    }

    my $exonstr = $self->get_exon_string;

    if ($exonstr ne "") {
	my $str = $self->query("select distinct gsi.* from gene_stable_id gsi,exon_transcript et, transcript t, gene where gsi.gene_id = gene.gene_id and gene.gene_id = t.gene_id and et.transcript_id  = t.transcript_id and et.exon_id in $exonstr");

	return $str;
    }
}
sub get_transcript_stable_id_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump transcript stable id SQL with no slice");
    }

    my $exonstr = $self->get_exon_string;

    if ($exonstr ne "") {
	my $str = $self->query("select distinct tsi.* from transcript_stable_id tsi,exon_transcript et where tsi.transcript_id = et.transcript_id and et.exon_id in $exonstr");

	return $str;

    }
}
sub get_exon_stable_id_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump exon stable id SQL with no slice");
    }

    my $exonstr = $self->get_exon_string;

    if ($exonstr ne "") {
	my $str = $self->query("select distinct * from exon_stable_id esi where esi.exon_id in $exonstr");

	return $str;
    }
}
sub get_translation_stable_id_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump translation stable id SQL with no slice");
    }

    my $exonstr = $self->get_exon_string;

    if ($exonstr ne "") {
	my $str = $self->query("select distinct tsi.* from translation_stable_id tsi,exon_transcript et, transcript t where tsi.translation_id = t.translation_id and t.transcript_id = et.transcript_id and et.exon_id in $exonstr");


	return $str;
    }
}

sub get_protein_feature_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump protein_feature SQL with no slice");
    }

    my $exonstr = $self->get_exon_string;

    if ($exonstr ne "") {
	my $str = $self->query("select distinct pf.* from exon_transcript et, transcript t,protein_feature pf where pf.translation_id = t.translation_id and t.transcript_id = et.transcript_id and et.exon_id in $exonstr");


	return $str;
    }
}

sub get_repeat_feature_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump repeat_feature SQL with no slice");
    }

    my $contigstr = $self->get_raw_contig_string;

    if ($contigstr ne "") {
	my $str = $self->query("select * from repeat_feature where contig_id in $contigstr");

	return $str;
    }
}

sub get_repeat_consensus_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump repeat_consensus SQL with no slice");
    }

    my $contigstr = $self->get_raw_contig_string;

    if ($contigstr ne "") {
	my $str = $self->query("select distinct rc.* from repeat_consensus rc,repeat_feature rf where rc.repeat_consensus_id = rf.repeat_consensus_id and rf.contig_id in $contigstr");

	return $str;
    }
}


sub get_supporting_feature_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump supporting_feature SQL with no slice");
    }

    my $exonstr = $self->get_exon_string;

    if ($exonstr ne "") {
	my $str = $self->query("select * from supporting_feature where exon_id in $exonstr");

	return $str;
    }
}

sub get_stable_id_event_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump stable_id_event SQL with no slice");
    }

    my $exonstr = $self->get_exon_string;

    if ($exonstr ne "") {
	my $str = $self->query("select * from supporting_feature where exon_id in $exonstr");

	return $str;
    }
}

sub get_stable_id_event_SQL {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump stable_id_event SQL with no slice");
    }

    my $exonstr = $self->get_exon_string;

    if ($exonstr ne "") {
	my $str = $self->query("select * from supporting_feature where exon_id in $exonstr");

	return $str;
    }
}

sub get_exon_dbIDs {
    my ($self) = @_;

    
    if (!defined($self->{_exon_dbIDs})) {
	$self->{_exon_dbIDs} = [];

	my $contigstr = $self->get_raw_contig_string;

	if ($contigstr ne "") {
	    my $query = "select exon_id from exon where contig_id in $contigstr";

	    my $sth = $self->prepare($query);

	    my $res = $sth->execute;

	    my @exonids;

	    while (my $ref = $sth->fetchrow_arrayref) {
		push(@exonids,$ref->[0]);
	    }

	    $self->{_exon_dbIDs} = \@exonids;
	}
    }

    return $self->{_exon_dbIDs};
}

sub get_exon_string {
    my ($self) = @_;

    my @exonids = @{$self->get_exon_dbIDs};

    if (scalar(@exonids) == 0) {
	return;
    }

    my $str = " (";

    foreach my $exon (@exonids) {
	$str .= $exon . ",";
    }
    chop($str);
    
    $str .= ") ";

    return $str;
}

sub get_raw_contig_string {
    my ($self) = @_;

    if (!defined($self->{_raw_contig_string})) {
	my @ids = @{$self->get_raw_contig_dbIDs};


	if (scalar(@ids) == 0) {
	    return;
	}

	my $str = " (";

	foreach my $id (@ids) {
	    $str .= "$id,";
	}

	chop($str);

	$str .= ") ";

	$self->{_raw_contig_string} = $str;

    }

    return $self->{_raw_contig_string};
}


sub get_raw_contig_dbIDs {
    my ($self) = @_;


    if (!defined($self->{_raw_contig_dbIDs})) {
	my @contigids;

	foreach my $contig (@{$self->get_contigs}) {
	    push(@contigids,$contig->dbID);
	}
	$self->{_raw_contig_dbIDs} = \@contigids;
    }

    return $self->{_raw_contig_dbIDs};

}

sub get_contigs {
    my ($self) = @_;

    if (!defined($self->slice)) {
	$self->throw("Can't dump assembly SQL with no slice");
    }

    if (!defined($self->{_raw_contigs})) {

	my @path = @{$self->slice->get_tiling_path};

	my @contigs;

	foreach my $path (@path) {
	    push(@contigs,$path->component_Seq);
	}

	$self->{_raw_contigs} = \@contigs;
    }
    
    return $self->{_raw_contigs};
}

sub get_object_xref_SQL {
    my ($self) = @_;
  
    if (!defined($self->slice)) {
	$self->throw("Can't dump object_xref SQL with no slice");
    }

    my $xref_id_string = $self->get_xref_id_string;

    if ($xref_id_string ne "") {
	my $str = $self->query("select * from object_xref where xref_id in $xref_id_string");

	return $str;
    }

}

sub get_xref_SQL {
    my ($self) = @_;
  
    if (!defined($self->slice)) {
	$self->throw("Can't dump xref SQL with no slice");
    }

    my $xref_id_string = $self->get_xref_id_string;

    if (defined($xref_id_string) && $xref_id_string ne "") {
	my $str = $self->query("select * from xref where xref_id in $xref_id_string");

	return $str;
    }

}

sub get_identity_xref_SQL {
    my ($self) = @_;
  
    if (!defined($self->slice)) {
	$self->throw("Can't dump identity_xref SQL with no slice");
    }

    my $xref_id_string = $self->get_xref_id_string;
    
    if ($xref_id_string ne "") {
	my $str = $self->query("select * from identity_xref ix,object_xref ox where ix.object_xref_id = ox.object_xref_id and ox.xref_id in $xref_id_string");

	return $str;
    }

}

sub get_external_synonym_SQL {
    my ($self) = @_;
  
    if (!defined($self->slice)) {
	$self->throw("Can't dump external_synonym SQL with no slice");
    }

    my $xref_id_string = $self->get_xref_id_string;

    if ($xref_id_string ne "") {
	my $str = $self->query("select * from external_synonym where xref_id in $xref_id_string");

	return $str;
    }

}

sub get_xref_id_string {
    my ($self) = @_;

    if (!defined($self->{_xref_id_string})) {

	my $str = " (";

	my @ids = @{$self->get_xref_ids};

	if (scalar(@ids) == 0){ 
	    return;
	}


	foreach my $id (@ids) {
	    $str .= $id . ",";
	}
	chop($str);

	$str .= ") ";
    
	$self->{_xref_id_string} = $str;

    } 
    return $self->{_xref_id_string};
}


sub get_xref_ids {
    my ($self) = @_;

    if (!defined($self->{_xref_ids})) {
	$self->{_xref_ids} = [];

	my $exonstr = $self->get_exon_string;

	if ($exonstr ne "") {
	    my $query = "select object_xref.xref_id from object_xref,exon_transcript et, transcript t where t.translation_id = object_xref.ensembl_id and et.transcript_id  = t.transcript_id and et.exon_id in $exonstr";


	    my $sth = $self->prepare($query);

	    my $res = $sth->execute;

	    my @ids;
	
	    while (my $ref = $sth->fetchrow_arrayref) {
		push(@ids,$ref->[0]);
	    }

	    $self->{_xref_ids} = \@ids;
	}
    }


    return $self->{_xref_ids};

}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

