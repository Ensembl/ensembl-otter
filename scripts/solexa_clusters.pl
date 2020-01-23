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

use strict;
use warnings;

use Data::Dumper;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::SimpleFeature;

my $dba = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
    -host   => 'genebuild4.internal.sanger.ac.uk',
    -port   => 3306,
    -user   => 'ensro',
    -dbname => 'sw4_danio_solexa_genome_align_53',
);

my $result_dba = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
    -host   => 'otterpipe2',
    -port   => 3323,
    -user   => 'ottadmin',
    -pass   => '**********',
    -dbname => 'gr5_zebrafish_solexa',
);
BEGIN { die "Broken - needs password" }

my $aa = $result_dba->get_AnalysisAdaptor;

my $analysis = $aa->fetch_by_logic_name('solexa_non_redundant');

my $afa = $result_dba->get_DnaAlignFeatureAdaptor;

my $sa = $dba->get_SliceAdaptor;

my $slice = $sa->fetch_by_region('chromosome',1,537730,587318,-1);

my @afs;

#for my $ana (qw(37bp_14dpf_ga 37bp_1dpf_ga 37bp_28dpf_ga 37bp_2dpf_ga 37bp_3dpf_ga 37bp_5dpf_ga)) {
#for my $ana (qw(37bp_2dpf_ga)) {
#    push @afs, @{ $slice->get_all_DnaAlignFeatures($ana) };
#}

@afs = @{ $slice->get_all_DnaAlignFeatures };

#die "num afs: ".scalar(@$afs)."\n";

my @clusters;

@afs = sort {
    ( $a->seq_region_start <=> $b->seq_region_start )
    || ( $a->seq_region_end <=> $b->seq_region_end )
} @afs;

my $VERBOSE = 0;

for my $af (@afs) {
    
    my @fs = $af->ungapped_features;
    
    next unless @fs > 1;
    
    print "Feature: " if $VERBOSE;
    print_feature($af) if $VERBOSE;
    
    my $added = 0;
    
    for my $cluster (@clusters) {
        
        if (consistent($af, $cluster)) {
            
            print "Adding to cluster: " if $VERBOSE;
            print_cluster($cluster) if $VERBOSE;
            
            push @{ $cluster->{fs} }, $af;
            
            if ($fs[0]->seq_region_start < $cluster->{f1_start}) {
                die "Should never happen!";
            }
            
            if ($fs[0]->seq_region_end > $cluster->{f1_end}) {
                $cluster->{f1_end} = $fs[0]->seq_region_end;
                print "Extending f1 end\n" if $VERBOSE;
            }
            
            if ($fs[1]->seq_region_start < $cluster->{f2_start}) {
                $cluster->{f2_start} = $fs[1]->seq_region_start;
                print "Extending f2 start\n" if $VERBOSE;
            }
            
            if ($fs[1]->seq_region_end > $cluster->{f2_end}) {
                $cluster->{f2_end} = $fs[1]->seq_region_end;
                print "Extending f2 end\n" if $VERBOSE;
            }
            
            print "Cluster now: " if $VERBOSE;
            print_cluster($cluster) if $VERBOSE;
            
            $added = 1;
            last;
        }
    }
    
    unless ($added) {
        my $c = {
            f1_start    => $fs[0]->seq_region_start, 
            f1_end      => $fs[0]->seq_region_end,
            f2_start    => $fs[1]->seq_region_start,
            f2_end      => $fs[1]->seq_region_end,
            fs          => [$af]
        };
        
        print "New cluster: " if $VERBOSE;
        print_cluster($c) if $VERBOSE;
                
        push @clusters, $c;
    }
}

print "Found ".scalar(@clusters)." clusters\n";

#my @to_keep;

#print "Reduced ".scalar(@afs)." to ".scalar(@to_keep)."\n";

#map { $afa->store($_) } @to_keep;

my $cluster_num = 0;

for my $c (@clusters) {
    
    my $len = $c->{f2_end} - $c->{f1_start} + 1;
    
    my $cigar = $len.'M';
    
    my $insert = $c->{f2_start} - $c->{f1_end};
    
    if ($insert > 0) {
        my $f1_len = $c->{f1_end} - $c->{f1_start} + 1;
        my $f2_len = $c->{f2_end} - $c->{f2_start} + 1;
        
        $cigar = $f1_len.'M'.$insert.'I'.$f2_len.'M';
    }
    
    my $af = new Bio::EnsEMBL::DnaDnaAlignFeature(
        -slice        => $slice->seq_region_Slice,
        -start        => $c->{f1_start},
        -end          => $c->{f2_end},
        -strand       => 1,
        -hseqname     => 'cluster'.$cluster_num++,
        -hstart       => 1,
        -hstrand      => 1,
        -hend         => $len,
        -analysis     => $analysis,
        -cigar_string => $cigar,
        -score        => scalar(@{$c->{fs}}),
    );

    $afa->store($af);
}

sub consistent {
    my ($f, $c) = @_;
    
    my @fs = $f->ungapped_features;
    
    return (overlap($fs[0]->seq_region_start, $fs[0]->seq_region_end, $c->{f1_start}, $c->{f1_end})) &&
        (overlap($fs[1]->seq_region_start, $fs[1]->seq_region_end, $c->{f2_start}, $c->{f2_end}));
}

sub overlap {
    # check if feature f1 overlaps feature f2

    my ( $f1_start, $f1_end, $f2_start, $f2_end ) = @_;
    
    return ($f1_end >= $f2_start and $f1_start <= $f2_end);
}

sub print_cluster {
    my $c = shift;
    print $c->{f1_start}.'-'.$c->{f1_end}.'_'.$c->{f2_start}.'-'.$c->{f2_end}.' ['.scalar(@{$c->{fs}})."]\n";
}

sub print_feature {
    my $f = shift;
    my @fs = $f->ungapped_features;
    print $fs[0]->seq_region_start.'-'.$fs[0]->seq_region_end.'_'.$fs[1]->seq_region_start.'-'.$fs[1]->seq_region_end."\n";
}
