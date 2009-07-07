#!/usr/local/bin/perl

# enzembl - connect to ensembl schema databases and show features directly in zmap

use strict;
use warnings;

use Getopt::Long;
use File::Temp qw(tempfile tempdir);
use Config::IniFiles;
use Cwd qw(abs_path);
use File::HomeDir qw(my_home);

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::Vega::Utils::EnsEMBL2GFF;

my $CFG_DELIM = qr/[\s,;]+/;

# define a default styles file and blixemrc here so we can edit 
# all settings from the same file

my $STYLES_FILE =<<STYLES;
[root]
width=9
default-bump-mode=overlap
colours=selected fill gold ; normal border black
bump-mode=unbump
bump-spacing=4

[align]
default-bump-mode=name-colinear
parent-style=root
mode=alignment
alignment-pfetchable=true
alignment-parse-gaps=true
alignment-align-gaps=true

[dna_align]
parent-style=align
max-score=100
colours=normal border MidnightBlue
min-score=70
score-mode=width
alignment-blixem=blixem-n
alignment-within-error=0
alignment-between-error=0

[pep_align]
frame-mode=always
parent-style=align
show-reverse-strand=true
colours=normal border firebrick4
max-score=100
min-score=70
score-mode=percent
alignment-blixem=blixem-x
alignment-within-error=0
alignment-between-error=3

[repeat]
max-mag=1000
colours=normal border purple4
parent-style=align
max-score=400
min-score=50
score-mode=width

[tsct]
width=7
mode=transcript
colours=normal border DarkGreen
transcript-cds-colours = normal fill white ; normal border DarkOliveGreen ; selected fill gold
parent-style=root
bump-mode=overlap

[feat]
colours=normal border DarkKhaki
parent-style=root
mode=basic
bump-mode=unbump

[predicted_tsct]
width=5
max-mag=1000
parent-style=tsct
colours=normal border purple4
STYLES

my $BLIXEMRC =<<BLIXEMRC;
[blixem]
default_fetch_mode = pfetch_socket

[pfetch_socket]
pfetch_mode = socket
port = 22400
node = 172.18.62.3
BLIXEMRC

# Map the kinds of features we're interested in to root styles and specify 
# some colours to use to draw them. These colours will be used for each source
# of the same type in turn, and we will die if we run out of colours! These
# settings will be overriden by any user supplied styles file.

my %FEATURE_TYPES = (
	DnaAlignFeatures => {
		root_style	=> 'dna_align', 
		colours 	=> [qw(CornflowerBlue SkyBlue SteelBlue LightSteelBlue NavyBlue)],
	},
	ProteinAlignFeatures => {
		root_style	=> 'pep_align',
		colours 	=> [qw(OrangeRed2 tomato1 red3 DeepPink4 HotPink3)]
	},
	Genes => {
		root_style 	=> 'tsct',
		colours		=> [qw(MediumAquamarine DarkSeaGreen PaleGreen chartreuse OliveDrab)]
	},
	SimpleFeatures => {
		root_style	=> 'feat',
		colours		=> [qw(LightGoldenRod1 yellow1 LightYellow1 khaki3 gold3)]
	},
	RepeatFeatures => {
		root_style 	=> 'repeat',
		colours		=> [qw(plum1 plum2 plum3 plum4 purple3)]
	},
	PredictionTranscripts => {
		root_style 	=> 'predicted_tsct',
		colours		=> [qw(gray20 gray40 gray60 gray80 gray90)]
	},
);

# globals

my %dbs;
my %regions;
my $start;
my $end;

# command line options

my $help;
my $port;
my $pass;
my $host;
my $user;
my $dbname;
my $analyses;
my $region;
my $coords;
my $styles_file;
my $zmap_exe;
my $blixem_exe;
my $cfg_file = my_home.'/.enzembl_config';

my $usage = sub { exec('perldoc', $0) };

# parse the command line options

GetOptions(	
	'port:s',		\$port,
	'pass:s',		\$pass,
	'host:s',		\$host,
	'user:s',		\$user,
	'db:s',  		\$dbname,
	'analyses:s',	\$analyses,
	'region:s', 	\$region,
	'coords:s', 	\$coords,
	'styles:s',		\$styles_file,
	'cfg:s',		\$cfg_file,
	'zmap:s',		\$zmap_exe,
	'blixem:s',		\$blixem_exe,
	'h|help',		\$help,
) or $usage->();

$usage->() if $help;

if ($dbname) {
	
	my $dbh = new Bio::EnsEMBL::DBSQL::DBAdaptor(
		-host 	=> $host,
		-user 	=> $user,
		-pass 	=> $pass,
		-port 	=> $port,
		-dbname	=> $dbname,
		-driver	=> 'mysql'
	);
	
	$dbs{$dbname}->{dbh} = $dbh;
	
	$dbs{$dbname}->{analyses} = [ split($CFG_DELIM, $analyses) ];
}

if ($region) {
	my ($cs, $id) = split /:/, $region;
	$regions{$id} = $cs;	

#	for my $region (split($CFG_DELIM, $regions)) {
#		my ($cs, $id) = split /:/, $region;
#		$regions{$id} = $cs;
#	}

}

# read the config file

if (-e $cfg_file) {
	my $cfg = new Config::IniFiles( -file => $cfg_file ) 
		or die "'$cfg_file' doesn't look like a valid enzembl config file\n";
	
	if ($cfg->SectionExists('enzembl')) {
		
		for my $db (split($CFG_DELIM, $cfg->val('enzembl','dbs'))) {
			
			my $dbh = new Bio::EnsEMBL::DBSQL::DBAdaptor(
				-host 	=> $cfg->val($db,'host'),
				-user 	=> $cfg->val($db,'user'),
				-pass 	=> $cfg->val($db,'pass') || '',
				-port 	=> $cfg->val($db,'port'),
				-dbname	=> $db,
				-driver	=> 'mysql'
			);
			
			$dbs{$db}->{dbh} = $dbh;
			
			die "No analyses supplied for db: $db\n" unless $cfg->val($db,'analyses');
			
			$dbs{$db}->{analyses} ||= [];
			
			push @{ $dbs{$db}->{analyses} }, split($CFG_DELIM, $cfg->val($db,'analyses'));
		}
		
		# the following settings are all 'unless'ed so that command line options 
		# override config file options
		
		unless (%regions) {
			
			die "No region supplied!\n" unless $cfg->val('enzembl','region');
			
			my ($cs, $id) = split /:/, $cfg->val('enzembl','region');
			$regions{$id} = $cs;
			
#			for my $region (split($CFG_DELIM, $cfg->val('enzembl','regions'))) {
#				my ($cs, $id) = split /:/, $region;
#				$regions{$id} = $cs;
#			}
		
		}
		
		unless (defined $start && defined $end) {
			($start, $end) = split /-/, $cfg->val('enzembl','coords') if $cfg->val('enzembl','coords');
		}
		
		$zmap_exe = $cfg->val('enzembl','zmap') unless $zmap_exe;
		$blixem_exe = $cfg->val('enzembl','blixem') unless $blixem_exe;
		$styles_file = $cfg->val('enzembl','styles') unless $styles_file;
	}
	else {
		die "Invalid config file: $cfg_file (no [enzembl] stanza)\n";
	}
}

$zmap_exe = abs_path($zmap_exe);
$blixem_exe = abs_path($blixem_exe);

# pull the data from each of the databases

my $gff = '';
my %sources_to_types = ();
my $sequence_name;

