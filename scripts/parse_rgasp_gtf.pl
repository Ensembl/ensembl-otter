#!/usr/bin/env perl
# Copyright [2018-2019] EMBL-European Bioinformatics Institute
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


use strict;
use warnings;
use Net::Netrc;

use Data::Dumper qw { Dumper };
use Getopt::Long qw{ GetOptions };
use Text::ParseWords qw{ quotewords };

use Bio::EnsEMBL::Gene;
use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::Translation;
use Bio::EnsEMBL::DBEntry;

$|                   = 1;    # unbuffer output
$Data::Dumper::Terse = 1;

my %file_to_ana_name;
while (<DATA>) {
    next if /^\s*$/;
    next if /^\s*#/;
    chomp;
    my ($file, $ana_name) = split;
    $file_to_ana_name{$file} = $ana_name;
}

{
    my $host = 'mcs4a';
    my $user = '';
    my $pass = '';
    my $port = '';

    # my $dbname = 'gencode_homo_sapiens_rgasp_56_37';
    my $dbname = 'gencode_caenorhabditis_elegans_rgasp_56_200';

    # options to be read in from the commandline
    GetOptions(
        'host=s'   => \$host,
        'user=s'   => \$user,
        'dbname=s' => \$dbname,
        'pass=s'   => \$pass,
        'port=i'   => \$port,
    );
    unless ($pass) {
        if (my $netrc = Net::Netrc->lookup($host)) {
            $user ||= $netrc->login;
            $pass ||= $netrc->password;
            $port ||= $netrc->account;
        }
    }

    # connect to the Ensembl db (to which we will write genes)
    my $db = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
        -host   => $host,
        -user   => $user,
        -pass   => $pass,
        -port   => $port,
        -dbname => $dbname,
    );

    foreach my $file (@ARGV) {
        warn "\nParsing $file\n";
        begin_work($db);
        eval { load_gtf($file, $db); };
        if (my $err = $@) {
            rollback($db);
            warn "Error loading $file, nothing saved\n$err";
        }
        else {
            commit($db);
            warn "File loaded OK $file\n";
        }
    }
}

sub begin_work {
    my $db = shift;

    $db->dbc->db_handle->begin_work;
    $db->dbc->db_handle->{'AutoCommit'} = 0;
}

sub rollback {
    my $db = shift;

    $db->dbc->db_handle->commit;
}

sub commit {
    my $db = shift;

    $db->dbc->db_handle->commit;
}

sub load_gtf {
    my ($file, $db) = @_;

    my ($file_name) = $file =~ m{([^/]+)\.[^\.]+$};
    my $ana_name = $file_to_ana_name{$file_name}
      or die "Cannot see an analysis name for file name '$file_name'";
    warn "Analysis logic name = '$ana_name'\n";

    delete_all_genes_by_type($db, $ana_name);

    # adaptor required
    my $csa = $db->get_CoordSystemAdaptor();

    # fetch coordinate system
    my @args;
    if ($file =~ /_hum_/) {
        @args = ('GRCh37');
    }
    my $cs = $csa->fetch_by_name('chromosome', @args);

    # create a new analysis with logic_name $analtype
    # so that we know where the genes come from
    my $analysis = Bio::EnsEMBL::Analysis->new(-logic_name => $ana_name);

    my %info;    # Everything stored in here!
    ### Should keep track of transcript and gene IDs to see
    ### if there are any out of order in the file.
    my (%gene_id_loaded, %tsct_id_loaded);

    open my $FH, $file or die "Can't read '$file'; $!";

    # read in the gff file
    while (<$FH>) {
        next if /^\s*#/;
        next if /^\s*$/;
        chomp;

        # split the line into 9 fields
        # This means that all the ';'-separated comments will
        # remain together as one field to be parsed later
        my @gtf   = split /\s+/, $_, 9;
        my $start = $gtf[3];
        my $end   = $gtf[4];

        # gff gives you the frame not the phase - so to convert to ensembl phase:
        my $phase;
        if ($gtf[7] ne '.') {
            $phase = (3 - $gtf[7]) % 3;
        }

        my $strand = undef;
        if ($gtf[6] eq '+') {
            $strand = 1;
        }
        elsif ($gtf[6] eq '-') {
            $strand = -1;
        }

        # # #
        # Now we deal with the terminal group field
        # # #
        my $hashy = {};

        # Store everything from the group field
        foreach my $str (split(/\s*;\s*/, $gtf[8])) {
            my ($key, $val) = quotewords('\s+', 0, $str);
            $hashy->{$key} = $val;
        }

        # We're going to assume that data is dumped gene-by-gene so that
        # when we find a new gene_id we can save the previous one.
        my $geneid = delete $hashy->{'gene_id'};

        # # #
        # Deal with EXON
        # # #
        if ($gtf[2] eq "exon") {
            my $tsctid = delete $hashy->{'transcript_id'};

            my $exon_list = $info{$geneid}{'exons'}{$tsctid} ||= [];

            # create a nice data structure for exons
            my $exon_info = {
                start  => $start,
                end    => $end,
                strand => $strand,
            };
            if (keys %$hashy) {
                $exon_info->{'values'} = $hashy;
            }
            push(@$exon_list, $exon_info);
        }

        # # #
        # Deal with CDS
        # # #
        elsif ($gtf[2] eq "CDS" or $gtf[2] eq 'stop_codon') {

            my $tsctid = delete $hashy->{'transcript_id'};

            #print "In CDS geneid = $geneid tranid = $id\n";

            my $cds_list = $info{$geneid}{'cds'}{$tsctid} ||= [];

            # create a nice data structure for CDSs
            my $cds_info = {
                start  => $start,
                end    => $end,
                strand => $strand,
                phase  => $phase,
            };
            if ($gtf[2] eq 'stop_codon') {

                # Preserve the fact that this was a stop codon
                $hashy->{'stop_codon'} = 'yes';
            }
            if (keys %$hashy) {
                $cds_info->{'values'} = $hashy;
            }
            push(@$cds_list, $cds_info);
        }

        # # #
        # We just don't care about other types of feature
        # # #
        else {

            # we have a start_codon, gene, source, or other
            # unrecognised field that is going to be ignored
            # We don't really need GENE as all the info we need
            # to build a gene is already in EXON
            # We don't need SOURCE as that just tells us the
            # chromosome

            # Doesn't matter if we don't have a gene_id for a feature
            # type which we ignore anyway!
            $geneid = 'IGNORE';
        }

        # Check that gene_id field is not missing when we need it.
        if (!$geneid) {
            die "No gene_id field in line: $_";
        }
        elsif ($geneid ne 'IGNORE') {
            $info{$geneid}{'sequence'} = $gtf[0];
            $info{$geneid}{'source'}   = $gtf[1];    # Could store per transcript
        }

        # Do we have info from more than one gene yet?
        if (keys %info > 1) {
            foreach my $key (keys %info) {
                next if $key eq $geneid;             # The new gene we've just reached in the file
                save_ensembl_gene($db, $cs, $analysis, $key, \%info);
            }
        }
    }

    # finished reading in the gff file
    close $FH or die "Error reading '$file'; $!";

    # Save any remaining gene(s)
    foreach my $key (keys %info) {
        save_ensembl_gene($db, $cs, $analysis, $key, \%info);
    }
}

