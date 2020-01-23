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


### star_search.pl

use strict;
use warnings;
use Getopt::Long qw{ GetOptions };
use File::Temp qw{ tmpnam };
use Bio::EnsEMBL::DBSQL::DBAdaptor;

{
    my $usage       = sub { exec('perldoc', $0) };
    my $genome_star = '';
    my $fasta_input = '';
    my $star_output_dir = '';
    my $analysis_logic_name = '';
    my $run_flag    = 0;

    my ($db_name, $db_host, $db_port, $db_user, $db_pass);
    my @command_line = @ARGV;
    GetOptions(
        # DB connection parameters chosen to be compatible with EnsEMBL pipeline script convention
        'dbhost=s' => \$db_host,
        'dbport=s' => \$db_port,
        'dbname=s' => \$db_name,
        'dbuser=s' => \$db_user,
        'dbpass=s' => \$db_pass,

        'analysis=s'  => \$analysis_logic_name,
        'genome=s'    => \$genome_star,
        'fasta=s'     => \$fasta_input,
        'outprefix=s' => \$star_output_dir,
        'run!'        => \$run_flag,
        'h|help!'     => $usage,
    ) or $usage->();
    $usage->() unless $genome_star and $fasta_input and $analysis_logic_name and $star_output_dir;
    $star_output_dir .= "/" unless $star_output_dir =~ m{/$};

    my $db_aptr = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
        -host   => $db_host,
        -port   => $db_port,
        -dbname => $db_name,
        -user   => $db_user,
        -pass   => $db_pass,
    );

    my $dbh = $db_aptr->dbc->db_handle;
    $dbh->{AutoCommit} = 0;
    $dbh->{RaiseError} = 1;

    my $lsf_mem    = 30_000;
    my $n_threads  = 4;
    my $intron_max = 1e6;

    # Incorporating advice from this page:
    # https://github.com/PacificBiosciences/cDNA_primer/wiki/Bioinfx-study:-Optimizing-STAR-aligner-for-Iso-Seq-data

    if ($run_flag) {
        my $cmd = [
            'STARlong',
            '--runThreadN'                    => $n_threads,
            '--genomeDir'                     => $genome_star,
            '--outTmpDir'                     => scalar(tmpnam()),
            '--readFilesIn'                   => $fasta_input,
            '--alignIntronMax'                => $intron_max,
            '--outFileNamePrefix'             => $star_output_dir,

            qw{
                --outStd                         SAM
                --outSAMattributes               jM AS NM

                --seedSearchStartLmax            50
                --seedPerReadNmax                100000
                --seedPerWindowNmax              1000
                --alignWindowsPerReadNmax        30000
                --alignTranscriptsPerReadNmax    100000
                --alignTranscriptsPerWindowNmax  10000
                --winAnchorMultimapNmax          200

                --outFilterMultimapScoreRange    1
                --outFilterMultimapNmax          10000
                --outFilterScoreMinOverLread     0
                --outFilterMatchNmin             0
                --outFilterMatchNminOverLread    0
                --outFilterMismatchNmax          999
                --outFilterMismatchNoverLmax     1
                
                --scoreGapNoncan    -20
                --scoreGapGCAG      -4
                --scoreGapATAC      -8
                --scoreDelOpen      -1
                --scoreDelBase      -1
                --scoreInsOpen      -1
                --scoreInsBase      -1
            },
        ];
        
        fetch_analysis_id($dbh, $analysis_logic_name);
        fetch_chr_seq_region_ids($dbh, $genome_star);
        my $count = run_and_store($db_aptr, $cmd);
        print STDERR "Found and stored $count matches\n";
    }
    else {
        mkdir($star_output_dir) or die "Failed to create dirctory '$star_output_dir'; $!";
        my $star_v = "STAR_2.4.2a";
        $ENV{'PATH'} = "/software/svi/bin/$star_v/bin/Linux_x86_64:$ENV{PATH}";
        my @bsub = (
            'bsub',
            -q => 'normal',
            -n => $n_threads,
            -M => $lsf_mem,
            -R => "select[mem>$lsf_mem] rusage[mem=$lsf_mem] span[hosts=1]",
            -o => "$star_output_dir/$fasta_input.out",
            -e => "$star_output_dir/$fasta_input.err",
            $0, '-run', @command_line,
        );

        # print STDERR "@bsub\n";
        system(@bsub);
    }
}

sub run_and_store {
    my ($db_aptr, $cmd) = @_;

    open(my $star, '-|', @$cmd) or die "Error launching '@$cmd'; $!";
    my ($n_rows) = parse_and_store($db_aptr, $star);
    close($star) or die "Error running '@$cmd'; exit $?";
    return $n_rows;
}

{
    my $chr_to_seq_region_id = {};
    my @coord_system_id;

    sub fetch_chr_seq_region_ids {
        my ($dbh, $star_genome_dir) = @_;

        my $chr_names_file = "$star_genome_dir/chrName.txt";
        open(my $chr_names, $chr_names_file) or die "Failed to open chr names file '$chr_names_file'; $!";
        my $sth = $dbh->prepare(q{ SELECT seq_region_id, coord_system_id FROM seq_region WHERE name = ? });
        my %uniq_cs_id;
        while (my $chr = <$chr_names>) {
            chomp($chr);
            $sth->execute($chr);
            my @ids;
            while (my ($seq_region_id, $coord_system_id) = $sth->fetchrow) {
                $uniq_cs_id{$coord_system_id} = 1;
                push(@ids, $seq_region_id);
            }
            if (@ids == 1) {
                $chr_to_seq_region_id->{$chr} = $ids[0];
            }
            else {
                my $id_str = join(", ", @ids);
                die "Expecting one seq_region to match '$chr' but got: [$id_str]";
            }
        }
        close($chr_names) or die "Error reading file '$chr_names_file'; $!";
        @coord_system_id = keys(%uniq_cs_id);
    }

    sub chr_seq_region_ids {
        return $chr_to_seq_region_id;
    }
    
    sub update_meta_coord_table {
        my ($db_aptr, $max_genomic_length) = @_;

        foreach my $cs_id (@coord_system_id) {
            my $cs = $db_aptr->get_CoordSystemAdaptor->fetch_by_dbID($cs_id)
                or die "Failed to fetch CoordSystem with dbID = '$cs_id'\n";
            $db_aptr->get_MetaCoordContainer->add_feature_type($cs, 'dna_spliced_align_feature', $max_genomic_length);
        }
        $db_aptr->dbc->db_handle->commit;
    }
}

{
    my $analysis_id;

    sub fetch_analysis_id {
        my ($dbh, $analysis_logic_name) = @_;

        my $sth = $dbh->prepare(q{ SELECT analysis_id FROM analysis WHERE logic_name = ? });
        $sth->execute($analysis_logic_name);
        ($analysis_id) = $sth->fetchrow;
        $sth->finish;
        unless ($analysis_id) {
            die "Failed to fetch analysis_id for '$analysis_logic_name'";
        }
    }

    sub analysis_id {
        return $analysis_id;
    }
}

{
    my %sth_n;

    sub get_sth_for_n_rows {
        my ($dbh, $n_rows) = @_;

        my $sth;
        unless ($sth = $sth_n{$n_rows}) {
            my $sql = q{ INSERT INTO dna_spliced_align_feature (
                seq_region_id, seq_region_start, seq_region_end, seq_region_strand
              , hit_name,             hit_start,        hit_end,        hit_strand
              , analysis_id, score, perc_ident, alignment_type, alignment_string, hcoverage
              ) VALUES };
            my $values = q{(?,?,?,?,?,?,?,?,?,?,?,'vulgar_exonerate_components',?,?),} x $n_rows;
            chop($values);
            $sth = $sth_n{$n_rows} = $dbh->prepare($sql . $values);
        }
        return $sth;
    }
}

sub store_vulgar_features {
    my ($dbh, $data) = @_;

    my $sth = get_sth_for_n_rows($dbh, @$data / 13);
    $sth->execute(@$data);
    $dbh->commit;
}

