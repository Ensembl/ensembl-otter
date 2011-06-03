#!/usr/bin/env perl

=head1 NAME

fix_gene_version.pl

=head1 SYNOPSIS

fix_gene_version.pl

=head1 DESCRIPTION

This script fix the versioning errors of the gene/transcript/exon/translation in the database which was caused by some bugs in the saving code.
It loops through the list of gene SID provided or the full list of gene SID fetched from the database and work out the true versioning history for each object.
It also remove identical genes wrongly saved.

here is an example commandline

./fix_gene_version.pl
-host otterlive
-port 3324
-dbname loutre_human
-user pipuser
-pass *****
-write
-stable_id OTTHUMG00000000399,OTTHUMG00000000400,...

=head1 OPTIONS

    -host (default:otterlive)   host name of the database with missing contig dna
    -dbname (no default)  For RDBs, what database to connect to
    -user (check the ~/.netrc file)  For RDBs, what username to connect as
    -pass (check the ~/.netrc file)  For RDBs, what password to use
    -port (check the ~/.netrc file)   For RDBs, what port to use

    -verbose    make the script verbose
    -write      write the changes in the database
    -stable_id  comma separated list of gene stable id
    -help|h     displays this documentation with PERLDOC

=head1 CONTACT

Mustapha Larbaoui B<email> ml6@sanger.ac.uk

=cut

use strict;
use warnings;
use Sys::Hostname;
use Net::Netrc;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::DBSQL::DBAdaptor;
use Bio::Vega::ContigLockBroker;
use Bio::Vega::Utils::Comparator qw(compare);
use Bio::Otter::Lace::Defaults;
use Getopt::Long;
use HTTP::Date;

my $dbname;
my $host = 'otterlive';
my $port;
my $user;
my $pass;
my @ids;
my $verbose = 0;
my $write   = 0;
my $cl      = Bio::Otter::Lace::Defaults::make_Client();
my $author  = $cl->author;
my $email   = $cl->email;
my $usage   = sub { exec( 'perldoc', $0 ); };

GetOptions(
			'host=s'      => \$host,
			'port=n'      => \$port,
			'dbname=s'    => \$dbname,
			'user=s'      => \$user,
			'pass=s'      => \$pass,
			'verbose!'    => \$verbose,
			'write!'      => \$write,
			'stable_id=s' => \@ids,
			'h|help!'     => $usage,
  )
  or $usage->();

# Reading the DB connexion parameters from ~/.netrc
my $ref = Net::Netrc->lookup($host);
if ( !$ref ) {
	print STDERR "No entry found in ~/.netrc for host $host\n";
	next;
}
$user = $ref->login;
$pass = $ref->password;
$port = $ref->account;

my @sids;
map( push( @sids, split( /,/, $_ ) ), @ids );

# Extend the Bio::Vega objects to keep track of the true version

sub Bio::Vega::Gene::true_version {
	my $self = shift;
	$self->{'true_version'} = shift if (@_);
	return ( $self->{'true_version'} || 1 );
}

sub Bio::Vega::Transcript::true_version {
	my $self = shift;
	$self->{'true_version'} = shift if (@_);
	return ( $self->{'true_version'} || 1 );
}

sub Bio::Vega::Translation::true_version {
	my $self = shift;
	$self->{'true_version'} = shift if (@_);
	return ( $self->{'true_version'} || 1 );
}

sub Bio::Vega::Exon::true_version {
	my $self = shift;
	$self->{'true_version'} = shift if (@_);
	return ( $self->{'true_version'} || 1 );
}
my $dba = Bio::Vega::DBSQL::DBAdaptor->new(
											-dbname => $dbname,
											-host   => $host,
											-port   => $port,
											-user   => $user,
											-pass   => $pass,
);

my $ga = $dba->get_GeneAdaptor();
my $counter;
my $ref_gene_hash;
my @sql;

my $list = @sids ?  \@sids : $ga->list_stable_ids;