for my $db (keys %dbs) {

	my $dbh = $dbs{$db}->{dbh};

	my $analysis_adaptor = $dbh->get_AnalysisAdaptor();
	my $slice_adaptor = $dbh->get_SliceAdaptor();
	
	my @analyses = @{ $dbs{$db}->{analyses} };
	
#	unless (@analyses) {		
#		my %analysis_hash = ();
#		my $i = 1;
#	
#		for my $analysis (@{ $analysis_adaptor->fetch_all }) {
#			$analysis_hash{$i} = $analysis;
#			print "($i) ",$analysis->logic_name, "\n";
#			$i++;
#		}
#		
#		print "Please select analyses from the list above: ";
#		my @analyses_nums = split /\s/, <STDIN>;
#		@analyses = map { $analysis_hash{$_}->logic_name } @analyses_nums;
#	}
	
	for my $region (keys %regions) {
	
		# get a slice for each region
		
		my $slice = $slice_adaptor->fetch_by_region($regions{$region}, $region, $start, $end);
		
		die "Failed to fetch slice" unless $slice;
		
		unless ($gff) {
			
			# add a gff header if this is the first entry
			
			$gff = Bio::Vega::Utils::EnsEMBL2GFF::gff_header($slice, 1);
			$sequence_name = $slice->seq_region_name;
		}
		
		for my $feature_type (keys %FEATURE_TYPES) {
			
			# grab features of each type we're interested in
			
			my $method = 'get_all_'.$feature_type;
			for my $analysis (@analyses) {
				my $features = $slice->$method($analysis);
				for my $feature (@{ $features }) {
					if ( $feature->can('to_gff') ) {
						
						# add the gff of this feature
						
						$gff .= $feature->to_gff . "\n";
	
						# and store the gff 'source' name of this feature
	
						my $source = $feature->_gff_hash->{source};
						
						if ($sources_to_types{$source}) {
							unless ($sources_to_types{$source} eq $feature_type) {
								die "Can't have multiple gff sources from one analysis:\n".
									"('$analysis' seems to have both '".$sources_to_types{$source}.
									"' and '$feature_type')";
							}
						}
						else { 
							$sources_to_types{$source} = $feature_type;
						}
					}
					else {
						warn "no to_gff method in $feature_type";
					}
				}
			}
		}
	}
}

# build up zmap configuration and styles files

my $sources_list = join(';', keys %sources_to_types);

my $dna_sources = join (';', 
	grep { $sources_to_types{$_} eq 'DnaAlignFeatures' } keys %sources_to_types
);

my $protein_sources = join (';',
	grep { $sources_to_types{$_} eq 'ProteinAlignFeatures' } keys %sources_to_types
);

my $tsct_sources = join (';',
	grep { $sources_to_types{$_} =~ /Genes|PredictionTranscripts/ } keys %sources_to_types
);

my $styles_list;

if ($styles_file) {
	
	# the user supplied a styles file
	
	$styles_file = abs_path($styles_file);
	
	my $styles = new Config::IniFiles( -file => $styles_file );
	
	my %provided_styles = map { $_ => 1 } $styles->Sections;
	
	$styles_list = join (';', keys %provided_styles);
	
	# check that there is a style for every source
	
	my @missing = grep { ! $provided_styles{$_} } keys %sources_to_types;
	
	die "No style defined for the following sources in styles file: $styles_file:\n".
		join("\n", @missing)."\n" if @missing;
}
else {
	
	# build up a styles file to use
	
	my $styles = new Config::IniFiles( -file => \$STYLES_FILE );
	
	for my $source (keys %sources_to_types) {
		
		$styles->AddSection($source);
		
		$styles->newval(
			$source, 
			'parent-style', 
			$FEATURE_TYPES{$sources_to_types{$source}}->{root_style}
		);
		
		my $colour = shift @{ $FEATURE_TYPES{$sources_to_types{$source}}->{colours} };
	
		die "Run out of colours for type: ".$sources_to_types{$source} unless $colour;
		
		$styles->newval(
			$source, 
			'colours', 
			"normal fill $colour"
		);
	}
		
	my $styles_fh;
	
	($styles_fh, $styles_file) = tempfile(
		'enzembl_styles_XXXXXX', 
		SUFFIX => '.ini', 
		UNLINK => 1, 
		DIR => '/tmp'
	);
	
	$styles->WriteConfig($styles_file) or die "Failed to write styles file";
	
	$styles_list = join (';', $styles->Sections);
}

my $zmap_dir = tempdir(
	'enzembl_zmap_XXXXXX', 
	DIR => '/tmp', 
	CLEANUP => 1
);

my ($gff_fh, $gff_filename) = tempfile(
	'enzembl_gff_data_XXXXXX', 
	SUFFIX => '.gff', 
	UNLINK => 1, 
	DIR => '/tmp'
);

my ($blixemrc_fh, $blixemrc) = tempfile(
	'enzembl_blixemrc_XXXXXX',  
	UNLINK => 1, 
	DIR => '/tmp'
);

open(my $zmap_fh, ">$zmap_dir/ZMap");

my $ZMAP = <<ZMAP;
[ZMap]
show-mainwindow = true
default-sequence = $sequence_name
pfetch-mode = pipe
pfetch = pfetch

[ZMapWindow]
canvas-maxsize = 10000
feature-spacing = 4.0
colour-frame-1 = #e6ffe6
colour-item-highlight = gold
colour-column-highlight = CornSilk
colour-frame-2 = #e6e6ff
colour-frame-0 = #ffe6e6
feature-line-width = 1

[logging]
logging = true
show-code = false

[source]
url = file://$gff_filename
featuresets = DNA;$sources_list
styles = $styles_list
stylesfile = $styles_file
sequence = true
navigator-sets = scale

[blixem]
script = $blixem_exe
dna-featuresets = $dna_sources
protein-featuresets = $protein_sources
config-file = $blixemrc
transcript-featuresets = $tsct_sources
homol-max = 0
scope = 200000
ZMAP

# write out the config files

print $zmap_fh $ZMAP;
print $blixemrc_fh $BLIXEMRC;
print $gff_fh $gff;

# and run zmap...

system($zmap_exe, "--conf_dir", $zmap_dir);

__END__
	
=head1 NAME 

enzembl 

=head1 SYNOPSIS

connect to EnsEMBL schema databases and show features directly in ZMap, 
e.g. (assuming you've specified some databases in your config file):

  enzembl -region clone:AC068644.15 -analyses vertrna,Halfwise

=head1 OPTIONS

=over 4

=item B<-cfg FILE>

Read configuration from the specified file (defaults to ~/.enzembl_config).

=item B<-region coord_system:identifier>

Grab features from the specified region, e.g. clone:AC068644.15, chromosome:15 etc. 
Must be supplied here or in the config file

=item B<-coords start-end>

Limit search to specified coordinates (defaults to entire region)

=item B<-analyses logic_name1,logic_name2,...>

Grab features created by these analyses. (Must be supplied here or in the config file.)

=item B<-styles FILE>

Use provided zmap styles file (otherwise one will be created for you).

=item B<-zmap /path/to/zmap>

Use this zmap executable. Must be supplied here or in the config file.

=item B<-blixem /path/to/blixemh>

Use this blixem executable. 
Should be supplied here or in the config file if you want blixem to work.

=item B<-db DATABASE -host HOST -port PORT -user USER -pass PASSWORD>

Grab features from this (ensembl schema) database. Multiple databases can be specifed 
in the config file, although no mapping between coordinate systems is (yet) supported, 
so all features must lie in the same coordinate space. Must be supplied here or in the 
config file.

=head1 CONFIG FILE

 If supplied, should look something like this:

 [enzembl]
 dbs = loutre_human, pipe_human
 zmap = /software/anacode/otter/otter_production_main/bin/zmap
 blixem = /software/anacode/otter/otter_production_main/bin/blixemh 
 
 [loutre_human]
 host = otterlive
 port = 3301
 user = ottro
 analyses = Otter
 
 [pipe_human]
 host = otterpipe1
 port = 3302
 user = ottro
 analyses = vertrna
 
=head1 NB

Command line options override config file settings.

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk





