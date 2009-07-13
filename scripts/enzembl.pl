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

# this regex defines the delimiter for options which can take multiple values
my $CFG_DELIM = qr/[\s,;]+/;

# globals

my %feature_types;
my %dbs;
my %regions;
my $start;
my $end;

# command line/config file options

my $help;
my $verbose;
my $port;
my $pass;
my $host;
my $user;
my $dbname;
my $analyses;
my $types;
my $region;
my $coords;
my $styles_file;
my $create_missing_styles;
my $zmap_exe;
my $zmap_config_file;
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
	'create_styles',\$create_missing_styles,
	'types:s',		\$types,
	'cfg:s',		\$cfg_file,
	'zmap:s',		\$zmap_exe,
	'zmap_cfg:s',	\$zmap_config_file,
	'h|help',		\$help,
	'v|verbose',	\$verbose,
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
	
	$dbs{$dbname}->{analyses} = [ split $CFG_DELIM, $analyses ];
}

if ($region) {
	my ($cs, $id) = split /:/, $region;
	$regions{$id} = $cs;
}

if ($types) {
	%feature_types = map { $_ => {} } split $CFG_DELIM, $types;
}

if ($coords) {
	($start, $end) = split /-/, $coords;	
}

# read the config file

if (-e $cfg_file) {
	my $cfg = new Config::IniFiles( -file => $cfg_file ) 
		or die "'$cfg_file' doesn't look like a valid enzembl config file\n";
	
	if ($cfg->SectionExists('enzembl')) {
		
		# the following settings are all 'unless'ed so that command line options 
		# override config file settings
		
		unless ($dbname) {
			die "No database specified!\n" unless $cfg->val('enzembl','dbs');
			
			for my $db (split $CFG_DELIM, $cfg->val('enzembl','dbs')) {
				
				my $dbh = new Bio::EnsEMBL::DBSQL::DBAdaptor(
					-host 	=> $cfg->val($db,'host'),
					-user 	=> $cfg->val($db,'user'),
					-pass 	=> $cfg->val($db,'pass') || '',
					-port 	=> $cfg->val($db,'port'),
					-dbname	=> $db,
					-driver	=> 'mysql'
				);
				
				$dbs{$db}->{dbh} = $dbh;
				
				die "No analyses supplied for db: $db!\n" unless $cfg->val($db,'analyses');
				
				$dbs{$db}->{analyses} ||= [];
				
				push @{ $dbs{$db}->{analyses} }, split $CFG_DELIM, $cfg->val($db,'analyses');
			}
		}
		
		unless (%regions) {
			die "No region supplied!\n" unless $cfg->val('enzembl','region');
			
			my ($cs, $id) = split /:/, $cfg->val('enzembl','region');
			$regions{$id} = $cs;
		}
		
		unless (defined $start && defined $end) {
			($start, $end) = split /-/, $cfg->val('enzembl','coords') if $cfg->val('enzembl','coords');
		}
		
		unless (%feature_types) {
			die "You must supply at least one feature type!\n" unless $cfg->val('enzembl','feature-types');
			
			for my $type (split $CFG_DELIM, $cfg->val('enzembl','feature-types')) {
				$feature_types{$type} = {};
			}
		}
		
		# look up settings for the type seperately so that the user can supply types on the 
		# command line but leave settings in the config file
		for my $type (keys %feature_types) {
			if ($cfg->SectionExists($type)) {
				$feature_types{$type}->{parent_style} = $cfg->val($type,'parent-style');
				$feature_types{$type}->{colours} = [
					split $CFG_DELIM, $cfg->val($type,'colours')
				];
			}
		}
		
		$zmap_exe = $cfg->val('enzembl','zmap') unless $zmap_exe;
		$zmap_config_file = $cfg->val('enzembl','zmap-config') unless $zmap_config_file;
		$styles_file = $cfg->val('enzembl','stylesfile') unless $styles_file;
		$create_missing_styles = $cfg->val('enzembl','create-missing-styles') unless defined $create_missing_styles;
	}
	else {
		die "Invalid config file: $cfg_file (no [enzembl] stanza)\n";
	}
}

# make sure we have everything we need

die "No zmap executable supplied!\n" unless $zmap_exe;
die "No zmap config supplied!\n" unless $zmap_config_file;
die "No styles file supplied!\n" unless $styles_file;

# ensure all paths are absolute

$zmap_exe = abs_path($zmap_exe);
$zmap_config_file = abs_path($zmap_config_file);
$styles_file = abs_path($styles_file);

# pull the data from each of the databases

my $gff;
my %sources_to_types;
my $sequence_name;

