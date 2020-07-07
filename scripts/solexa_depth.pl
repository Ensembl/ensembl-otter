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

my $log_analysis = $aa->fetch_by_logic_name('solexa_summary_log');
my $analysis = $aa->fetch_by_logic_name('solexa_summary');

my $sfa = $result_dba->get_SimpleFeatureAdaptor;

my $sa = $dba->get_SliceAdaptor;

my $slice = $sa->fetch_by_region('chromosome',1,537730,587318,-1);

my @afs;

for my $ana (qw(37bp_14dpf_ga 37bp_1dpf_ga 37bp_28dpf_ga 37bp_2dpf_ga 37bp_3dpf_ga 37bp_5dpf_ga)) {
    push @afs, @{ $slice->get_all_DnaAlignFeatures($ana) };
}

#die "num afs: ".scalar(@$afs)."\n";

my %depth;

for my $af (@afs) {
    my @fs = $af->ungapped_features;
    for my $f (@fs) {
        #if ($f->start > 1 and $f->end < $slice->length) {
            for (my $i = $f->start; $i < $f->end; $i++) {
                $depth{$i}++;    
            }
        #}
    }
}

my ($start, $end, $tot_depth);

my $i = 0;

for my $b (sort { $a <=> $b } keys %depth) {
    
    if (!$start) {
        $start = $b;
        $end = $b;
    }
    elsif ($b != $end+1) {
        # end this feature
      
        my $sf = Bio::EnsEMBL::SimpleFeature->new(
            -start         => $start,
            -end           => $end+1,
            -strand        => 1,
            -slice         => $slice,
            -analysis      => $log_analysis,
            -score         => log(($tot_depth / ($end - $start))+1),
            -display_label => 'solexa_summary_feature_'.$i++,
        );
        
        $sfa->store($sf);
        
        print "New feature: $start - $end\n";
        
        $start = $b;
        $end = $b;
        $tot_depth = 0;
    }
    else {
        $end++;
        $tot_depth += $depth{$b};
    }
}