sub save_ensembl_gene {
    my ($db, $cs, $analysis, $key, $info) = @_;

    my $gene_info = delete $info->{$key};
    my $gene;
    eval { $gene = create_ensembl_gene($db, $cs, $analysis, $key, $gene_info); };
    if ($@) {
        die "Error creating gene: $@", "\nData: ", Dumper($gene_info);
    }
    else {

        # Save $gene
        $db->get_GeneAdaptor->store($gene) if $gene;

        # warn "Not saving gene";
    }
}

sub create_ensembl_gene {
    my ($db, $cs, $analysis, $geneid, $info) = @_;

    my $sequence = $info->{'sequence'};

    # This substitution may still leave a valid
    # value when it isn't a chromosome!
    $sequence =~ s/^chr(omosome)?[_-]?//i;

    # A number of submitters put "M" instead of "MT" for the mitochondrial genome
    if ($sequence =~ /^M/) {
        $sequence =
          $analysis->logic_name =~ /_wor_/
          ? 'MtDNA'
          : 'MT';
    }

    if ($sequence =~ /^0/) {
        warn "Skipping gene '$geneid' on sequence '$sequence' ($info->{'sequence'}); spike-in?\n";
        return;
    }

    # fetch a slice for this sequence
    my $slice = $db->get_SliceAdaptor->fetch_by_region($cs->name, $sequence)
      or die sprintf(q{Failed to fetch fetch slice %s:%s}, $cs->name, $sequence);

    my @new_transcripts = ();

    # For transcripts with CDS info but no exons, copy the CDS info to exons
    foreach my $tsctid (keys %{ $info->{'cds'} }) {
        my $cds_list = $info->{'cds'}{$tsctid};
        my $exons    = $info->{'exons'}{$tsctid};
        unless ($exons) {

            # warn "No exons in transcript '$tsctid', copying CDS coordiates\n";
            @{ $info->{'exons'}{$tsctid} } = @$cds_list;
            $exons = $info->{'exons'}{$tsctid};
        }

        # Merge overlapping exon coordinates. Fixes files where exon lines are
        # duplicated. We are only interested in the min and max coords from CDS
        # features, so we don't bother merging them.
        merge_overlapping_or_abutting($exons);
    }

    # # #
    # Make Transcripts
    # # #
    foreach my $tsctid (sort keys %{ $info->{'exons'} }) {

        # print STDERR "  transcript $tsctid\n";
        my $rpkm = '';
        if (my $score = get_value($info, 'RPKM')) {
            $rpkm = ",RPKM=$score";
        }

        my $tran = Bio::EnsEMBL::Transcript->new;
        $tran->stable_id($tsctid . $rpkm);
        $tran->version(1);
        $tran->analysis($analysis);
        $tran->status('PREDICTED');

        # # #
        # Make Exons
        # # #
        my @exons = @{ $info->{'exons'}{$tsctid} };

        # Add exons to transcript
        my $ecount = 0;
        my $tsct_strand;
        foreach my $exon (@exons) {
            $ecount++;
            my $newstrand = $exon->{strand};
            $tsct_strand ||= $newstrand;
            if ($tsct_strand != $newstrand) {
                warn "Setting exon on '$newstrand' strand to transcript strand '$tsct_strand'\n";
            }

            my $newexon = new Bio::EnsEMBL::Exon(
                -start  => $exon->{start},
                -end    => $exon->{end},
                -strand => $tsct_strand,
            );

            # Use the exon_id from the file if we have it
            my $stable_id = $exon->{'values'}{'exon_id'} if $exon->{'values'};

            # Otherwise make up a stable ID based on the transcript_id plus count
            $stable_id ||= sprintf '%s-%03d', $tran->stable_id, $ecount;
            if (my $score = get_value($exon, 'RPKM')) {
                $stable_id .= ",RPKM=$score";
            }

            $newexon->stable_id($stable_id);
            $newexon->version(1);
            $newexon->phase(-1);
            $newexon->end_phase(-1);
            $newexon->slice($slice);

            # Add Exon to Transcript
            $tran->add_Exon($newexon);
        }

        # finished adding exons to transcript

        # # #
        # Now assign Translation to Transcript
        # # #
        if (my $cdsexons = $info->{'cds'}{$tsctid}) {
            $tran->biotype('coding');

            # Set min/max span of CDS from first CDS "exon"
            my $min_exon = $cdsexons->[0];
            my $max_exon = $min_exon;
            my $mincds   = $min_exon->{'start'};
            my $maxcds   = $max_exon->{'end'};

            # Look through the rest of the CDS "exon" list to extend the CDS span
            for (my $i = 1; $i < @$cdsexons; $i++) {
                my $cdsex = $cdsexons->[$i];
                if ($cdsex->{'start'} < $mincds) {
                    $mincds   = $cdsex->{'start'};
                    $min_exon = $cdsex;
                }
                if ($cdsex->{'end'} > $maxcds) {
                    $maxcds   = $cdsex->{'end'};
                    $max_exon = $cdsex;
                }
            }

            # Get the transcript start phase from the first coding "exon"
            my $start_phase = $tsct_strand == 1 ? $min_exon->{'phase'} : $max_exon->{'phase'};

            # Make a new Translation
            my $translation = Bio::EnsEMBL::Translation->new;
            $translation->stable_id($tran->stable_id);
            $translation->version(1);

            # Add Translation to Transcript
            $tran->translation($translation);

            foreach my $ex (@{ $tran->get_all_Exons }) {
                if ($mincds >= $ex->start && $mincds <= $ex->end) {
                    if ($ex->strand == 1) {

                        # CDS start is in this exon
                        $translation->start_Exon($ex);
                        $translation->start($mincds - $ex->start + 1);
                        $ex->phase($start_phase);
                    }
                    else {

                        # CDS end is in this exon
                        $translation->end_Exon($ex);
                        $translation->end($ex->end - $mincds + 1);
                    }
                }

                if ($maxcds >= $ex->start && $maxcds <= $ex->end) {
                    if ($ex->strand == 1) {

                        # CDS end is in this exon
                        $translation->end_Exon($ex);
                        $translation->end($maxcds - $ex->start + 1);
                    }
                    else {

                        # CDS start is in this exon
                        $translation->start_Exon($ex);
                        $translation->start($ex->end - $maxcds + 1);
                        $ex->phase($start_phase);
                    }
                }
            }

            set_coding_exon_phases($tran);
        }
        else {

            # print STDERR "No CDS for $geneid $tsctid\n";
            $tran->biotype('processed_transcript');
        }

        # finished looking for a Translation

        # store the transcript:
        push @new_transcripts, $tran;
    }

    # # #
    # Make a Gene
    # # #
    my $gene = new Bio::EnsEMBL::Gene;
    $gene->analysis($analysis);
    $gene->source($info->{'source'} || 'UNK');
    $gene->status('PREDICTED');
    $gene->stable_id($geneid);
    $gene->version(1);

    # add alternate transcripts
    foreach my $tran (@new_transcripts) {
        $gene->add_Transcript($tran);
    }

    if ($gene->get_all_Transcripts) {

        # may not have transcript if pseudogene -no exons, not being stored...can i put gene on a slice?
        prune_Exons($gene);

        my $is_coding = 0;
        foreach my $t (@{ $gene->get_all_Transcripts }) {
            if ($t->translation) {
                $is_coding = 1;
                $t->translation->version(1);
            }
        }
        $gene->biotype($is_coding ? 'coding' : 'non_coding');

        return $gene;
    }
    else {
        warn $gene->stable_id . " has no exons\n";
    }
}

