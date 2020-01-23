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


use strict;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::SeqIO;
use Getopt::Long;

my $dbhost    = 'ensdb-web-17';
my $dbuser    = 'ensro';
my $dbname    = 'vega_danio_rerio_20151019_82_GRCz10';
my $dbpass    = undef;
my $dbport    = 5317;
my $stable_id;
my $db_id;
my $file;
my $genetype;

GetOptions(
	   'dbhost=s'    => \$dbhost,
	   'dbname=s'    => \$dbname,
	   'dbuser=s'    => \$dbuser,
	   'dbpass=s'    => \$dbpass,
	   'dbport=s'    => \$dbport,
	   'stable_id!' => \$stable_id,
	   'db_id!' => \$db_id,
	   'file=s' => \$file,
	  )or die ("Couldn't get options");

my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
					    '-host'   => $dbhost,
					    '-user'   => $dbuser,
					    '-dbname' => $dbname,
					    '-pass'   => $dbpass,
					    '-port'   => $dbport,
					   );


print STDERR "connected to $dbname : $dbhost\n";

my $fh;
#print STDERR "have file ".$file."\n" if($file);
if($file){
    open (FH, '>'.$file) or die "couldn't open file ".$file." $!";
    $fh = \*FH;
}
else{
    $fh = \*STDOUT;
}



my $seqio = Bio::SeqIO->new('-format' => 'Fasta' , -fh => $fh ) ;
my $slice_adaptor = $db->get_SliceAdaptor();

foreach my $gene_id(@{$db->get_GeneAdaptor->list_dbIDs}) {
    eval {
        my $gene = $db->get_GeneAdaptor->fetch_by_dbID($gene_id);
        my $gene_id = $gene->dbID();
        my $gene_stable_id = $gene->stable_id;
        my $gene_version = $gene->version;
        
        my $slice = $slice_adaptor->fetch_by_region($gene->slice->coord_system->name,
                                                    $gene->slice->seq_region_name,
                                                    $gene->start,
                                                    $gene->end,
                                                    undef,
                                                    $gene->slice->coord_system->version);
        my $components = $slice->project('clone');
        my @clones;
        foreach my $comp (@$components) {
            push @clones, $comp->to_Slice->seq_region_name;
        }
        my $clone = join ",", @clones;
                                                    
        foreach my $trans ( @{$gene->get_all_Transcripts}) {
            my $identifier = $trans->stable_id;
            my $version    = $trans->version;
	    my $tseq       = $trans->seq;
	    my $seq        = $tseq->seq;
            my $protid;
            if ($trans->translation()) {
                $protid = $trans->translation()->stable_id;
            }
            else {
                $protid = "no translation";
            }
	    $tseq->seq($seq);
	    $tseq->display_id($identifier);
	    
            $tseq->desc("name ".$trans->external_name." version $version transcript_type ".$trans->biotype." protein_id $protid gene_id $gene_stable_id name ".$gene->external_name." version $gene_version gene_type ".$gene->biotype." gene_status ".$gene->status." clone $clone\n");
	    $seqio->write_seq($tseq);
        }
    };

  
    if( $@ ) {
        print STDERR "unable to process $gene_id, due to \n$@\n";
    }
}

close($fh);