GSI: foreach my $si ( @$list ) {
	print STDOUT "Processing GSI $si\n";
	my $gene_slice = $ga->fetch_latest_by_stable_id($si)->feature_Slice;
	my ( $cb, $author_obj );
	if ( $write ) {
		eval {
			$cb = Bio::Vega::ContigLockBroker->new( -hostname => hostname );
			$author_obj =
			  Bio::Vega::Author->new( -name => $author, -email => $email );
			printf STDOUT "Locking $si slice %s <%d-%d>\n",
			  $gene_slice->seq_region_name, $gene_slice->start,
			  $gene_slice->end if $verbose;
			$cb->lock_clones_by_slice( [$gene_slice], $author_obj, $dba );
		};
		if ($@) {
			warning("Problem locking $si slice with author name $author\n$@\n");
			next GSI;
		}
	}
	$dba->dbc->db_handle->begin_work;
	eval {
		my $gene_versions = $ga->fetch_all_versions_by_stable_id($si);
		my $ref_gene      = $ga->reincarnate_gene( shift @$gene_versions );
		my $seq_hash      = {};
		$counter = 1;
		@sql     = ();
		&print_info( $ref_gene, $seq_hash ) if $verbose;
		&populate_hash_ref($ref_gene);
	  G_VERSION: foreach my $gene (@$gene_versions) {
			$gene = $ga->reincarnate_gene($gene);
			my ( $any_changes, $seq_changes ) =
			  &transcripts_diff( $gene, time );
			$any_changes ||= compare( $ref_gene, $gene );
			$gene->true_version( $ref_gene->true_version + $seq_changes );
			print STDOUT
			  "any_changes [$any_changes] seq_changes [$seq_changes]\n" if $verbose;
			if ( !( $any_changes || $seq_changes ) ) {
				printf STDOUT "DELETE GENE: %d %s.%s (%s)\n", $gene->dbID,
				  $gene->stable_id, $gene->version, $gene->true_version;
				$ga->remove($gene) if ($write);
				if ( $gene->is_current ) {
					printf STDOUT
					  "SET OLD GENE CURRENT: %d %s.%s (is_current:%s)\n",
					  $ref_gene->dbID, $ref_gene->stable_id, $ref_gene->version,
					  $ref_gene->is_current;
					$ga->resurrect($ref_gene) if ($write);
				}
				next G_VERSION;
			}
			if ( $gene->version ne $gene->true_version ) {
				printf STDOUT "GENE_VERSION_UPDATE: %d %s.%s (%s)\n",
				  $gene->dbID, $gene->stable_id, $gene->version,
				  $gene->true_version;
				push @sql,
				  &update_sql( 'gene', $gene->dbID, $gene->stable_id,
							   $gene->version, $gene->true_version );
			}
			&print_info( $gene, $seq_hash ) if $verbose;
			&populate_hash_ref($gene);
			$ref_gene = $gene;
		}

		# Update the versions here
		foreach my $sql (@sql) {
			if ($write) {
				$dba->dbc->do($sql);
			}
			else {
				print STDOUT $sql . "\n";
			}
		}
	};
	if ($@) {
		$dba->dbc->db_handle->rollback;
		print STDERR "Have seen an error for $si [$@]\n";
	}
	else {
		$dba->dbc->db_handle->commit;
	}
	if ( $write ) {
		eval {
			printf STDOUT "Unlocking $si slice %s <%d-%d>\n",
			  $gene_slice->seq_region_name, $gene_slice->start,
			  $gene_slice->end if $verbose;
			$cb->remove_by_slice( [$gene_slice], $author_obj, $dba );
		};
		if ($@) {
			warning(     "Cannot remove locks from $si slice with author name $author\n$@\n"
			);
		}
	}
}


# Start the methods here

sub update_sql {
	my ( $type, $dbID, $stable_id, $old_version, $new_version ) = @_;
	return qq{
UPDATE ${type}_stable_id
SET version = $new_version
where ${type}_id = $dbID
AND stable_id = '$stable_id'
AND version = $old_version ;};
}

sub populate_hash_ref {
	my ($gene) = @_;
	$ref_gene_hash = {};
	$ref_gene_hash->{ $gene->stable_id } = $gene;

	foreach my $transcript ( @{ $gene->get_all_Transcripts } ) {
		$ref_gene_hash->{ $transcript->stable_id } = $transcript;

		foreach my $exon ( @{ $transcript->get_all_Exons } ) {
			$ref_gene_hash->{ $exon->stable_id } = $exon;

		}
		if ( $transcript->translation ) {
			$ref_gene_hash->{ $transcript->translation->stable_id } =
			  $transcript->translation;
		}
	}
}

sub print_info {
	my ( $gene, $seq_hash ) = @_;
	printf STDOUT "%s\t%d\t%s.%d\t'%s'\t'%s'\t%s\n",
	  $gene->slice->seq_region_name, $gene->dbID, $gene->stable_id,
	  $gene->version, time2str( $gene->created_date ),
	  time2str( $gene->modified_date ), $gene->gene_author->name;
	foreach my $transcript ( @{ $gene->get_all_Transcripts } ) {
		printf STDOUT "\t%d\t%s.%d\t%s\t'%s'\t'%s'\n", $transcript->dbID,
		  $transcript->stable_id, $transcript->version, $transcript->biotype,
		  time2str( $transcript->created_date ),
		  time2str( $transcript->modified_date );
		if ( $transcript->translation ) {
			my $translation = $transcript->translation;
			printf STDOUT "\t%s.%d\t'%s'\t'%s'\t%s\n", $translation->stable_id,
			  $translation->version, time2str( $translation->created_date ),
			  time2str( $translation->modified_date ),
			  &get_seq_id( $translation->seq, $seq_hash );
		}
		foreach my $exon (
			sort {
				     $a->start <=> $b->start
				  || $a->end <=> $b->end
			} @{ $transcript->get_all_Exons }
		  )
		{
			printf STDOUT "\t\t%s.%d\t%d-%d:%d:%d\t'%s'\t'%s'\t%s\n",
			  $exon->stable_id, $exon->version, $exon->start, $exon->end,
			  $exon->phase, $exon->end_phase, time2str( $exon->created_date ),
			  time2str( $exon->modified_date ),
			  &get_seq_id( $exon->seq->seq, $seq_hash );
		}
	}
}

sub get_seq_id {
	my ( $seq, $seq_hash ) = @_;
	$seq = lc $seq;
	if ( !$seq_hash->{$seq} ) {
		$seq_hash->{$seq} = $counter;
		$counter++;
	}
	return $seq_hash->{$seq};
}
my $time;

sub current_time {
	my ($t) = @_;
	if ( defined $t ) {
		$time = $t;
	}
	return $time;
}

# the methods below are from Bio::Vega::AnnotationBroker

sub transcripts_diff {
	my ( $gene, $time ) = @_;
	current_time($time);
	my $transcripts_any_changes = 0;
	my $transcripts_seq_changes = 0;
	my $shared_exons            = {};
	foreach my $tran ( @{ $gene->get_all_Transcripts } ) {
		## check if exons are new or old
		#  and if old whether they have changed or not:
		#  and if changed, was there any change in sequence?
		my ( $exons_any_changes, $exons_seq_changes ) =
		  exons_diff( $tran, $shared_exons );

	 # has to be run exactly once, so not suitable as a part of '||' expression:
		my ( $translation_any_changes, $translation_seq_changes ) =
		  translations_diff($tran);
		my $this_transcript_any_changes = 0;
		my $this_transcript_seq_changes = $exons_seq_changes
		  || $translation_seq_changes;
		if ( my $db_transcript = $ref_gene_hash->{ $tran->stable_id } )
		{    # the transcript is not NEW

			# this is the check of 'significant change in structure':
			$this_transcript_any_changes = $exons_any_changes
			  || $translation_any_changes
			  || compare( $db_transcript, $tran );

			if ($this_transcript_any_changes) {

				$tran->true_version( $db_transcript->true_version +
									 $this_transcript_seq_changes );
			}
			else {
				$tran->true_version( $db_transcript->true_version );
			}
		}
		else {    # no db_transcript means the transcript is NEW
			$this_transcript_any_changes =
			  1;    # because it should have its' own new exons
			$this_transcript_seq_changes = 1;    # for the same reason
		}
		if ( $tran->version ne $tran->true_version ) {
			printf STDOUT "TRANSCRIPT_VERSION_UPDATE: %d %s.%s (%s)\n",
			  $tran->dbID, $tran->stable_id, $tran->version,
			  $tran->true_version;
			push @sql,
			  &update_sql(
						   'transcript',     $tran->dbID,
						   $tran->stable_id, $tran->version,
						   $tran->true_version
			  );
		}
		$transcripts_any_changes ||= $this_transcript_any_changes;
		$transcripts_seq_changes ||= $this_transcript_seq_changes;
		check_start_and_end_of_translation($tran);
	}
	return ( $transcripts_any_changes, $transcripts_seq_changes );
}

