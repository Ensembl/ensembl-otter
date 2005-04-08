package Evi::Taxonamer;

# Find out and cache the taxon_id<->taxon_name mapping globally
#
# lg4, 6.Apr'2005

use lib "/nfs/disk100/pubseq/PerlModules/Modules/";
use SRS;

my %waiting	= ();
my %data	= ();

sub put_id {					# use this method to register the id's
	my $taxon_id = pop @_;		# can be called as Taxonamer-> or Taxonamer::

	if(not $data{$taxon_id}) {
		$waiting{$taxon_id}=1;
	}
}

sub fetch {
	my @lines = getz('-f', 'id spc', '[taxonomy-id:'.join('|', keys %waiting).']');
	while(@lines) {
		my $taxon_id = (split(/(\s*:\s*|\s*\n)/,shift @lines))[2];
		my $name	 = (split(/(\s*:\s*|\s*\n)/,shift @lines))[2];

		$data{$taxon_id} = $name;
		delete $waiting{$taxon_id};
		print "Taxonamer: found [$taxon_id] --> [$name]\n";
	}

	for my $taxon_id (keys %waiting) { # get rid of the rest just once
		$data{$taxon_id} = "TAXON-${taxon_id}";
		delete $waiting{$taxon_id};
		warn "Taxonamer: could not find taxon with ID = $taxon_id\n";
	}
}

sub get_name {					# a normal usage is Taxonamer::get_name(9606)
	my $taxon_id 	= pop @_;	# in case someone wants to use Taxonamer->get_name() notation

	put_id($taxon_id);

	if(keys %waiting) {
		fetch();
	}
	return $data{$taxon_id};
}

1;
