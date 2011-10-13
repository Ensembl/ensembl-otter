#!/usr/bin/env perl

### fix_gene_biotypes.pl

use strict;
use warnings;

use Bio::Otter::Lace::Defaults;
use Bio::Otter::Lace::PipelineDB;

{
    $0 = 'otterlace';   # For testing, to see restricted dataset.
    my $dataset_name = 'human_test';

    my $usage = sub { exec('perldoc', $0) };
    # This do_getopt() call is needed to parse the otter config files
    # even if you aren't giving any arguments on the command line.
    Bio::Otter::Lace::Defaults::do_getopt(
        'h|help!'       => $usage,
        'dataset=s'     => \$dataset_name,
        ) or $usage->();
    $usage->() unless $dataset_name;
    
    my $dba;
    if (0) {
        # Client communicates with otter HTTP server
        my $cl = Bio::Otter::Lace::Defaults::make_Client();
    
        # DataSet interacts directly with an otter database
        my $ds = $cl->get_DataSet_by_name($dataset_name);
    
        my $otter_dba = $ds->get_cached_DBAdaptor;
        $dba = $otter_dba->dbc;
    }
    else {
        # This is the version of the script used to patch vega_homo_sapiens_20110516_v62_GRCh37

        # $dba = DBI->connect("DBI:mysql:database=vega_homo_sapiens_20110516_v62_GRCh37;host=ensdb-1-11;port=5317",
        #     'ensadmin', 'ensembl', {RaiseError => 1});

        # $dba = DBI->connect("DBI:mysql:database=vega_homo_sapiens_20110711_v63_GRCh37;host=ensdb-1-11;port=5317",
        #     'ensadmin', 'ensembl', {RaiseError => 1});

        $dba = DBI->connect("DBI:mysql:database=vega_homo_sapiens_20111010_v64_GRCh37;host=ensdb-1-11;port=5317",
            'ensadmin', 'ensembl', {RaiseError => 1});
    }
    
    my $sth = $dba->prepare(q{
        SELECT g.biotype
          , g.status
          , g.gene_id
          , t.biotype
          , t.status
        FROM (gene g
              , transcript t)
        LEFT JOIN transcript_attrib ta
          ON t.transcript_id = ta.transcript_id
          AND ta.attrib_type_id = 54
          AND ta.value = 'not for VEGA'
        WHERE g.gene_id = t.gene_id
          AND g.is_current = 1
          AND ta.transcript_id IS NULL
    });
    $sth->execute;
    
    # gene_id  stable_id           biotype    
    # -------  ------------------  -----------
    # 364283   OTTHUMG00000030222  polymorphic
    # 352727   OTTHUMG00000163212  polymorphic
    # 380254   OTTHUMG00000166126  polymorphic
    
    # AND g.gene_id in (364283, 352727, 380254)
    
    
    my $update = $dba->prepare(q{
        UPDATE gene SET biotype = ?, status = ? WHERE gene_id = ?
    });
    
    my %gene_tsct_biotypes;
    while (my ($gene_biotype, $gene_status, $gene_id, $tsct_biotype, $tsct_status) = $sth->fetchrow) {
        $gene_status ||= '';
        $tsct_status ||= '';
        my $gene_data = $gene_tsct_biotypes{$gene_id} ||= {};
        $gene_data->{'biotype'} = $gene_biotype;
        $gene_data->{'stauts'}  = $gene_status;
        $gene_data->{'tsct_biotype'}{$tsct_biotype}++;
        $gene_data->{'tsct_status' }{$tsct_status }++;
    }
    
    my %transitions;
    foreach my $gene_id (sort {$a <=> $b} keys %gene_tsct_biotypes) {
        my $gene_data = $gene_tsct_biotypes{$gene_id};
        my ($gene_biotype) = $gene_data->{'biotype'};
        my ($gene_status)  = $gene_data->{'stauts'};
        my $tsct_biotype_hash = $gene_data->{'tsct_biotype'};
        my $tsct_status_hash  = $gene_data->{'tsct_status' };
        my ($new_biotype, $new_status) = set_biotype_status_from_transcripts($gene_status, $tsct_biotype_hash, $tsct_status_hash);
        if ($new_biotype ne $gene_biotype or $new_status ne $gene_status) {
            # if ("$gene_biotype ($gene_status) > $new_biotype ($new_status)" eq "processed_transcript (NOVEL) > antisense (PUTATIVE)") {
            #     die $gene_id;
            # }
            $transitions{"  $gene_biotype ($gene_status) > $new_biotype ($new_status)"}++;
            $transitions{"$gene_biotype > $new_biotype"}++;
            $update->execute($new_biotype, $new_status, $gene_id);
        }
    }
    
    foreach my $trans (sort keys %transitions) {
        printf "%8d  %s\n", $transitions{$trans}, $trans;
    }
}

# Edited version of method in Bio::Vega::Gene
sub set_biotype_status_from_transcripts {
    # my ($self) = @_;
    my ($gene_status, $tsct_biotype_hash, $tsct_status_hash) = @_;

    my (%tsct_biotype, %tsct_status);
    # TSCT: foreach my $tsct (@{$self->get_all_Transcripts}) {
    #     foreach my $attrib (@{ $self->get_all_Attributes('remark') }) {
    #         if ($attrib->value eq 'not for VEGA') {
    #             # Skip transcripts tagged with "not for VEGA"
    #             next TSCT;
    #         }
    #     }
    #     $tsct_biotype{$tsct->biotype}++;
    #     $tsct_status{ $tsct->status }++;
    # }

    %tsct_biotype = %$tsct_biotype_hash;
    %tsct_status  = %$tsct_status_hash;

    my $biotype = 'processed_transcript';
    if (my @pseudo = grep { /pseudo/i } keys %tsct_biotype) {
        if (@pseudo > 1) {
            # throw(
            #     sprintf "More than one psedogene type in gene %s (%s)",
            #         $self->get_all_Attributes('name')->[0]->value,
            #         join(', ', @pseudo)
            #     );
            die "More than one psedogene type in gene\n";
        }
        else {
            if ($tsct_biotype{'protein_coding'}) {
                $biotype = 'polymorphic';
            }
            else {
                $biotype = $pseudo[0];
            }
        }
    }
    elsif ($tsct_biotype{'protein_coding'} or $tsct_biotype{'nonsense_mediated_decay'}) {
        $biotype = 'protein_coding';
    }
    elsif (keys %tsct_biotype == 1) {
        # If there is just 1 transcript biotype, then the gene gets it too.
        ($biotype) = keys %tsct_biotype;
    }
    # $self->biotype($biotype);

    # Have already set status to KNOWN if Known was set in acedb.
    # unless ($self->is_known) {
    my $status = '';
    if ($gene_status eq 'KNOWN') {
        $status = 'KNOWN';
    } else {
        # Not setting gene status to KNOWN if there is a transcript
        # with status KNOWN.  So KNOWN is only set if radio button in
        # otterlace is checked.
        if ($tsct_status{'PUTATIVE'} and keys(%tsct_status) == 1) {
            # Gene status is PUTATIVE if that is the only kind of transcript
            $status = 'PUTATIVE';
        }
        elsif ($tsct_status{'NOVEL'} or ($biotype !~ /pseudo/i and $biotype ne 'TEC')) {
            $status = 'NOVEL';
        }
        # $self->status($status);
    }

    return ($biotype, $status);
}



__END__

=head1 NAME - fix_gene_biotypes.pl

    SELECT g.biotype
      , t.transcript_id
      , t.biotype
      , ta.value
    FROM (gene g
          , transcript t
          , gene_stable_id gsid)
    LEFT JOIN transcript_attrib ta
      ON t.transcript_id = ta.transcript_id
      AND ta.attrib_type_id = 54
      AND ta.value = 'not for VEGA'
    WHERE g.gene_id = t.gene_id
      AND g.gene_id = gsid.gene_id
      AND g.is_current = 1
      AND gsid.stable_id = 'OTTHUMG00000166126'


=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