sub parse_and_store {
    my ($db_aptr, $star_fh) = @_;

    my $dbh = $db_aptr->dbc->db_handle;

    my $chr_to_seq_region_id = chr_seq_region_ids();
    my $analysis_id = analysis_id();

    my $data = [];
    my $hit_count = 0;
    my $max_genomic_length = 0;
    my $chunk_size = 1000;
    while (<$star_fh>) {
        next if /^@/;
        $hit_count++;
        chomp;
        my ($hit_name
          , $binary_flags
          , $chr_name
          , $chr_start
          , $map_quality
          , $cigar
          , $rnext
          , $pnext
          , $tlen
          , $hit_sequence
          , $hit_quality
          , @optional_flags
        ) = split /\t/, $_;

        my $chr_db_id = $chr_to_seq_region_id->{$chr_name} or die "No seq_region_id for chr '$chr_name'";

        # Parse the optional flags
        my ($chr_strand, $score, $edit_distance);
        foreach my $attr (@optional_flags) {
            my ($FG, $type, $value) = split /:/, $attr;
            if ($FG eq 'jM') {
                my @splices = $value =~ /,(-?\d+)/g;
                my $strand_vote = 0;
                foreach my $n (@splices) {
                    next unless $n > 0; # Value of 0 signifies non-consensus splice; -1 no splice sites.
                    # Odd numbers are forward strand splice sites, even are reverse
                    $strand_vote += $n % 2 ? 1 : -1;
                }

                if ($strand_vote == 0) {
                    # No splice info, so we don't know which genomic strand we're on
                    $chr_strand = 0;
                }
                elsif ($strand_vote > 1) {
                    $chr_strand = 1;
                }
                else {
                    $chr_strand = -1;
                }
            }
            elsif ($FG eq 'AS') {
                $score = $value;
            }
            elsif ($FG eq 'NM') {
                $edit_distance = $value;
            }
        }

        my $flipped_hit = $binary_flags & 16;
        my ($hit_strand);
        if ($chr_strand == 0) {
            # No information about chr strand from splice sites
            $hit_strand = 1;
            $chr_strand = $flipped_hit ? -1 : 1;
        }
        else {
            # A flipped hit to a reverse strand gene is a match to the forward strand of the hit
            $hit_strand = $chr_strand * ($flipped_hit ? -1 : 1);
        }

        my @cigar_fields = $cigar =~ /(\d+)(\D)/g;
        if ($chr_strand == -1) {
            # Reverse the CIGAR, keeping the pairs of OP + INT together.
            my $limit = @cigar_fields - 2;  # Last pair would be a no-op
            for (my $i = 0; $i < $limit; $i += 2) {
                splice(@cigar_fields, $i, 0, splice(@cigar_fields, -2, 2));
            }
        }

        my @vulgar_fields;
        my $hit_start      = 1;
        my $hit_aln_length = 0;
        my $chr_aln_length = 0;
        my $hit_pad_length = 0; # Needed for percent identity
        my $hit_del_length = 0; # Needed for hit coverage
        my $hit_length = length($hit_sequence);
        for (my $i = 0; $i < @cigar_fields; $i += 2) {
            my ($len, $op) = @cigar_fields[ $i, $i + 1 ];
            if ($op eq 'M') {
                push @vulgar_fields, 'M', $len, $len;
                $chr_aln_length += $len;
                $hit_aln_length += $len;
            }
            elsif ($op eq 'N') {
                push @vulgar_fields, 5, 0, 2, 'I', 0, $len - 4, 3, 0, 2;
                $chr_aln_length += $len;
            }
            elsif ($op eq 'I') {
                push @vulgar_fields, 'G', $len, 0;
                $hit_aln_length += $len;
                $hit_del_length += $len;    # Will not contribute to hcoverage
            }
            elsif ($op eq 'D') {
                push @vulgar_fields, 'G', 0, $len;
                $chr_aln_length += $len;
                $hit_pad_length += $len;    # Will add to span of alignment
            }
            elsif ($op eq 'S') {
                # Soft clipping - clipped sequence is present in SAM
                if ($i == 0) {
                    $hit_start += $len;
                }
            }
            elsif ($op eq 'H') {
                # Hard clipping - clipped sequence not present in SAM
                $hit_length += $len;
            }
            else {
                die "Unexpected SAM CIGAR element: '$len$op'";
            }
        }
        my $hit_end = $hit_start + $hit_aln_length - 1;
        my $chr_end = $chr_start + $chr_aln_length - 1;

        # The total span of the gapped alignment (not including introns) minus the edit distance
        my $percent_identity = sprintf "%.3f", 100 * (1 - ($edit_distance / ($hit_pad_length + $hit_aln_length)));
        
        my $hit_coverage     = sprintf "%.3f", 100 * (($hit_aln_length - $hit_del_length) / $hit_length);

        if ($hit_strand == -1) {
            my $new_hit_start = $hit_length - $hit_end   + 1;
            $hit_end          = $hit_length - $hit_start + 1;
            $hit_start = $new_hit_start;
        }

        push(@$data,
            $chr_db_id, $chr_start, $chr_end, $chr_strand,
            $hit_name,  $hit_start, $hit_end, $hit_strand,
            $analysis_id, $score, $percent_identity, "@vulgar_fields", $hit_coverage);

        # my $pattern = "%18s  %-s\n";
        # print STDERR "\n";
        # printf STDERR $pattern, 'seq_region_start',  $offset + $chr_start;
        # printf STDERR $pattern, 'seq_region_end',    $offset + $chr_end;
        # printf STDERR $pattern, 'seq_region_strand', $chr_strand;
        # printf STDERR $pattern, 'hit_start',         $hit_start;
        # printf STDERR $pattern, 'hit_end',           $hit_end;
        # printf STDERR $pattern, 'hit_strand',        $hit_strand;
        # printf STDERR $pattern, 'hit_name',          $hit_name;
        # printf STDERR $pattern, 'perc_ident',        $percent_identity;
        # printf STDERR $pattern, 'hcoverage',         $hit_coverage;
        # printf STDERR $pattern, 'alignment_string',  "@vulgar_fields";

        # print STDERR join("\t", $chr_name, $chr_strand, $hit_name, $hit_start, $hit_end, $hit_strand, "@vulgar_fields"), "\n";
        
        my $genomic_length = $chr_end - $chr_start + 1;
        if ($genomic_length > $max_genomic_length) {
            $max_genomic_length = $genomic_length;
        }
        
        unless ($hit_count % $chunk_size) {
            store_vulgar_features($dbh, $data);
            $data = [];
        }
    }
    if (@$data) {
        store_vulgar_features($dbh, $data);
        $data = [];
    }
    
    update_meta_coord_table($db_aptr, $max_genomic_length);
    return $hit_count;
}


__END__

=head1 NAME - star_search.pl

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