sub exons_diff {
	my ( $transcript, $shared_exons ) = @_;

	# Get a ref to the actual list of exons in the object
	my $actual_exon_list = $transcript->get_all_Exons_ref;
	my $transl           = $transcript->translation;
	### Why pass in $shared_exons as an argument?  Shouldn't it be a property of the AnnotationBroker?
	my $exons_any_changes = 0;
	my $exons_seq_changes = 0;
	my $sa                = $dba->get_StableIdAdaptor();
	foreach my $exon (@$actual_exon_list) {
		my $save_exon = $exon;
		if ( my $hashed_exon = $shared_exons->{ $exon->stable_id } ) {

			# we've seen it already in the new set
			if ( compare( $hashed_exon, $exon ) ) {
				$exons_any_changes = 1;
				$exons_seq_changes = 1
			}
		}
		elsif ( my $db_exon = $ref_gene_hash->{ $exon->stable_id } ) {

			# haven't seen yet, but it had a prev.version
			if ( compare( $db_exon, $exon ) ) {

				my $seq_diff = $db_exon->seq()->seq ne $exon->seq()->seq;
				$exons_any_changes = 1;
				$exons_seq_changes ||= $seq_diff;
				$exon->true_version( $db_exon->true_version + $seq_diff );
			}
			else {
				$exon->true_version( $db_exon->true_version );
			}
			if ( $exon->version ne $exon->true_version ) {
				printf STDOUT "EXON_VERSION_UPDATE: %d %s.%s (%s)\n",
				  $exon->dbID, $exon->stable_id, $exon->version,
				  $exon->true_version;
				push @sql,
				  &update_sql( 'exon', $exon->dbID, $exon->stable_id,
							   $exon->version, $exon->true_version );
			}
		}
		else {
			$exons_any_changes =
			  1;    # a birth of a new exon is clearly a change :)
			$exons_seq_changes = 1;    # including the change in the sequence
		}

		# maintain a set of all exons of all transcripts of the gene
		if ( !$shared_exons->{ $exon->stable_id } ) {
			$shared_exons->{ $exon->stable_id } = $exon;
		}

		# If we have used an exon from the database, we must
		# check to see if the translation uses it.
		if ( $transl and $exon != $save_exon ) {
			if ( $save_exon == $transl->start_Exon ) {
				$transl->start_Exon($exon);
			}
			if ( $save_exon == $transl->end_Exon ) {
				$transl->end_Exon($exon);
			}
		}
	}
	return ( $exons_any_changes, $exons_seq_changes );
}

