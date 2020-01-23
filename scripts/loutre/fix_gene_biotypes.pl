#!/usr/bin/env perl
# Copyright [2018-2020] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


### fix_gene_biotypes.pl

use strict;
use warnings;
use Try::Tiny;
use Net::Netrc;

use Bio::Otter::Lace::Defaults;
use Bio::EnsEMBL::DBSQL::DBAdaptor;


# use Bio::Otter::Lace::PipelineDB;

{
    # my $dataset_name = 'human_test';

    my $usage = sub { exec('perldoc', $0) };

    # This do_getopt() call is needed to parse the otter config files
    # even if you aren't giving any arguments on the command line.
    Bio::Otter::Lace::Defaults::do_getopt(
        'h|help!' => $usage,
        # 'dataset=s'     => \$dataset_name,
    ) or $usage->();

    # $usage->() unless $dataset_name;


    # if (0) {
    #     # Client communicates with otter HTTP server
    #     $0 = 'otter';   # For testing, to see restricted dataset.
    #     my $cl = Bio::Otter::Lace::Defaults::make_Client();
    #
    #     # DataSet interacts directly with an otter database
    #     my $ds = $cl->get_DataSet_by_name($dataset_name);
    #
    #     my $otter_dba = $ds->get_cached_DBAdaptor;
    #     $dba = $otter_dba->dbc;
    # }
    # else {
    # This is the version of the script used to patch vega_homo_sapiens_20110516_v62_GRCh37

    # $dba = DBI->connect("dbname=vega_homo_sapiens_20110516_v62_GRCh37;host=ensdb-1-11;port=5317",
    #     'ensadmin', '*******', {RaiseError => 1});

    # $dba = DBI->connect("dbname=vega_homo_sapiens_20110711_v63_GRCh37;host=ensdb-1-11;port=5317",
    #     'ensadmin', '*******', {RaiseError => 1});

    # $dba = DBI->connect("dbname=vega_homo_sapiens_20111010_v64_GRCh37;host=ensdb-1-11;port=5317",
    #     'ensadmin', '*******', {RaiseError => 1});

    # $dba = DBI->connect("dbname=vega_mus_musculus_20111010_v64_NCBIM37;host=ensdb-1-11;port=5317",
    #     'ensadmin', '*******', {RaiseError => 1});

    # my $dsn = "dbname=vega_homo_sapiens_20111219_v65_GRCh37;host=ensdb-1-11;port=5317";
    # my $dsn = "dbname=homo_sapiens_vega_65_20111219_gb_4;host=ensdb-1-11;port=5317";
    # my $dsn = "dbname=amonida_human_vega_67;host=genebuild4;port=3306";
    
    # my $dsn = "species=human;dbname=vega_homo_sapiens_20120319_v66_GRCh37;host=ensdb-web-17;port=5317";
    # my $dsn = "species=mouse;dbname=vega_mus_musculus_20120316_66_GRCm38;host=ensdb-web-17;port=5317";

    # my $dsn = "species=zebrafish;dbname=vega_danio_rerio_20120611_67_Zv9;host=ensdb-web-17;port=5317";
    # my $dsn = "species=human;dbname=vega_homo_sapiens_20120611_67_GRCh37;host=ensdb-web-17;port=5317";
    # my $dsn = "species=pig;dbname=vega_sus_scrofa_20120618_67;host=ensdb-web-17;port=5317";

    # my @args = qw( -dbname vega_mus_musculus_20120821_68_GRCm38 -host ensdb-web-17 -port 5317 );
    # my @args = qw( -dbname vega_homo_sapiens_20120813_68_GRCh37 -host ensdb-web-17 -port 5317 );

    # my @args = qw( -dbname vega_mus_musculus_20120821_68_GRCm38 -host ensdb-web-17 -port 5317 );
    # my @args = qw( -dbname vega_homo_sapiens_20120813_68_GRCh37 -host ensdb-web-17 -port 5317 );

    # my @args = qw( -dbname vega_homo_sapiens_20120822_68_GRCh37 -host ensdb-web-17 -port 5317 );
    # my @args = qw( -dbname vega_mus_musculus_20120822_68_GRCm38 -host ensdb-web-17 -port 5317 );
    
    # my @args = qw( -dbname vega_homo_sapiens_20120822_69_GRCh37 -host ensdb-web-17 -port 5317 );
    # my @args = qw( -dbname vega_mus_musculus_20120822_69_GRCm38 -host ensdb-web-17 -port 5317 );

    # my @args = qw( -dbname vega_danio_rerio_20121112_69_Zv9 -host ensdb-web-17 -port 5317 );
    # my @args = qw( -dbname vega_homo_sapiens_20121112_69_GRCh37 -host ensdb-web-17 -port 5317 );

    # my @args = qw( -dbname vega_homo_sapiens_20130211_70_GRCh37 -host ensdb-web-17 -port 5317 );
    # my @args = qw( -dbname vega_mus_musculus_20130211_70_GRCm38 -host ensdb-web-17 -port 5317 );

    # my @args = qw( -dbname vega_homo_sapiens_20130422_71_GRCh37 -host ensdb-web-17 -port 5317 );
    # my @args = qw( -dbname vega_danio_rerio_20130422_71_Zv9 -host ensdb-web-17 -port 5317 );

    # my @args = qw( -dbname vega_homo_sapiens_20130722_72_GRCh37 -host ensdb-web-17 -port 5317 );
    # my @args = qw( -dbname vega_mus_musculus_20130722_72_GRCm38 -host ensdb-web-17 -port 5317 );
    # my @args = qw( -dbname vega_sus_scrofa_20130722_72 -host ensdb-web-17 -port 5317 );
    # my @args = qw( -dbname vega_rattus_norvegicus_20130610_72_5a -host ensdb-web-17 -port 5317 );
    # my %args = qw( -dbname vega_sarcophilus_harrisii_20130909_72 -host ensdb-web-17 );
    # my %args = qw( -dbname vega_homo_sapiens_20140402_74_GRCh38 -host ensdb-web-17 );
    # my %args = qw( -dbname vega_mus_musculus_20140415_75_GRCm38 -host ensdb-web-17 );
    my %args = qw( -dbname vega_danio_rerio_20131007_74_Zv9 -host ensdb-web-17 );

    printf "%s fix_gene_biotypes.pl on (%s)\n", scalar(localtime), join(" ", %args);

    my $mchn = Net::Netrc->lookup($args{'-host'})
      or die "No entry for '$args{-host}' in ~/.netrc";
    $args{'-user'}  = $mchn->login;
    $args{'-pass'}  = $mchn->password;
    $args{'-port'}  = $mchn->account;
    $args{'-group'} = 'ensembl';

    my $dba = Bio::EnsEMBL::DBSQL::DBAdaptor->new(%args);

    my $species = $dba->get_MetaContainer->get_common_name; # meta_key = 'species.common_name'

    my $ott_ncRNA_host;
    # if ($species eq 'human') {
    #     my $progdir = $0;
    #     $progdir =~ s{/[^/]+$}{};
    #     open my $nc_fh, '-|', "$progdir/detect_ncRNA_host_genes"
    #       or die "Can't open pipe from detect_ncRNA_host_genes; $!";
    #     while (defined(my $ott = <$nc_fh>)) {
    #         chomp($ott);
    #         $ott_ncRNA_host->{$ott} = 1;
    #     }
    #     close $nc_fh or die "Error running detect_ncRNA_host_genes; exit $?";
    #     my $n = keys %$ott_ncRNA_host;
    #     warn "Found $n ncRNA_host genes\n";
    # }

    # my $dba = DBI->connect($dsn, 'ensadmin', '*******', { RaiseError => 1 });
    my $dbh = $dba->dbc->db_handle;
    $dbh->begin_work;
    
    my $error = 0;
    try {
        fix_biotypes($dba, $ott_ncRNA_host);
    }
    catch {
        $error = 1;
        warn "Error: $_";
        $dbh->rollback;
    };
    unless ($error) {
        $dbh->commit;
    }
}