sub merge_overlapping_or_abutting {
    my ($feat_list) = @_;

    @$feat_list = sort { $a->{'start'} <=> $b->{'start'} || $a->{'end'} <=> $b->{'end'} } @$feat_list;

    for (my $i = 1; $i < @$feat_list;) {
        my ($A, $B) = @$feat_list[ $i - 1, $i ];

        # Do the two features overlap or abut?
        if ($A->{'end'} >= $B->{'start'} - 1 and $A->{'start'} <= $B->{'end'} + 1) {

            # Discard $B
            splice(@$feat_list, $i, 1);

            # warn "Merging features: ", Dumper($A, $B);

            # Merge coordinate span of $B into $A
            $A->{'start'} = $A->{'start'} < $B->{'start'} ? $A->{'start'} : $B->{'start'};
            $A->{'end'}   = $A->{'end'}   > $B->{'end'}   ? $A->{'end'}   : $B->{'end'};

            # Copy any keys from the $B value hash that $A doesn't have into $A
            if (my $b_val = $B->{'values'}) {
                if (my $a_val = $A->{'values'}) {
                    foreach my $name (keys %$b_val) {
                        $a_val->{$name} ||= $b_val->{$name};
                    }
                }
                else {
                    $A->{'values'} = $b_val;
                }
            }

            # warn "Merged feature: ", Dumper($A);
        }
        else {
            $i++;
        }
    }
}

# Assumes that the start and end phases on each exon have been set to -1 and
# that the start phase on the first coding exon is set to 0, 1 or 2.
sub set_coding_exon_phases {
    my ($tsct) = @_;

    my $tsl      = $tsct->translation;
    my $start_ex = $tsl->start_Exon;
    my $end_ex   = $tsl->end_Exon;

    my $in_cds = 0;
    my $phase;
    foreach my $ex (@{ $tsct->get_all_Exons }) {

        # Length of 5' and 3' UTRs in this exon
        my $utr_5_length = 0;
        my $utr_3_length = 0;

        # Is this the first coding exon?
        if ($ex == $start_ex) {
            $in_cds       = 1;
            $utr_5_length = $tsl->start - 1;

            # The start phase of the translation has been stored in the first exon
            $phase = $ex->phase;
            if ($phase == -1) {
                printf STDERR "Error: Start phase not saved on first coding exon '%s', setting phase to 0\n",
                  exon_hash_key($ex);
                $phase = 0;
            }
        }

        # Set start and end phases if this is a coding exon
        if ($in_cds) {
            $ex->phase($utr_5_length ? -1 : $phase);

            # Is this the last coding exon?
            if ($ex == $end_ex) {
                $in_cds       = 0;
                $utr_3_length = $ex->length - $tsl->end;
            }
            my $exon_cds_length = $ex->length - $utr_5_length - $utr_3_length;
            if ($exon_cds_length < 1) {
                die "Error: exon CDS length is '$exon_cds_length': ", Dumper($ex);
            }
            $phase = ($exon_cds_length + $phase) % 3;

            # Set end phase of last coding exon to -1 if there is 3' UTR
            $ex->end_phase($utr_3_length ? -1 : $phase);
        }
    }
}

sub get_value {
    my ($info_hash, $key) = @_;

    my $values_hash = $info_hash->{'values'}
      or return;
    return $values_hash->{$key};
}

sub prune_Exons {
    my ($gene) = @_;

    # keep track of all unique exons found so far to avoid making duplicates
    # need to be very careful about translation->start_exon and translation->end_Exon

    my (%stable_key, %unique_exons);

    foreach my $tran (@{ $gene->get_all_Transcripts }) {
        my (@transcript_exons);
        foreach my $exon (@{ $tran->get_all_Exons }) {
            my $key = exon_hash_key($exon);
            if (my $found = $unique_exons{$key}) {

                # Use the found exon in the translation
                if ($tran->translation) {
                    if ($exon == $tran->translation->start_Exon) {
                        $tran->translation->start_Exon($found);
                    }
                    if ($exon == $tran->translation->end_Exon) {
                        $tran->translation->end_Exon($found);
                    }
                }

                # re-use existing exon in this transcript
                $exon = $found;
            }
            else {
                $unique_exons{$key} = $exon;
            }
            push(@transcript_exons, $exon);

            # Make sure we don't have the same stable IDs
            # for different exons (different keys).
            if (my $stable = $exon->stable_id) {
                if (my $seen_key = $stable_key{$stable}) {
                    if ($seen_key ne $key) {
                        $exon->{'_stable_id'} = undef;

                        # printf STDERR "Already seen exon_id '$stable' on different exon\n";
                    }
                }
                else {
                    $stable_key{$stable} = $key;
                }
            }
        }
        $tran->flush_Exons;
        foreach my $exon (@transcript_exons) {
            $tran->add_Exon($exon);
        }
    }
}

sub exon_hash_key {
    my ($exon) = @_;

    # This assumes that all the exons we
    # compare will be on the same contig
    return join(" ", $exon->start, $exon->end, $exon->strand, $exon->phase, $exon->end_phase);
}

sub delete_all_genes_by_type {
    my ($db, $ana_name) = @_;

    my $analysis = $db->get_AnalysisAdaptor->fetch_by_logic_name($ana_name)
      or return;
    my $sth = $db->dbc->prepare(
        q{
        SELECT gene_id FROM gene WHERE analysis_id = ?
    }
    );
    $sth->execute($analysis->dbID);

    my $gene_aptr = $db->get_GeneAdaptor;
    while (my ($gene_id) = $sth->fetchrow) {
        my $gene = $gene_aptr->fetch_by_dbID($gene_id);

        # warn "Removing gene '$gene_id'";
        $gene_aptr->remove($gene);
    }
}

__DATA__
Jel_hum_qtr_solexa__20090926_0051	Jel_hum_qtr_solexa_GM12878
Jel_hum_qtr_solexa__20090926_0052	Jel_hum_qtr_solexa_K562
Jel_hum_qna_solexa_hummul_20090922_0220	Jel_hum_qna_solexa_hummul
Tho_hum_qbo_solexa_GM12878single_20090928_1350 	Tho_hum_qbo_solexa_GM12878single
Tho_hum_qbo_solexa_K562single_20090928_1349	Tho_hum_qbo_solexa_K562single
Tho_hum_qbo_solexa_K562strand_20090928_1420	Tho_hum_qbo_solexa_K562strand
Tho_hum_qbo_solexa__20090928_0918	Tho_hum_qbo_solexa_K562
Tho_hum_qbo_solexa__20090928_0919	Tho_hum_qbo_solexa_GM12878
Tho_hum_qbo_solexa_hummul_20090928_1417	Tho_hum_qbo_solexa_hummul
Tho_hum_qbo_solid_GM12878solid_20090928_1850	Tho_hum_qbo_solid_GM12878
Tho_hum_qbo_solid_K562solid_20090928_1850	Tho_hum_qbo_solid_K562
Tho_hum_qbo_helicos_K562helicos_20090923_0232	Tho_hum_qbo_helicos_K562helicos_1
Tho_hum_qbo_helicos_K562helicos_20090929_0217	Tho_hum_qbo_helicos_K562helicos_2
Tyl_hum_qbo_helicos_K562helicos_20090922_0509	Tyl_hum_qbo_helicos_K562helicos
Tyl_hum_qbo_solexa_GM12878single_20090921_2334	Tyl_hum_qbo_solexa_GM12878single_spike
Tyl_hum_qbo_solexa_GM12878single_20090922_0524	Tyl_hum_qbo_solexa_GM12878single
Tyl_hum_qbo_solexa_K562single_20090921_2314	Tyl_hum_qbo_solexa_K562single_1
Tyl_hum_qbo_solexa_K562single_20090922_0517	Tyl_hum_qbo_solexa_K562single_2
Tyl_hum_qbo_solexa_K562single_20090922_0519	Tyl_hum_qbo_solexa_K562single_3
Tyl_hum_qbo_solexa_K562strand_20090922_0541	Tyl_hum_qbo_solexa_K562strand
Tyl_hum_qbo_solexa_SRX004865_20090922_0622	Tyl_hum_qbo_solexa_SRX004865
Tyl_hum_qbo_solexa__20090921_2340	Tyl_hum_qbo_solexa_K562_spike
Tyl_hum_qbo_solexa__20090922_0530	Tyl_hum_qbo_solexa_K562_1
Tyl_hum_qbo_solexa__20090922_0531	Tyl_hum_qbo_solexa_K562_2
Tyl_hum_qbo_solexa__20090922_0534	Tyl_hum_qbo_solexa_GM12878_1
Tyl_hum_qbo_solexa__20090922_0536	Tyl_hum_qbo_solexa_GM12878_2
Tyl_hum_qbo_solid_GM12878solid_20090922_0505	Tyl_hum_qbo_solid_GM12878
Tyl_hum_qbo_solid_K562solid_20090922_0458	Tyl_hum_qbo_solid_K562
Tyl_hum_qbo_solid_K562strand_20090922_0539	Tyl_hum_qbo_solid_K562strand
Tyl_hum_qna_solexa_hummul_20091008_1644	Tyl_hum_qna_solexa_hummul_baselevel
Tyl_hum_qna_solexa_hummul_20091020_2243	Tyl_hum_qna_solexa_hummul
Tyl_hum_qbo_solexa__20090921_2346	Tyl_hum_qbo_solexa_GM12878_spike
Tyl_hum_qbo_solexa_K562single_20090921_2333	Tyl_hum_qbo_solexa_K562single_spike
Mar_hum_qbo_helicos_K562helicos_20090922_1056	Mar_hum_qbo_helicos_K562helicos
Mar_hum_qbo_solexa_GM12878single_20090921_1651	Mar_hum_qbo_solexa_GM12878single_spike
Mar_hum_qbo_solexa_GM12878single_20090922_0738	Mar_hum_qbo_solexa_GM12878single
Mar_hum_qbo_solexa_K562single_20090921_1650	Mar_hum_qbo_solexa_K562single_spike
Mar_hum_qbo_solexa_K562single_20090922_0607	Mar_hum_qbo_solexa_K562single
Mar_hum_qbo_solexa_K562strand_20090922_0038	Mar_hum_qbo_solexa_K562strand
Mar_hum_qbo_solexa__20090921_1651	Mar_hum_qbo_solexa_spike
Mar_hum_qbo_solexa__20090922_0020	Mar_hum_qbo_solexa_K562
Mar_hum_qbo_solexa__20090922_0549	Mar_hum_qbo_solexa_GM12878
Mar_hum_qbo_solid_GM12878solid_20090921_2149	Mar_hum_qbo_solid_GM12878
Mar_hum_qbo_solid_K562solid_20090921_2147	Mar_hum_qbo_solid_K562
Mar_hum_qbo_solexa_GM12878_manual_20091014	Mar_hum_qbo_solexa_GM12878_spike
Mar_hum_qna_solexa_hummul_20090921_2141	Mar_hum_qna_solexa_hummul
Mar_hum_qna_helicos_hummul_20091008_2310	Mar_hum_qna_helicos_hummul
Vic_hum_qbo_solexa__20090922_0410	Vic_hum_qbo_solexa_GM12878
Vic_hum_qtr_solexa__20090922_0752	Vic_hum_qtr_solexa_spike
Vic_hum_qna_solexa_hummul_20091009_1443	Vic_hum_qna_solexa_hummul_baselevel
Lio_hum_qtr_solexa__20090926_0118	Lio_hum_qtr_solexa_GM12878
Lio_hum_qtr_solexa__20090926_0119	Lio_hum_qtr_solexa_K562
Car_hum_qna_solexa_hummul_20091006_0307	Car_hum_qna_solexa_hummul_1
Car_hum_qna_solexa_hummul_20091006_0322	Car_hum_qna_solexa_hummul_2
Car_hum_qna_solexa_hummul_20091006_0403	Car_hum_qna_solexa_hummul_3
Chr_hum_qbo_solexa__20090917_1616	Chr_hum_qbo_solexa_GM12878_1
Chr_hum_qbo_solexa__20090918_1340	Chr_hum_qbo_solexa_GM12878_2
Chr_hum_qbo_solexa__20090918_1343	Chr_hum_qbo_solexa_GM12878_3
Chr_hum_qbo_solexa__20090918_2307	Chr_hum_qbo_solexa_K562_1
Chr_hum_qbo_solexa__20090918_2310	Chr_hum_qbo_solexa_K562_2
Chr_hum_qbo_solexa__20090919_0007	Chr_hum_qbo_solexa_K562_3
Ger_hum_qtr_solexa_hummul_20090919_2028	Ger_hum_qtr_solexa_hummul_1
Ger_hum_qtr_solexa_hummul_20090919_2031	Ger_hum_qtr_solexa_hummul_2
Jie_hum_qex_solexa_GM12878single_20090920_2255	Jie_hum_qex_solexa_GM12878single
Jie_hum_qex_solexa_K562single_20090920_2256	Jie_hum_qex_solexa_K562single
Jie_hum_qex_solexa_K562strand_20090920_2256	Jie_hum_qex_solexa_K562strand
Jie_hum_qex_solexa__20090920_2254	Jie_hum_qex_solexa_GM12878
Jie_hum_qex_solexa__20090920_2255	Jie_hum_qex_solexa_K562
Sea_hum_qex_helicos_K562helicos_20091006_0939	Sea_hum_qex_helicos_K562helicos
Sea_hum_qex_solexa_K562strand_20091006_0942	Sea_hum_qex_solexa_K562strand
Sea_hum_qex_solexa__20091006_0944	Sea_hum_qex_solexa_K562
Sea_hum_qex_solexa__20091006_0947	Sea_hum_qex_solexa_GM12878
Sea_hum_qex_solid_GM12878solid_20091006_0932	Sea_hum_qex_solid_GM12878
Sea_hum_qex_solid_K562solid_20091006_0936	Sea_hum_qex_solid_K562
Sim_hum_qtr_solexa__20090921_1624	Sim_hum_qtr_solexa_K562
Sim_hum_qtr_solexa__20090921_1628	Sim_hum_qtr_solexa_GM12878
Sim_hum_qtr_solexa_hummul_20090921_1607	Sim_hum_qtr_solexa_hummul


