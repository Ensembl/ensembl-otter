#!/usr/local/bin/perl -w

## this script is used to test the truncate_to_Slice method in AnnotatedTranscript.pm 
## it creates a 4 versions of a slice, each with the start (or end) coordinate being inremented by 1 bp
## the start and end coordinates used  represnt a clone + the distance from the start of a specific translation region 
## this can be viewed in otterlace and the start / end coordinates changed to test different genes

use strict;
use Bio::Otter::DBSQL::DBAdaptor;
use Bio::EnsEMBL::DBSQL::GeneAdaptor;
#use Bio::Otter::Converter;
use Data::Dumper;

my $chr_name        =   6 ;
my $assembly_type   =   'MHC_COX' ;

# to test for start of exons getting chopped using this - remember to change fetch_slice lines also if testing the exon end being truncated
my $slice_start     =   3553325  +  2786;
my $slice_end       =   3654651   ;

# use these test for end of exons being chopped at the end - adjust the  197 value depending on the transcript tested
#my $slice_start     =   3553325   ;
#my $slice_end       =   $slice_start + 1967 ;




# connect to main otter server 
my $db = Bio::Otter::DBSQL::DBAdaptor->new(
        -user   => 'ensro',
        -dbname => 'test_otter_human',
        -host   => 'humsrv1',
        -driver => 'mysql' , 
        );

$db->assembly_type($assembly_type) ;        
my $slice_adaptor = $db->get_SliceAdaptor;
my $g_aptr        = $db->get_GeneAdaptor;

### create slice with borderline on an area we wish to test

###currently this test will only test exons being truncted by the slice start  - uncomment lines 22,23 , 54 to test the other end

my $strand;
my %transcript_hash ; 

for  (my $i = 0 ; $i < 4 ; $i++){
    
    
    # use this version to test exons that are being truncated at the exon start 
    my $slice = $slice_adaptor->fetch_by_chr_start_end($chr_name  , $slice_start + $i, $slice_end ) ;
    
    # use this version to test for exons that are being truncted at the end
    #my $slice = $slice_adaptor->fetch_by_chr_start_end($chr_name  , $slice_start     , $slice_end - $i ) ;
    
    print STDERR "\nSlice starting at :" . ( $slice_start + 1 ) ;
    print STDERR  $i ? "$slice_start \+ $i "  : "$slice_start" ;

    my $genes_list = $g_aptr->fetch_by_Slice($slice);
    print STDERR ",   found " . scalar(@$genes_list) . " genes" ;
    
    foreach my $gene (@$genes_list){
        my $transcript_list = $gene->get_all_Transcripts ;
        print STDERR "\n\t\twith  " . scalar(@$transcript_list) . " transcripts";
        print STDERR "\n\t\tids " . 
                                    join ", " , 
                                             map { $_->transcript_info->name . " " .$_->dbID }  @$transcript_list ;    
            
        
        foreach my $transcript (@$transcript_list){
           $strand = $transcript->start_Exon->strand ;

           my $sequence ;
           eval {$sequence = $transcript->translate->seq };
           unless ( $@ ){
               #$sequence = reverse $sequence  if ($strand == -1) ; 
               push @{ $transcript_hash{$transcript->transcript_info->name} } , $sequence  ; 
           }
           else {
                print STDERR "error with " . $transcript->transcript_info->name .  $@  ;
           }
        }    
    }
}

my $quit = 0 ;

print STDERR "\n\nChoose a transcript (or 'q' to end)"  ;
my @array ;
my $index = 0 ;
foreach my $name (keys %transcript_hash ){
    $index ++ ;
    push @array , $name ;  
    print STDERR "\n$index\t$name" ;
    
}
    
while ($quit != 1){

    my $input = <> ;
    warn "you chose..." . $input ;
    
    if ( ($input =~ /[q|Q]/) || ($input > scalar@array )|| ($input < 1)){
        $quit = 1;
    }else{
        my $name =  $array[$input - 1 ] ;
        my $seq_array  =  $transcript_hash{$name}  ;
        print STDERR $name  . "\n";
        my $i = -1 ;
        foreach my $seq ( @$seq_array ){
            ($i <  0 ) ?  print STDERR "original version\n" :print STDERR "\nphase : $i\n" ;
            print STDERR "$seq" ;
            $i ++ ;
        }
        warn "\n\nchoose again?";
    }
}