sub fix_biotypes {
    my ($dba, $ott_ncRNA_host) = @_;

    my $dbc = $dba->dbc;
    my $sth = $dbc->prepare(
        q{
        SELECT g.biotype
          , g.status
          , g.gene_id
          , g.stable_id
          , t.biotype
          , t.status
        FROM gene g
        JOIN transcript t ON g.gene_id = t.gene_id
        LEFT JOIN transcript_attrib ta
          ON t.transcript_id = ta.transcript_id
          AND ta.attrib_type_id = 54
          AND ta.value = 'not for VEGA'
        WHERE g.is_current = 1
          AND ta.transcript_id IS NULL
          AND t.biotype != 'artifact'
    }
    );
    $sth->execute;

    # gene_id  stable_id           biotype
    # -------  ------------------  -----------
    # 364283   OTTHUMG00000030222  polymorphic
    # 352727   OTTHUMG00000163212  polymorphic
    # 380254   OTTHUMG00000166126  polymorphic

    # AND g.gene_id in (364283, 352727, 380254)

    my $update = $dbc->prepare(q{
        UPDATE gene SET biotype = ?, status = ? WHERE gene_id = ?
    });

    my %gene_tsct_biotypes;
    while (my ($gene_biotype, $gene_status, $gene_id, $gsid, $tsct_biotype, $tsct_status) = $sth->fetchrow) {
        next if $tsct_biotype eq 'artifact';
        $gene_status ||= '';
        $tsct_status ||= '';
        my $gene_data = $gene_tsct_biotypes{$gene_id} ||= {};
        $gene_data->{'biotype'}   = $gene_biotype;
        $gene_data->{'status'}    = $gene_status;
        $gene_data->{'stable_id'} = $gsid;
        $gene_data->{'tsct_biotype'}{$tsct_biotype}++;
        $gene_data->{'tsct_status'}{$tsct_status}++;
    }

    # Look for Annotator Set Biotypes (ASB), which allow
    # the annotator to override the biotype which would
    # be automatically selected for the locus.
    my $fetch_asb = $dbc->prepare(
        q{
            SELECT g.gene_id
              , ga.value
            FROM gene g
              , gene_attrib ga
            WHERE g.gene_id = ga.gene_id
              AND g.is_current = 1
              AND ga.attrib_type_id IN(54, 123)
              AND SUBSTR(ga.value, 1, 4) = 'ASB_' 
        }
    );
    $fetch_asb->execute;
    
    my %gene_asb;
    while (my ($gene_id, $asb) = $fetch_asb->fetchrow) {
        my $gene_data = $gene_tsct_biotypes{$gene_id};
        unless ($gene_data) {
            warn "No gene data for gene_id = '$gene_id'";
            next;
        }
        $asb =~ s/^ASB_//;
        $gene_data->{'annotator_set_biotype'} = $asb;
    }

    my %transitions;
    my $nc_RNA_host_remark       = 'ncRNA host';
    my $nc_RNA_host_remark_added = 0;
    foreach my $gene_id (sort { $a <=> $b } keys %gene_tsct_biotypes) {
        my $gene_data         = $gene_tsct_biotypes{$gene_id};
        my ($gene_biotype)    = $gene_data->{'biotype'};
        my ($gene_status)     = $gene_data->{'status'};
        my $tsct_biotype_hash = $gene_data->{'tsct_biotype'};
        my $tsct_status_hash  = $gene_data->{'tsct_status'};
        my ($new_biotype, $new_status) =
          set_biotype_status_from_transcripts($gene_status, $tsct_biotype_hash, $tsct_status_hash);
        if (my $asb = $gene_data->{'annotator_set_biotype'}) {
            $new_biotype = $asb;
        }
        
        # EnsEMBL fear the single quote
        $new_biotype =~ s/3'_/3prime_/;

        if ($ott_ncRNA_host->{ $gene_data->{'stable_id'} }) {
            $nc_RNA_host_remark_added += add_remark_attribute_if_missing($dba, $gene_id, $nc_RNA_host_remark);
        }
        if ($new_biotype ne $gene_biotype or $new_status ne $gene_status) {
            $transitions{"  $gene_biotype ($gene_status) > $new_biotype ($new_status)"}++;
            $transitions{"$gene_biotype > $new_biotype"}++;
            $update->execute($new_biotype, $new_status || undef, $gene_id);
        }
    }

    foreach my $trans (sort keys %transitions) {
        printf "%8d  %s\n", $transitions{$trans}, $trans;
    }
    print "Added $nc_RNA_host_remark_added '$nc_RNA_host_remark' remarks\n";
    return;
}

