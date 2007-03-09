## Vega module for comparison of two objects, gene vs gene, transcript vs transcript, translation vs translation and exon vs exon

package Bio::Vega::Utils::Comparator;

use strict;
use warnings;
use base 'Exporter';
our @EXPORT_OK = qw{ compare };

use Bio::EnsEMBL::Utils::Exception qw(throw);

sub compare{
  my ($obj1,$obj2) = @_;
  my $changed=0;
  ##sanity checks
  unless ($obj1 && $obj2){
	 if ($obj1){
		print STDERR "\nobj1 to be compared:".$obj1->stable_id." key:".$obj1->hashkey;
	 }
	 if ($obj2){
		print STDERR "\nobj2 to be compared:".$obj2->stable_id." key:".$obj2->hashkey;
	 }
	 throw("Need two objects to compare \n Only one object set");
  }
  if ( ref($obj1) ne ref($obj2)) {
	 throw("Cannot compare two different types of objects. Objects should be of the same class $obj1 vs $obj2\n");
  }
  my $class = ref($obj1);
  unless ( $class->isa('Bio::EnsEMBL::Exon') || $class->isa('Bio::Vega::Gene') || $class->isa('Bio::Vega::Transcript') || $class->isa('Bio::Vega::Translation') || $class->isa('Bio::Vega::ContigInfo') ) {
	 throw('objects to be compared should be either Bio::Vega::Gene or Bio::EnsEMBL::Exon or Bio::Vega::Translation or Bio::Vega::Transcript or Bio::Vega::ContigInfo' );
  }

  ##do actual comparisons
  my $obj1_hash_key=$obj1->hashkey;
  my $obj2_hash_key=$obj2->hashkey;
  ##This main key comparison saves a lot of time and space
  ##compare main keys only if main key is same then sub keys are compared
  if ($obj1_hash_key eq $obj2_hash_key) {
	 ##Exon doesn't have a hash_sub_key, so for others
	 if ($class ne 'Bio::EnsEMBL::Exon'){
		my $obj1_hash_sub = $obj1->hashkey_sub;
		my $obj2_hash_sub = $obj2->hashkey_sub;
		my $e_count=0;
		foreach (keys %$obj1_hash_sub){
		  unless (exists $obj2_hash_sub->{$_}){
			 $e_count++;
			 if ($e_count == 1) {
				print STDERR "*Changes observed\n";
			 }
			 if (!$class->isa('Bio::Vega::ContigInfo')) {
				print STDERR $obj1->stable_id.".".$obj1->version." now has changed or new attrib $_  \n";
			 }
			 else {
				print STDERR $obj1->slice->name." contig info now has changed or new attrib $_  \n";
			 }

		  }
		}
		if ($e_count > 0) {
		  $changed=1;
		}	
	 }
  }
  else {
	 $changed=1;
#	 my $obj2version;
	# if (defined $obj2->version) {
		#$obj2version=$obj2->version;
	 #}
	 #else {
		#$obj2version='';
	 #}
	 print STDERR "*Changes observed\n";
	 if ($class->isa('Bio::Vega::ContigInfo')) {
		print STDERR "ContigInfo has changed due to change in main key \nBefore-key:$obj1_hash_key\nAfter-key :$obj2_hash_key\n";
	 }
	 else {
		print STDERR $obj1->stable_id.".".$obj1->version." now has changed main key \n";
		if ($class->isa('Bio::Vega::Gene')) {
		  print STDERR "slice_name-start-end-strand-biotype-status-source-genename-description-transcript_count-attrib_count\n";
		}
		elsif ($class->isa('Bio::Vega::Transcript')){
		  print STDERR "slice_name-start-end-strand-biotype-status-exon_count-transcriptname-mRNAstartNF-mRNAendNF-cDNAstartNF-cDNAendNF-description-evidence_count-attrib_count\n";
		}
		elsif ($class->isa('Bio::Vega::Translation')){
		 print STDERR "start_exon_hash_key-end_exon_hash_key-tl_start-tl_end\n";
		}
		elsif ($class->isa('Bio::EnsEMBL::Exon')){
		  print STDERR "slice_name-start-end-strand-phase-end_phase\n";
		}
		print STDERR "Before-key:$obj1_hash_key\nAfter-key :$obj2_hash_key\n";
	 }
  }
  return $changed;
}

1;