Jel_wor_qtr_solexa_SRX001872_20090926_0116	Jel_wor_qtr_solexa_SRX001872
Jel_wor_qtr_solexa_SRX001873_20090926_0117	Jel_wor_qtr_solexa_SRX001873
Jel_wor_qtr_solexa_SRX001874_20090926_0117	Jel_wor_qtr_solexa_SRX001874
Jel_wor_qtr_solexa_SRX001875_20090926_0116	Jel_wor_qtr_solexa_SRX001875
Jel_wor_qtr_solexa_SRX004863_20090926_0113	Jel_wor_qtr_solexa_SRX004863
Jel_wor_qtr_solexa_SRX004866_20090926_0115	Jel_wor_qtr_solexa_SRX004866
Jel_wor_qtr_solexa_SRX004867_20090926_0115	Jel_wor_qtr_solexa_SRX004867
Jel_wor_qna_solexa_wormmul_20091009_1913	Jel_wor_qna_solexa_wormmul

Tho_wor_qbo_solexa_SRX001872_20090928_0826	Tho_wor_qbo_solexa_SRX001872
Tho_wor_qbo_solexa_SRX001873_20090928_0810	Tho_wor_qbo_solexa_SRX001873
Tho_wor_qbo_solexa_SRX001874_20090928_0827	Tho_wor_qbo_solexa_SRX001874
Tho_wor_qbo_solexa_SRX001875_20090928_0826	Tho_wor_qbo_solexa_SRX001875
Tho_wor_qbo_solexa_SRX004863_20090928_0851	Tho_wor_qbo_solexa_SRX004863
Tho_wor_qbo_solexa_SRX004865_20090928_0856	Tho_wor_qbo_solexa_SRX004865
Tho_wor_qbo_solexa_SRX004867_20090928_0810	Tho_wor_qbo_solexa_SRX004867
Tho_wor_qbo_solexa_wormmul_20090928_0913	Tho_wor_qbo_solexa_wormmul

Tyl_wor_qbo_solexa_SRX001872_20090922_0403	Tyl_wor_qbo_solexa_SRX001872_1
Tyl_wor_qbo_solexa_SRX001872_20090922_0420	Tyl_wor_qbo_solexa_SRX001872_2
Tyl_wor_qbo_solexa_SRX001873_20090922_0410	Tyl_wor_qbo_solexa_SRX001873_1
Tyl_wor_qbo_solexa_SRX001873_20090922_0426	Tyl_wor_qbo_solexa_SRX001873_2
Tyl_wor_qbo_solexa_SRX001874_20090922_0424	Tyl_wor_qbo_solexa_SRX001874
Tyl_wor_qbo_solexa_SRX001875_20090922_0407	Tyl_wor_qbo_solexa_SRX001875_1
Tyl_wor_qbo_solexa_SRX001875_20090922_0422	Tyl_wor_qbo_solexa_SRX001875_2
Tyl_wor_qbo_solexa_SRX004863_20090922_0400	Tyl_wor_qbo_solexa_SRX004863_1
Tyl_wor_qbo_solexa_SRX004863_20090922_0415	Tyl_wor_qbo_solexa_SRX004863_2
Tyl_wor_qbo_solexa_SRX004865_20090922_0417	Tyl_wor_qbo_solexa_SRX004865_1
Tyl_wor_qbo_solexa_SRX004865_20090922_0624	Tyl_wor_qbo_solexa_SRX004865_2
Tyl_wor_qbo_solexa_SRX004867_20090922_0419	Tyl_wor_qbo_solexa_SRX004867
Tyl_wor_qna_solexa_SRX001874_20090922_0653	Tyl_wor_qna_solexa_SRX001874
Tyl_wor_qna_solexa_SRX004867_20090922_0650	Tyl_wor_qna_solexa_SRX004867
Tyl_wor_qna_solexa_wormmul_20090922_1032	Tyl_wor_qna_solexa_wormmul
Tyl_wor_qna_solexa_wormmul_20091008_1641	Tyl_wor_qna_solexa_wormmul_base
Tyl_hum_qbo_solexa_SRX004865_20090922_0622	Tyl_hum_qbo_solexa_SRX004865