sub translations_diff {
	my ($transcript)            = @_;
	my $translation_any_changes = 0;
	my $translation_seq_changes = 0;
	if ( my $translation = $transcript->translation() ) {
		my $db_transcript = $ref_gene_hash->{ $transcript->stable_id };
		if ( $db_transcript
			 && ( my $db_translation = $db_transcript->translation() ) )
		{
			my $created_time = $db_translation->created_date();
			my $db_version   = $db_translation->true_version();
			if ( $db_translation->stable_id ne $translation->stable_id ) {
				print STDERR
				  "Translations being compared have different stable_ids: '"
				  . $db_translation->stable_id
				  . "' and '"
				  . $translation->stable_id . "'\n";

				my $existing_translation =
				  $dba->get_TranslationAdaptor->fetch_by_stable_id(
													  $translation->stable_id );
				$existing_translation = 0;
				if ($existing_translation) {
					throw(  "new translation stable_id("
						  . $translation->stable_id
						  . ") for this transcript("
						  . $transcript->stable_id()
						  . ") is already associated with another transcript" );
				}
				else {    # NEW, but with a given stable_id
					$db_version              = 0;
					$translation_any_changes = 1;
					$translation_seq_changes = 1;
				}
			}
			else {
				$translation_any_changes =
				  compare( $db_translation, $translation )
				  || ( $db_transcript->translatable_Exons_vega_hashkey ne
					   $transcript->translatable_Exons_vega_hashkey );
				if ($translation_any_changes) {
					if (    ( my $db_translate = $db_transcript->translate() )
						 && ( my $translate = $transcript->translate() ) )
					{
						$translation_seq_changes =
						  $db_translate->seq() ne $translate->seq();
					}
					else {
						if ( !$db_translate ) {
							warn "db_translate does not exist for "
							  . $db_transcript->stable_id . '('
							  . $db_transcript->dbID . ')';
						}
						elsif ( !$translate ) {
							warn "translate does not exist for "
							  . $transcript->stable_id;
						}
						$translation_seq_changes = 1;
					}
				}
			}
			$translation->created_date( $db_translation->created_date() );
			$translation->modified_date(   $translation_any_changes
										 ? &current_time()
										 : $db_translation->modified_date );
			$translation->true_version(
									   $db_version + $translation_seq_changes );
			if ( $translation->version ne $translation->true_version ) {
				printf STDOUT "TRANSLATION_VERSION_UPDATE: %d %s.%s (%s)\n",
				  $translation->dbID,    $translation->stable_id,
				  $translation->version, $translation->true_version;
				push @sql,
				  &update_sql(
							   'translation',
							   $translation->dbID,
							   $translation->stable_id,
							   $translation->version,
							   $translation->true_version
				  );
			}
		}
		else {    # NEW
			$translation->created_date( &current_time() );
			$translation->modified_date( &current_time() );
			$translation->version(1);
			$translation_any_changes = 1;
			$translation_seq_changes = 1;
		}
	}
	else {
		my $db_transcript = $ref_gene_hash->{ $transcript->stable_id };
		if ( $db_transcript
			 && ( my $db_translation = $db_transcript->translation() ) )
		{
			$translation_any_changes = 1;
			$translation_seq_changes = 1;
		}
	}
	return ( $translation_any_changes, $translation_seq_changes );
}

sub check_start_and_end_of_translation {
	my ($transcript) = @_;
	my $translation = $transcript->translation();
	unless ($translation) {
		return 0;
	}
	my $exons = $transcript->get_all_Exons_ref;

	#make sure that the start and end exon are set correctly
	my $start_exon = $translation->start_Exon();
	my $end_exon   = $translation->end_Exon();
	if ( !$start_exon ) {
		throw("Translation does not define a start exon.");
	}
	if ( !$end_exon ) {
		throw("Translation does not define an end exon.");
	}
	if ( !$start_exon->dbID() ) {
		my $key = $start_exon->vega_hashkey();
		($start_exon) = grep { $_->vega_hashkey() eq $key } @$exons;
		if ($start_exon) {
			$translation->start_Exon($start_exon);
		}
		else {
			($start_exon) =
			  grep { $_->stable_id eq $translation->start_Exon->stable_id }
			  @$exons;
			if ($start_exon) {
				$translation->start_Exon($start_exon);
			}
			else {
				throw(
					"Translation's start_Exon does not appear to be one of the "
					  . "exons in its associated Transcript" );
			}
		}
	}
	if ( !$end_exon->dbID() ) {
		my $key = $end_exon->vega_hashkey();
		($end_exon) = grep { $_->vega_hashkey() eq $key } @$exons;
		if ($end_exon) {
			$translation->end_Exon($end_exon);
		}
		else {
			($end_exon) =
			  grep { $_->stable_id eq $translation->end_Exon->stable_id }
			  @$exons;
			if ($end_exon) {
				$translation->end_Exon($end_exon);
			}
			else {
				throw(
					  "Translation's end_Exon does not appear to be one of the "
						. "exons in its associated Transcript." );
			}
		}
	}
	return 1;
}