{
    my $attrib_insert;

    sub add_remark_attribute_if_missing {
        my ($dba, $gene_id, $remark) = @_;

        $attrib_insert ||= $dba->dbc->prepare(qq{
            INSERT INTO gene_attrib(gene_id, attrib_type_id, value)
            VALUES (?, 54, ?)
        });

        my $gene_aptr = $dba->get_GeneAdaptor;
        my $gene = $gene_aptr->fetch_by_dbID($gene_id)
          or die "No gene with dbID '$gene_id'";
        my $have_attrib = 0;
        foreach my $attrib (@{ $gene->get_all_Attributes('remark') }) {
            if ($attrib->value eq $remark) {
                $have_attrib = 1;
                last;
            }
        }
        if ($have_attrib) {
            return 0;
        }
        else {
            $attrib_insert->execute($gene_id, $remark);
            return 1;
        }
    }
    
}


# ncRNA_host
# transcribed pseudogene

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
            die "More than one pseudogene type in gene\n";
        }
        else {
            $biotype = $pseudo[0];
        }
    }
    elsif ($tsct_biotype{'protein_coding'}
        or $tsct_biotype{'nonsense_mediated_decay'}
        or $tsct_biotype{'non_stop_decay'})
    {
        $biotype = 'protein_coding';
    }
    elsif ($tsct_biotype{'retained_intron'} or $tsct_biotype{'ambiguous_orf'}) {
        $biotype = 'processed_transcript';
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
    }
    else {

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

