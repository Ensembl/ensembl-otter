package Slice;

use strict;
use warnings;
use Data::Dumper;

=head2 get_wanted_chromosomes

  Arg[1]      : B::E::U::ConversionSupport
  Arg[2]      : B::E::SliceAdaptor
  Arg[3]      : B::E::AttributeAdaptor
  Arg[4]      : string $coord_system_name (optional) - 'chromosome' by default
  Arg[5]      : string $coord_system_version (optional) - 'otter' by default
  Example     : @chr_names = &Slice::get_wanted_chromosomes($support,$laa,$lsa);
  Description : retrieve names of slices from a lutra database that are ready for dumping to Vega
  Return type : arrayref
  Caller      : general
  Status      : stable

=cut

sub get_wanted_chromosomes {
	my $support = shift;
	my $aa      = shift or throw("You must supply an attribute adaptor");
	my $sa      = shift or throw("You must supply a slice adaptor");
	my $cs = shift || 'chromosome';
	my $cv = shift || 'Otter';
	my $export_mode = $support->param('release_type');
	my $release = $support->param('vega_release');
	my $names;
	my $chroms  = &fetch_non_hidden_slices($support,$aa,$sa,$cs,$cv);
 CHROM:
	foreach my $chrom (@$chroms) {
		my $attribs = $aa->fetch_all_by_Slice($chrom);
		my $vals = $support->get_attrib_values($attribs,'vega_export_mod');
		if (scalar(@$vals > 1)) {
			$support->log_warning ("Multiple attribs for \'vega_export_mod\', please fix before continuing");
			exit;
		}
		next CHROM if (! grep { $_ eq $export_mode} @$vals);
		$vals =  $support->get_attrib_values($attribs,'vega_release',$release);	
		if (scalar(@$vals > 1)) {
			$support->log_warning ("Multiple attribs for \'vega_release\' value = $release , please fix before continuing");
			exit;
		}
		next CHROM if (! grep { $_ eq $release} @$vals);
		my $name = $chrom->seq_region_name;
		if (my @ignored = $support->param('ignore_chr')) {
			next CHROM if (grep {$_ eq $name} @ignored);
		}
		push @{$names}, $name;
	}
	return $names;
}


=head2 fetch_non_hidden_slices

  Arg[1]      : B::E::U::ConversionSupport
  Arg[2]      : B::E::SliceAdaptor
  Arg[2]      : B::E::AttributeAdaptor
  Arg[3]      : string $coord_system_name (optional) - 'chromosome' by default
  Arg[4]      : string $coord_system_version (optional) - 'otter' by default
  Example     : $chroms = $support->fetch_non_hidden_slice($sa,$aa);
  Description : retrieve all slices from a lutra database that don't have a hidden attribute
  Return type : arrayref
  Caller      : general
  Status      : stable

=cut

sub fetch_non_hidden_slices {
	my $support = shift;
	my $aa   = shift or throw("You must supply an attribute adaptor");
	my $sa   = shift or throw("You must supply a slice adaptor");
	my $cs = shift || 'chromosome';
	my $cv = shift || 'Otter';
	my $visible_chroms;
	foreach my $chrom ( @{$sa->fetch_all($cs,$cv)} ) {
		my $attribs = $aa->fetch_all_by_Slice($chrom);
		push @$visible_chroms, $chrom if @{$support->get_attrib_values($attribs,'hidden','N')};
	}
	return $visible_chroms;
}


1;
