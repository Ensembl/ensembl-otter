# Vega module for comparison of two objects, gene vs gene, transcript vs transcript, translation vs translation and exon vs exon

package Bio::Vega::Utils::Comparator;

use strict;
use warnings;
use base 'Exporter';
our @EXPORT_OK = qw{ compare };

use Bio::EnsEMBL::Utils::Exception qw(throw);

sub compare{
  my ($obj1,$obj2) = @_;

  my $changed=0;

  unless ($obj1 && $obj2){
	 throw('Need two objects to compare\n Only one object set');
  }

  if ( ref($obj1) ne ref($obj2)) {
	 throw("Cannot compare two different types of objects. Objects should be of the same class $obj1 vs $obj2\n");
  }
  my $class = ref($obj1);
  
  unless ( $class->isa('Bio::EnsEMBL::Exon') || $class->isa('Bio::Vega::Gene') || $class->isa('Bio::Vega::Transcript') || $class->isa('Bio::Vega::Translation') || $class->isa('Bio::Vega::ContigInfo') ) {
	 throw('objects to be compared should be either Bio::Vega::Gene or Bio::EnsEMBL::Exon or Bio::Vega::Translation or Bio::Vega::Transcript or Bio::Vega::ContigInfo' );
  }
  my $obj1_hash_key=$obj1->hashkey;
  my $obj2_hash_key=$obj2->hashkey;

  if ($obj1_hash_key eq $obj2_hash_key) {

	 if ($class ne 'Bio::EnsEMBL::Exon'){
		my $obj1_hash_sub = $obj1->hashkey_sub;
		my $obj2_hash_sub    = $obj2->hashkey_sub;
		my $e_count=0;
		foreach (keys %$obj1_hash_sub){
		  $e_count++ unless exists $obj2_hash_sub->{$_};
		  print STDERR "\nchanged or new attrib $_ in ".$obj1->stable_id."\n" unless exists $obj2_hash_sub->{$_};
		}
		if ($e_count > 0) {
		  $changed=1;
		}	
	 }
  }
  else {
	 $changed=1;
	 print STDERR "\nFrom comparator object changed due to change in main key: obj1 stable".$obj1->stable_id."--".$obj1->version." obj2 stable:".$obj2->stable_id."--version:".$obj2->version."\n".ref($obj1)."\nBefore key:$obj1_hash_key\n".ref($obj2)."\nAfter  key:$obj2_hash_key";
  }
  return $changed;

}



1;