for my $db (keys %dbs) {

	my $dbh = $dbs{$db}->{dbh};

	my $analysis_adaptor = $dbh->get_AnalysisAdaptor;
	my $slice_adaptor = $dbh->get_SliceAdaptor;
	
	my @analyses = @{ $dbs{$db}->{analyses} };
	
	for my $region (keys %regions) {
	
		# get a slice for each region
		
		my $coord_system = $regions{$region};
		
		my $slice = $slice_adaptor->fetch_by_region($coord_system, $region, $start, $end);
		
		die "Failed to fetch slice for region: $coord_system:$region ".
			($start && $end ? "$start-$end" : '')."\n" unless $slice;
		
		unless ($gff) {
			# add a gff header if this is the first entry, including DNA
			$gff = Bio::Vega::Utils::EnsEMBL2GFF::gff_header(slice => $slice, include_dna => 1);
			
			# save a sequence name to give to zmap later
			$sequence_name = $slice->seq_region_name;
		}
		
		for my $feature_type (keys %feature_types) {
			
			# grab features of each type we're interested in
			
			my $method = 'get_all_'.$feature_type;
			
			die "There is no method to retrieve $feature_type from a slice\n" unless $slice->can($method);
			
			for my $analysis (@analyses) {
				my $features = $slice->$method($analysis);
				
				if ($verbose && scalar(@$features)) {
					print "Found ".scalar(@$features)." ".$feature_type." from $analysis in $db\n";
				}
				
				for my $feature (@$features) {
					if ( $feature->can('to_gff') ) {
						
						# add the gff of this feature
						
						$gff .= $feature->to_gff . "\n";
	
						# and store the gff 'source' name of this feature
	
						my $source = $feature->_gff_hash->{source};
						
						if ($sources_to_types{$source}) {
							unless ($sources_to_types{$source} eq $feature_type) {
								die "Can't have multiple gff sources from one analysis:\n".
									"('$analysis' seems to have both '".$sources_to_types{$source}.
									"' and '$feature_type')\n";
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

# create the styles file

my $styles_cfg = new Config::IniFiles( -file => $styles_file ) 
	or die "Failed to read styles file: $styles_file\n";
	
my %provided_styles = map { $_ => 1 } $styles_cfg->Sections;
	
my $styles_list = join (';', keys %provided_styles);
	
if ($create_missing_styles) {
	
	# create a style for each source which doesn't have one
	
	for my $source (keys %sources_to_types) {
		
		# skip if there is a style already defined for this source
		next if $styles_cfg->SectionExists($source);
		
		my $type = $sources_to_types{$source};
		
		my $type_settings = $feature_types{$type};
		
		die "No parent-style provided for type: $type\n" unless $type_settings->{parent_style};
		die "No colours provided for type: $type\n" unless defined $type_settings->{colours};
		
		$styles_cfg->AddSection($source);
		
		$styles_cfg->newval(
			$source, 
			'parent-style', 
			$type_settings->{parent_style}
		);
		
		my $colour = shift @{ $type_settings->{colours} };
	
		die "Run out of colours for type: $type\n" unless $colour;
		
		$styles_cfg->newval(
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
	
	$styles_cfg->WriteConfig($styles_file) or die "Failed to write styles file: $styles_file\n";
	
	$styles_list = join (';', $styles_cfg->Sections);
}
else {
	# check that there is a style for every source
	
	my @missing = grep { ! $provided_styles{$_} } keys %sources_to_types;
	
	die "No style defined for the following sources in styles file: $styles_file:\n".
		join("\n", @missing)."\n" if @missing;
}

# write out the gff file

my ($gff_fh, $gff_filename) = tempfile(
	'enzembl_gff_data_XXXXXX', 
	SUFFIX => '.gff', 
	UNLINK => 1, 
	DIR => '/tmp'
);

print $gff_fh $gff;

# build up ZMap file

my $sources_list = 'DNA;'.join(';', keys %sources_to_types); # always include DNA

# zmap needs to know whether each source is dna, protein or a transcript to use blixem 
# correctly, so we try to guess the correct type here

my $dna_sources = join (';', 
	grep { $sources_to_types{$_} =~ /dna/i } keys %sources_to_types
);

my $protein_sources = join (';',
	grep { $sources_to_types{$_} =~ /protein/i } keys %sources_to_types
);

my $tsct_sources = join (';',
	grep { $sources_to_types{$_} =~ /gene|transcript/i } keys %sources_to_types
);

my $zmap_cfg = new Config::IniFiles( -file => $zmap_config_file );

$zmap_cfg->newval('ZMap', 'default-sequence', $sequence_name);
$zmap_cfg->newval('source', 'url','file://'.$gff_filename);
$zmap_cfg->newval('source', 'featuresets', $sources_list);
$zmap_cfg->newval('source', 'styles', $styles_list);
$zmap_cfg->newval('source', 'stylesfile', $styles_file);
$zmap_cfg->newval('blixem', 'dna-featuresets', $dna_sources);
$zmap_cfg->newval('blixem', 'protein-featuresets', $protein_sources);
$zmap_cfg->newval('blixem', 'transcript-featuresets', $tsct_sources);

my $zmap_dir = tempdir(
	'enzembl_zmap_XXXXXX', 
	DIR => '/tmp', 
	CLEANUP => 1
);

$zmap_cfg->WriteConfig($zmap_dir.'/ZMap') or die "Failed to write zmap config file\n";

# and run zmap...

!system($zmap_exe, "--conf_dir", $zmap_dir) or die "Failed to run $zmap_exe\n";

__END__
	
=head1 NAME 

enzembl 

=head1 SYNOPSIS

Connect to EnsEMBL schema databases and show features directly in ZMap.

=head1 EXAMPLE COMMAND LINES

assuming you've specified some style settings and a zmap executable in your config file
(see below for details):

  enzembl -region clone:AC068644.15 -analyses Halfwise,vertrna -types Genes,DnaAlignFeatures\ 
          -db pipe_human -host otterpipe1 -port 3302 -user ottro

or with databases and types specified in the config file:

  enzembl -region chromosome:chr14-03 -coords 1000-2000 -analyses Est2genome_human

=head1 OPTIONS

B<NB:> All of these settings can also be set in the config file. Command line options override config file settings.

=over 4

=item B<-cfg FILE>

Read configuration from the specified file (defaults to ~/.enzembl_config). See below for
an example file.

=item B<-region coord_system:identifier>

Grab features from the specified region, e.g. clone:AC068644.15, chromosome:15 etc.
Must be supplied here or in the config file

=item B<-coords start-end>

Limit search to specified coordinates (defaults to entire region).

=item B<-analyses logic_name1,logic_name2,...>

Grab features created by these analyses. Must be supplied here or in the config file.

=item B<-types type_name1,type_name2,...>

Only look for features of these types (== EnsEMBL feature classes). Must be supplied here or in the config file.

=item B<-styles FILE>

Use provided zmap styles file.

=item B<-create_styles>

Automatically create a style for features from each feature type found. The parent style and
some colours to use to differentiate features of the same type from different analyses can be
specified in the config file (see below for examples).

=item B<-zmap /path/to/zmap>

Use this zmap executable. Must be supplied here or in the config file.

=item B<-zmap_cfg FILE>

Use the given file as the ZMap configuration file (normally found in ~/.ZMap/ZMap). Note that 
this script automatically fills in the parameters shown below, if you specify any of these in 
this file they will be ignored. All other settings are passed unaltered to zmap. See below for 
a working example file.

 stanza		parameters set by this script
 ------------------------------------------------------------------------
 [ZMap]		default-sequence
 [source]	url, featuresets, styles, stylesfile
 [blixem]	dna-featuresets, protein-featuresets, transcript-featuresets

=item B<-db DATABASE -host HOST -port PORT -user USER -pass PASSWORD>

Grab features from this (ensembl schema) database. Multiple databases can be specified 
in the config file, although no mapping between coordinate systems is (yet) supported, 
so all features must lie in the same coordinate space. Must be supplied here or in the 
config file.

=item B<-v | -verbose>

Produce verbose output.

=item B<-h | -help>

Print these usage instructions.

=head1 EXAMPLE CONFIG FILE

If supplied, should look something like this:

 [enzembl]
 dbs = loutre_human, pipe_human
 zmap = /software/anacode/otter/otter_production_main/bin/zmap
 zmap-config = /nfs/team71/analysis/gr5/.enzembl/ZMap
 feature-types = DnaAlignFeatures,ProteinAlignFeatures,Genes,SimpleFeatures,RepeatFeatures,PredictionTranscripts
 stylesfile = /nfs/team71/analysis/gr5/.enzembl/basic_styles.ini
 create-missing-styles = 1

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

 [DnaAlignFeatures]
 parent-style = dna_align
 colours = CornflowerBlue,SkyBlue,SteelBlue,LightSteelBlue,NavyBlue

 [ProteinAlignFeatures]
 parent-style = pep_align
 colours = OrangeRed2,tomato1,red3,DeepPink4,HotPink3

 [Genes]
 parent-style = tsct
 colours = MediumAquamarine,DarkSeaGreen,PaleGreen,chartreuse,OliveDrab

 [SimpleFeatures]
 parent-style = feat
 colours = LightGoldenRod1,yellow1,LightYellow1,khaki3,gold3

 [RepeatFeatures]
 parent-style = repeat
 colours = plum1,plum2,plum3,plum4,purple3

 [PredictionTranscripts]
 parent-style = predicted_tsct
 colours = gray20,gray40,gray60,gray80,gray90
 
=head1 EXAMPLE STYLES FILE

A corresponding basic styles file to use is:
 
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

=head1 EXAMPLE ZMAP CONFIG FILE

 [ZMap]
 show-mainwindow = true
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
 sequence = true
 navigator-sets = scale

 [blixem]
 script = /software/anacode/otter/otter_production_main/bin/blixemh
 config-file = /nfs/team71/analysis/gr5/.enzembl/blixemrc
 homol-max = 0
 scope = 200000
 
=head1 EXAMPLE BLIXEMRC

 [blixem]
 default_fetch_mode = pfetch_socket

 [pfetch_socket]
 pfetch_mode = socket
 port = 22400
 node = 172.18.62.3

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk





