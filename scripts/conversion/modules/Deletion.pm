package Deletion;

use strict;
use warnings;


=head2 delete_exons

  Arg[1]      : Bio::EnsEMBL::Utils::ConversionSupport
  Arg[2]      : DBI::db
  Example     : $support->delete_exons)$dbh);
  Description : Delete exons (and associated supporting evidence) that don't
                belong to a transcript anymore.
  Return type : none
  Exceptions  : none
  Caller      : internal

=cut

sub delete_exons {
	my ($support,$dbh) = @_;
    # delete exons and supporting features
	$support->log_stamped("Deleting exon_transcript entries...\n");
	my $sql = qq(
        DELETE QUICK IGNORE
                et
        FROM
                exon_transcript et
        LEFT JOIN
                transcript t on et.transcript_id = t.transcript_id
        WHERE   t.transcript_id is null
    );

	my $num = $dbh->do($sql);
    $support->log_stamped("Done deleting $num records.\n\n");

    $support->log_stamped("Deleting exons...\n");
    $sql = qq(
        DELETE QUICK IGNORE
                esi,
                e
        FROM
                exon_stable_id esi,
                exon e
        LEFT JOIN
                exon_transcript et ON e.exon_id = et.exon_id
        WHERE   e.exon_id = esi.exon_id
        AND     et.exon_id IS NULL
    );
    $num = $dbh->do($sql);
    $support->log_stamped("Done deleting $num records.\n\n");

	$support->log_stamped("Deleting supporting features...\n");
    $sql = qq(
        DELETE QUICK IGNORE
                sf
        FROM
                supporting_feature sf
        LEFT JOIN
                exon e ON sf.exon_id = e.exon_id
        WHERE   e.exon_id IS NULL
    );
    $num = $dbh->do($sql);
    $support->log_stamped("Done deleting $num records.\n\n");

	$support->log_stamped("Deleting transcript_supporting features...\n");
    $sql = qq(
        DELETE QUICK IGNORE
                tsf
        FROM
                transcript_supporting_feature tsf
        LEFT JOIN
                transcript t ON tsf.transcript_id = t.transcript_id
        WHERE   t.transcript_id IS NULL
    );
    $num = $dbh->do($sql);
    $support->log_stamped("Done deleting $num records.\n\n");
}

=head2 delete_xrefs

  Arg[1]      : Bio::EnsEMBL::Utils::ConversionSupport
  Arg[2]      : DBI::db
  Example     : $support->delete_xrefs($dbh);
  Description : Delete xrefs no longer attached to an Ensembl object
  Return type : none
  Exceptions  : none
  Caller      : internal

=cut

sub delete_xrefs {
	my ($support,$dbh) = @_;
    # delete xrefs
    $support->log_stamped("Deleting xrefs...\n");
    $support->log_stamped("Determining which xrefs to delete...\n", 1);

    my ($sql, $num, @xrefs);

    # orphan gene xrefs to delete
    $sql = qq(
        SELECT
                ox.xref_id,
                ox.object_xref_id
        FROM
                object_xref ox
        LEFT JOIN
                gene g ON ox.ensembl_id = g.gene_id
        WHERE   ox.ensembl_object_type = 'Gene'
        AND     g.gene_id IS NULL
    );
    my @gene_xrefs = @{ $dbh->selectall_arrayref($sql) || [] };
    my $gene_xref_string = join(",", map { $_->[0] } @gene_xrefs) || 0;

    # since xrefs can be shared between genes, the above list of xrefs might
    # also contain entries that are not orphans, so we have to filter them out
    $sql = qq(
        SELECT
                x.xref_id
        FROM
                xref x,
                object_xref ox,
                gene g
        WHERE   g.gene_id = ox.ensembl_id
        AND     ox.ensembl_object_type = 'Gene'
        AND     ox.xref_id = x.xref_id
        AND     x.xref_id IN ($gene_xref_string)
    );
    my @keep_gene_xrefs = @{ $dbh->selectall_arrayref($sql) || [] };
    my %seen_genes;
    map { $seen_genes{$_->[0] } = 1 } @keep_gene_xrefs;

	#filter out additional xrefs to keep because some human xrefs can be used as
    #display_xrefs and as xrefs

	$sql = qq(
      SELECT
		        x.xref_id
        FROM
                xref x,
                gene g
        WHERE   x.xref_id = g.display_xref_id
    );
	my @keep_gene_display_xrefs = @{ $dbh->selectall_arrayref($sql) || [] };	
	my %seen_display_xrefs;
	map { $seen_display_xrefs{$_->[0] } = 1 } @keep_gene_display_xrefs;

    foreach my $gene_xref (@gene_xrefs) {
        push(@xrefs, $gene_xref) unless ( $seen_genes{$gene_xref->[0]} || $seen_display_xrefs{$gene_xref->[0]} );
    }

    # orphan transcript xrefs to delete
    $sql = qq(
        SELECT
                ox.xref_id,
                ox.object_xref_id
        FROM
                object_xref ox
        LEFT JOIN
                transcript t ON ox.ensembl_id = t.transcript_id
        WHERE   ox.ensembl_object_type = 'Transcript'
        AND     t.transcript_id IS NULL
    );
    my @transcript_xrefs = @{ $dbh->selectall_arrayref($sql) || [] };
    my $transcript_xref_string = join(",", map { $_->[0] } @transcript_xrefs) || 0;

    # filter (see genes for explanation)
    $sql = qq(
        SELECT
                x.xref_id
        FROM
                xref x,
                object_xref ox,
                transcript t
        WHERE   t.transcript_id = ox.ensembl_id
        AND     ox.ensembl_object_type = 'Transcript'
        AND     ox.xref_id = x.xref_id
        AND     x.xref_id IN ($transcript_xref_string)
    );
    my @keep_transcript_xrefs = @{ $dbh->selectall_arrayref($sql) || [] };
    my %seen_transcripts;
    map { $seen_transcripts{$_->[0] } = 1 } @keep_transcript_xrefs;
    foreach my $transcript_xref (@transcript_xrefs) {
        push(@xrefs, $transcript_xref) unless ($seen_transcripts{$transcript_xref->[0]});
    }

    # translations xrefs
    $sql = qq(
        SELECT
                ox.xref_id,
                ox.object_xref_id
        FROM
                object_xref ox
        LEFT JOIN
                translation tl ON ox.ensembl_id = tl.translation_id
        WHERE   ox.ensembl_object_type = 'Translation'
        AND     tl.translation_id IS NULL
    );
    my @translation_xrefs = @{ $dbh->selectall_arrayref($sql) || [] };
    my $translation_xref_string = join(",", map { $_->[0] } @translation_xrefs) || 0;

    # filter (see genes for explanation)
    $sql = qq(
        SELECT
                x.xref_id
        FROM
                xref x,
                object_xref ox,
                translation tl
        WHERE   tl.translation_id = ox.ensembl_id
        AND     ox.ensembl_object_type = 'Translation'
        AND     ox.xref_id = x.xref_id
        AND     x.xref_id IN ($translation_xref_string)
    );
    my @keep_translation_xrefs = @{ $dbh->selectall_arrayref($sql) || [] };
    my %seen_translations;
    map { $seen_translations{$_->[0] } = 1 } @keep_translation_xrefs;
    foreach my $translation_xref (@translation_xrefs) {
        push(@xrefs, $translation_xref) unless ($seen_translations{$translation_xref->[0]});
    }

    my $xref_string = join(",", map { $_->[0] } @xrefs) || 0;

    my $object_xref_string = join(",", map { $_->[1] } @gene_xrefs, @transcript_xrefs, @translation_xrefs) || 0;

    # delete from xref
    $support->log_stamped("Deleting from xref...\n", 1);
    $sql = qq(DELETE FROM xref WHERE xref_id IN ($xref_string));
    $num = $dbh->do($sql);
    $support->log_stamped("Done deleting $num entries.\n", 1);

    # delete from object_xref
    $support->log_stamped("Deleting from object_xref...\n", 1);
    $sql = qq(DELETE FROM object_xref WHERE object_xref_id IN ($object_xref_string));
    $num = $dbh->do($sql);
    $support->log_stamped("Done deleting $num entries.\n", 1);

    # delete from identity_xref
    $support->log_stamped("Deleting from identity_xref...\n", 1);
    $sql = qq(DELETE FROM identity_xref WHERE object_xref_id IN ($object_xref_string));
    $num = $dbh->do($sql);
    $support->log_stamped("Done deleting $num entries.\n", 1);

    # delete from external_synonym
    $support->log_stamped("Deleting from external_synonym...\n", 1);
    $sql = qq(DELETE FROM external_synonym WHERE xref_id IN ($xref_string));
    $num = $dbh->do($sql);
    $support->log_stamped("Done deleting $num entries.\n", 1);

    $support->log_stamped("Done.\n\n");
}

=head2 optimize_tables

  Arg[1]      : Bio::EnsEMBL::Utils::ConversionSupport
  Arg[2]      : DBI::db
  Example     : $support->optimize_tables(dbh);
  Description : Optimises database tables.
  Return type : none
  Exceptions  : none
  Caller      : internal

=cut

sub optimize_tables {
	my ($support,$dbh) = @_;
    # optimize tables
    $support->log_stamped("Optimizing tables...\n");
    my @tables = qw(
        gene
        gene_stable_id
        gene_attrib
		gene_author
        transcript
        transcript_stable_id
        transcript_author
        transcript_attrib
        transcript_supporting_feature
        evidence
        translation
        translation_attrib
        translation_stable_id
        protein_feature
        exon
        exon_stable_id
        exon_transcript
        supporting_feature
        xref
        object_xref
        identity_xref
        external_synonym
    );
    foreach my $table (@tables) {
        $support->log_stamped("$table...\n", 1);
        $dbh->do(qq(OPTIMIZE TABLE $table));
    }
    $support->log_stamped("Done.\n\n");
}

1;
