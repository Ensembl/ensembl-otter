#!/usr/bin/env perl

use warnings;

use strict;
use Carp;
use IO::String;
use Bio::Otter::Lace::Defaults;
use Bio::SeqIO;
use Bio::EnsEMBL::Pipeline::SeqFetcher;
use Bio::Factory::EMBOSS;       # EMBOSS needs to be on PATH - /software/pubseq/bin/EMBOSS-5.0.0/bin
                                # To verify, check that 'wossname water' runs successfully
use Bio::AlignIO;

use Hum::Pfetch;

{
    my $dataset_name = undef;
    my %opts = (
        total => 0,
        quiet => 0,
        verbose => 0,
        evi_type => undef,
        max_length => undef,
        );

    my $usage = sub { exec('perldoc', $0) };
    # This do_getopt() call is needed to parse the otter config files
    # even if you aren't giving any arguments on the command line.
    Bio::Otter::Lace::Defaults::do_getopt(
        'h|help!'       => $usage,
        'dataset=s'     => \$dataset_name,
        'quiet!'        => \$opts{quiet},
        'verbose!'      => \$opts{verbose},
        'total!'        => \$opts{total},
        'type:s'        => \$opts{evi_type},
        'maxlength:s'   => \$opts{max_length},
        ) or $usage->();
    $usage->() unless $dataset_name;
    if (my $et = $opts{evi_type}) {
        unless (   $et eq 'ncRNA' 
                || $et eq 'EST'
                || $et eq 'Protein'
                || $et eq 'cDNA'
                || $et eq 'Genomic'
            ) {
            croak "type must be one of EST,ncRNA,Protein,cDNA,Genomic";
        }
    }
    if ($opts{quiet} and not $opts{total}) {
        carp "Using -quiet but not -total - no output will be produced!";
    }

    # Client communicates with otter HTTP server
    my $cl = Bio::Otter::Lace::Defaults::make_Client();
    
    # DataSet interacts directly with an otter database
    my $ds = $cl->get_DataSet_by_name($dataset_name);
    my $otter_dba = $ds->get_cached_DBAdaptor;
    my $pipe_dba = Bio::Otter::Lace::PipelineDB::get_pipeline_DBAdaptor($otter_dba);

    my $transcript_adaptor = $otter_dba->get_TranscriptAdaptor;

    my $where = "";
    my @args = ();
    if ($opts{evi_type}) {
        $where = "AND e.type = ?";
        push @args, $opts{evi_type};
    }
    my $list_transcripts = $otter_dba->dbc->prepare(qq{
        SELECT DISTINCT
                t.transcript_id
        FROM
                transcript t
           JOIN gene g USING (gene_id)
           JOIN evidence e ON t.transcript_id = e.transcript_id
        WHERE
                t.is_current = 1
            AND g.source = 'havana'
            $where
        ORDER BY t.transcript_id
    });
    $list_transcripts->execute(@args);

    my $count = 0;
    while (my ($tid) = $list_transcripts->fetchrow()) {
        ++$count;
        printf( "TID: %10d\n", $tid ) if $opts{verbose};
        process_transcript($tid, $transcript_adaptor, \%opts);
    }
    printf "Total: %d\n", $count if $opts{total};

}

my ($seq_str, $seq_str_io, $seqio_out);

sub setup_io {
    $seq_str_io = IO::String->new(\$seq_str);
    $seqio_out = Bio::SeqIO->new(-format => 'Fasta',
                                 -fh     => $seq_str_io );
}

my $fetcher;

# Warning - Bio::EnsEMBL::Pipeline::SeqFetcher spawns a pfetch each time to do the work
#
sub pfetch_ensembl_pipeline {
    my ( $id ) = @_;
    $fetcher ||= Bio::EnsEMBL::Pipeline::SeqFetcher->new;
    my $seq = $fetcher->run_pfetch($id);
    carp sprintf "Cannot pfetch '%s'!\n", $id unless $seq;
    return $seq;
}

sub pfetch {
    my ( $id ) = @_;
    my ($hum_seq) = Hum::Pfetch::get_Sequences($id);
    unless ($hum_seq) {
        carp sprintf "Cannot pfetch '%s'!\n", $id;
        return undef;
    }
    my $seq = Bio::Seq->new(
        -seq        => $hum_seq->sequence_string,
        -display_id => $hum_seq->name,
        );
    return $seq;
}

my ($factory, $comp_app);

sub get_comp_app {
    $factory ||= Bio::Factory::EMBOSS->new();
    $comp_app ||= $factory->program('water');
    return $comp_app;
}

sub process_transcript {
    my ($tid, $transcript_adaptor, $opts) = @_;

    my $td = $transcript_adaptor->fetch_by_dbID($tid);
    if ($td) {

        #TEMP
        if ($td->stable_id eq 'OTTHUMT00000109016') {
            1;
        }

        if ($opts->{verbose}) {
            setup_io() unless $seqio_out;
            $seq_str_io->truncate(0);   # reset to start of $seq_str
            $seqio_out->write_seq($td->seq);
            print $seq_str;
        }

        my @evidence = @{$td->evidence_list};
        EVIDENCE: foreach my $evi (@evidence) {

            next EVIDENCE unless $evi->type eq $opts->{evi_type};

            printf "\t%s:%s\n", $evi->{name}, $evi->{type} if $opts->{verbose};

            my $evi_seq = pfetch($evi->{name});
            next EVIDENCE unless $evi_seq;

            if (    $opts->{max_length}
                    and ($evi_seq->length > $opts->{max_length})
                    and ($td->seq->length > $opts->{max_length})
                ) {
                carp "Transcript and evidence both too long, skipping";
                next EVIDENCE;
            }

            # Compare them
            my $comp_app = get_comp_app();
            my $comp_fh = File::Temp->new();
            my $comp_outfile = $comp_fh->filename;
            
            $comp_app->run({-asequence => $td->seq,
                            -bsequence => [$evi_seq],
                            -outfile   => $comp_outfile,
                            -aformat   => 'srspair',
                           });

            my $alnin = Bio::AlignIO->new(-format => 'emboss',
                                          -fh     => $comp_fh);

            while ( my $aln = $alnin->next_aln ) {
                # process the alignment -- these will be Bio::SimpleAlign objects
                if ($opts->{verbose}) {
                    printf("\tScore: %10.1f length: %5d flush: %s ident: %5.1f%%\n",
                           $aln->score,
                           $aln->length,
                           $aln->is_flush ? "Y" : "N",
                           $aln->overall_percentage_identity,
                        );
                } elsif (not $opts->{quiet}) {
                    printf("%s,%s,%s,%.1f,%d,%s,%.1f,%d,%d\n",
                           $td->stable_id,
                           $evi->{name},
                           $evi->{type},
                           $aln->score,
                           $aln->length,
                           $aln->is_flush ? "1" : "0",
                           $aln->overall_percentage_identity,
                           $td->seq->length,
                           $evi_seq->length,
                        );
                }
            }

        } # EVIDENCE

    }
}



__END__

=head1 NAME - explore_evidence_for_transcripts.pl

=head1 SYNOPSIS

explore_evidence_for_transcripts.pl -dataset <DATASET NAME> [-type <EVIDENCE_TYPE>] [-quiet] [-total]

=head1 DESCRIPTION

Explore evidence matching a transcript.

=head1 AUTHOR

Michael Gray B<email> mg13@sanger.ac.uk