Mar_wor_qbo_solexa_SRX001872_20090921_1054	Mar_wor_qbo_solexa_SRX001872
Mar_wor_qbo_solexa_SRX001873_20090921_1054	Mar_wor_qbo_solexa_SRX001873
Mar_wor_qbo_solexa_SRX001874_20090921_1054	Mar_wor_qbo_solexa_SRX001874
Mar_wor_qbo_solexa_SRX001875_20090921_1055	Mar_wor_qbo_solexa_SRX001875
Mar_wor_qbo_solexa_SRX004863_20090921_1052	Mar_wor_qbo_solexa_SRX004863
Mar_wor_qbo_solexa_SRX004864_20090921_1053	Mar_wor_qbo_solexa_SRX004864
Mar_wor_qbo_solexa_SRX004865_20090921_1053	Mar_wor_qbo_solexa_SRX004865
Mar_wor_qbo_solexa_SRX004866_20090921_1053	Mar_wor_qbo_solexa_SRX004866
Mar_wor_qbo_solexa_SRX004867_20090921_1053	Mar_wor_qbo_solexa_SRX004867
Mar_wor_qna_helicos_wormmul_20091008_1226	Mar_wor_qna_helicos_wormmul
Mar_wor_qna_solexa_wormmul_20090921_1049	Mar_wor_qna_solexa_wormmul

Vic_wor_qbo_solexa_SRX001872_20090922_0240	Vic_wor_qbo_solexa_SRX001872
Vic_wor_qbo_solexa_SRX001873_20090922_0243	Vic_wor_qbo_solexa_SRX001873
Vic_wor_qbo_solexa_SRX001874_20090922_0242	Vic_wor_qbo_solexa_SRX001874
Vic_wor_qbo_solexa_SRX001875_20090922_0241	Vic_wor_qbo_solexa_SRX001875
Vic_wor_qbo_solexa_SRX004867_20090922_0238	Vic_wor_qbo_solexa_SRX004867
Vic_wor_qbo_solexa_wormmul_20090922_0234	Vic_wor_qbo_solexa_wormmul_1
Vic_wor_qbo_solexa_wormmul_20090922_0236	Vic_wor_qbo_solexa_wormmul_2
Vic_wor_qna_solexa_wormmul_20090922_0227	Vic_wor_qna_solexa_wormmul_3
Vic_wor_qna_solexa_wormmul_20091009_1439	Vic_wor_qna_solexa_wormmul_base

Ger_wor_qbo_solexa_SRX001872_20090928_1451	Ger_wor_qbo_solexa_SRX001872
Ger_wor_qbo_solexa_SRX001873_20090928_1513	Ger_wor_qbo_solexa_SRX001873
Ger_wor_qbo_solexa_SRX001874_20090928_1517	Ger_wor_qbo_solexa_SRX001874
Ger_wor_qbo_solexa_SRX001875_20090928_1520	Ger_wor_qbo_solexa_SRX001875
Ger_wor_qbo_solexa_SRX004863_20090928_1524	Ger_wor_qbo_solexa_SRX004863
Ger_wor_qbo_solexa_SRX004867_20090928_1531	Ger_wor_qbo_solexa_SRX004867
Ger_wor_qbo_solexa_wormmul_20090928_1755	Ger_wor_qbo_solexa_wormmul

Gun_wor_qtr_solexa_SRX001872_20090921_1404	Gun_wor_qtr_solexa_SRX001872_1
Gun_wor_qtr_solexa_SRX001872_20090921_1445	Gun_wor_qtr_solexa_SRX001872_2
Gun_wor_qtr_solexa_SRX001872_20090921_1817	Gun_wor_qtr_solexa_SRX001872_3
Gun_wor_qtr_solexa_SRX001872_20090921_1830	Gun_wor_qtr_solexa_SRX001872_4
Gun_wor_qtr_solexa_SRX001872_20090921_1938	Gun_wor_qtr_solexa_SRX001872_5
Gun_wor_qtr_solexa_SRX001872_20091013_1554	Gun_wor_qtr_solexa_SRX001872_6
Gun_wor_qtr_solexa_SRX001872_20091014_1138	Gun_wor_qtr_solexa_SRX001872_7
Gun_wor_qtr_solexa_SRX001873_20090921_1405	Gun_wor_qtr_solexa_SRX001873_1
Gun_wor_qtr_solexa_SRX001873_20090921_1450	Gun_wor_qtr_solexa_SRX001873_2
Gun_wor_qtr_solexa_SRX001873_20090921_1818	Gun_wor_qtr_solexa_SRX001873_3
Gun_wor_qtr_solexa_SRX001873_20090921_1831	Gun_wor_qtr_solexa_SRX001873_4
Gun_wor_qtr_solexa_SRX001873_20090921_1939	Gun_wor_qtr_solexa_SRX001873_5
Gun_wor_qtr_solexa_SRX001873_20091014_1115	Gun_wor_qtr_solexa_SRX001873_6
Gun_wor_qtr_solexa_SRX001873_20091014_1140	Gun_wor_qtr_solexa_SRX001873_7
Gun_wor_qtr_solexa_SRX001874_20090921_1406	Gun_wor_qtr_solexa_SRX001874_1
Gun_wor_qtr_solexa_SRX001874_20090921_1451	Gun_wor_qtr_solexa_SRX001874_2
Gun_wor_qtr_solexa_SRX001874_20090921_1820	Gun_wor_qtr_solexa_SRX001874_3
Gun_wor_qtr_solexa_SRX001874_20090921_1832	Gun_wor_qtr_solexa_SRX001874_4
Gun_wor_qtr_solexa_SRX001874_20090921_1949	Gun_wor_qtr_solexa_SRX001874_5
Gun_wor_qtr_solexa_SRX001874_20091014_1121	Gun_wor_qtr_solexa_SRX001874_6
Gun_wor_qtr_solexa_SRX001874_20091014_1142	Gun_wor_qtr_solexa_SRX001874_7
Gun_wor_qtr_solexa_SRX001875_20090921_1406	Gun_wor_qtr_solexa_SRX001875_1
Gun_wor_qtr_solexa_SRX001875_20090921_1451	Gun_wor_qtr_solexa_SRX001875_2
Gun_wor_qtr_solexa_SRX001875_20090921_1821	Gun_wor_qtr_solexa_SRX001875_3
Gun_wor_qtr_solexa_SRX001875_20090921_1833	Gun_wor_qtr_solexa_SRX001875_4
Gun_wor_qtr_solexa_SRX001875_20090921_1952	Gun_wor_qtr_solexa_SRX001875_5
Gun_wor_qtr_solexa_SRX001875_20091014_1122	Gun_wor_qtr_solexa_SRX001875_6
Gun_wor_qtr_solexa_SRX001875_20091014_1144	Gun_wor_qtr_solexa_SRX001875_7
Gun_wor_qtr_solexa_SRX004863_20090921_1407	Gun_wor_qtr_solexa_SRX004863_1
Gun_wor_qtr_solexa_SRX004863_20090921_1452	Gun_wor_qtr_solexa_SRX004863_2
Gun_wor_qtr_solexa_SRX004863_20090921_1822	Gun_wor_qtr_solexa_SRX004863_3
Gun_wor_qtr_solexa_SRX004863_20090921_1834	Gun_wor_qtr_solexa_SRX004863_4
Gun_wor_qtr_solexa_SRX004863_20090921_1955	Gun_wor_qtr_solexa_SRX004863_5
Gun_wor_qtr_solexa_SRX004863_20091014_1127	Gun_wor_qtr_solexa_SRX004863_6
Gun_wor_qtr_solexa_SRX004863_20091014_1155	Gun_wor_qtr_solexa_SRX004863_7
Gun_wor_qtr_solexa_SRX004865_20090921_1408	Gun_wor_qtr_solexa_SRX004865_1
Gun_wor_qtr_solexa_SRX004865_20090921_1453	Gun_wor_qtr_solexa_SRX004865_2
Gun_wor_qtr_solexa_SRX004865_20090921_1824	Gun_wor_qtr_solexa_SRX004865_3
Gun_wor_qtr_solexa_SRX004865_20090921_1836	Gun_wor_qtr_solexa_SRX004865_4
Gun_wor_qtr_solexa_SRX004865_20090921_2001	Gun_wor_qtr_solexa_SRX004865_5
Gun_wor_qtr_solexa_SRX004865_20091014_1129	Gun_wor_qtr_solexa_SRX004865_6
Gun_wor_qtr_solexa_SRX004865_20091014_1159	Gun_wor_qtr_solexa_SRX004865_7
Gun_wor_qtr_solexa_SRX004867_20090921_1409	Gun_wor_qtr_solexa_SRX004867_1
Gun_wor_qtr_solexa_SRX004867_20090921_1454	Gun_wor_qtr_solexa_SRX004867_2
Gun_wor_qtr_solexa_SRX004867_20090921_1825	Gun_wor_qtr_solexa_SRX004867_3
Gun_wor_qtr_solexa_SRX004867_20090921_1840	Gun_wor_qtr_solexa_SRX004867_4
Gun_wor_qtr_solexa_SRX004867_20090921_2003	Gun_wor_qtr_solexa_SRX004867_5
Gun_wor_qtr_solexa_SRX004867_20091014_1131	Gun_wor_qtr_solexa_SRX004867_6
Gun_wor_qtr_solexa_SRX004867_20091014_1201	Gun_wor_qtr_solexa_SRX004867_7
Gun_wor_qna_solexa_wormmul_20091015_0017	Gun_wor_qna_solexa_wormmul

Wol_wor_qex_solexa_SRX004863_20090922_0832	Wol_wor_qex_solexa_SRX004863
Wol_wor_qex_solexa_SRX004865_20090922_0842	Wol_wor_qex_solexa_SRX004865
Wol_wor_qex_solexa_SRX004867_20090922_0907	Wol_wor_qex_solexa_SRX004867

Lio_wor_qna_solexa_SRX001875_20090919_1855	Lio_wor_qna_solexa_SRX001875
Lio_wor_qtr_solexa_SRX001872_20090926_0122	Lio_wor_qtr_solexa_SRX001872
Lio_wor_qtr_solexa_SRX001873_20090926_0124	Lio_wor_qtr_solexa_SRX001873
Lio_wor_qtr_solexa_SRX001874_20090926_0123	Lio_wor_qtr_solexa_SRX001874
Lio_wor_qtr_solexa_SRX001875_20090926_0123	Lio_wor_qtr_solexa_SRX001875
Lio_wor_qtr_solexa_SRX004863_20090926_0120	Lio_wor_qtr_solexa_SRX004863
Lio_wor_qtr_solexa_SRX004866_20090926_0120	Lio_wor_qtr_solexa_SRX004866
Lio_wor_qtr_solexa_SRX004867_20090926_0121	Lio_wor_qtr_solexa_SRX004867
