#!/usr/bin/env perl

# enzembl - connect to EnsEMBL schema databases and show features directly in ZMap

use strict;
use warnings;

use Getopt::Long;
use File::Temp qw(tempfile tempdir);
use Config::IniFiles;
use Cwd qw(abs_path);
use File::HomeDir qw(my_home);
use Pod::Usage;
use List::Util qw(shuffle);
use Try::Tiny;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::Vega::Utils::EnsEMBL2GFF;
use Bio::EnsEMBL::Utils::Exception qw(verbose);

my $STABLE_ID_REGEX = qr/^[A-Z]{3}([A-Z]{3})?([GTE])[\d]+$/;

my $STABLE_ID_PREFIXES = {
    G   => 'gene',
    T   => 'transcript',
    E   => 'exon',
};

# this regex defines the delimiter for options which can take multiple values
my $CFG_DELIM = qr/[\s,;]+/;

# this regex defines the delimiter for options with multiple parts
my $PART_DELIM = qr/:/;

# globals

my @feature_types;
my @analyses;
my %feature_type_settings;
my %dbs;
my @dbnames;
my %regions;
my %features;

# command line/config file options

my $verbose;
my $persist;
my $port;
my $pass;
my $host;
my $user;
my $dbname;
my $flank = 100;
my $styles_file;
my $create_missing_styles;
my $zmap_exe;
my $zmap_config_file;
my $cfg_file = my_home.'/.enzembl_config';

my $usage = sub { exec('perldoc', $0) };

my $requested_region = {};
my $common_region = {};

# subroutines

sub dbh_from_cfg {
    my ( $cfg, $db ) = @_;

    return $cfg->val($db, "species")
        ? dbh_from_registry($cfg, $db)
        : dbh_from_db($cfg, $db);
}

sub dbh_from_registry {
    my ( $cfg, $db ) = @_;

    Bio::EnsEMBL::Registry->load_registry_from_db(
        -db_version => 56,

        -host   => $cfg->val($db,'host'),
        -user   => $cfg->val($db,'user'),
        -pass   => $cfg->val($db,'pass') || '',
        -port   => $cfg->val($db,'port'),
        -driver => 'mysql',
        );

    my $species = $cfg->val($db,'species');
    my $sa = Bio::EnsEMBL::Registry->get_adaptor($species, 'core', 'slice');
    my $dbh = $sa->db;

    return $dbh;
}

sub dbh_from_db {
    my ( $cfg, $db ) = @_;

    return Bio::EnsEMBL::DBSQL::DBAdaptor->new(
        -host   => $cfg->val($db,'host'),
        -user   => $cfg->val($db,'user'),
        -pass   => $cfg->val($db,'pass') || '',
        -port   => $cfg->val($db,'port'),
        -dbname => $db,
        -driver => 'mysql',
        );
}

# parse the command line options

GetOptions(
        'db|dbs:s',     \$dbname,
        'port:s',               \$port,
        'pass:s',               \$pass,
        'host:s',               \$host,
        'user:s',               \$user,
        'cfg:s',        \$cfg_file,
        'analyses:s',   sub { @analyses = split $CFG_DELIM, $_[1] },
        'region:s',     sub { 
            my @parts = split $PART_DELIM, $_[1];
            $requested_region->{cs_name} = $parts[0];
            $requested_region->{cs_version} = $parts[1];
            $requested_region->{name} = $parts[2];
            $requested_region->{start} = $parts[3];
            $requested_region->{end} = $parts[4];
            $requested_region->{strand} = $parts[5];
        },
        'features:s',   sub { 
            my ($t, $id) = split $PART_DELIM, $_[1];
            if ($t =~ $STABLE_ID_REGEX) {
                $features{$t} = $STABLE_ID_PREFIXES->{$2};
            }
            elsif ($id) {
               $features{$id} = $t;
            }
            else {
                die "I don't know what type of feature $t is, try gene:$t or transcript:$t etc.\n";
            } 
        },
        'flank:s',      \$flank,
        'styles:s',             \$styles_file,
        'create_styles',\$create_missing_styles,
        'types:s',              sub { @feature_types = split $CFG_DELIM, $_[1] },
        'zmap:s',               \$zmap_exe,
        'zmap_cfg:s',   \$zmap_config_file,
        'verbose|v',    \$verbose,
        'persist|p',    \$persist,
        'help|h',               sub { exec('perldoc', $0) },
) or pod2usage(1);

if ($dbname && $user) {
        
        die "Can only supply settings for one database from the command line (try using a config file)\n" 
                if $dbname =~ /$CFG_DELIM/;
        
        my $dbh = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
                -host   => $host,
                -user   => $user,
                -pass   => $pass,
                -port   => $port,
                -dbname => $dbname,
                -driver => 'mysql'
        );
        
        $dbs{$dbname}->{dbh} = $dbh;
        
        $dbs{$dbname}->{analyses} = \@analyses;
}
elsif ($dbname) {
        @dbnames = split $CFG_DELIM, $dbname;
}

# read the config file

if (-e $cfg_file) {
        my $cfg = Config::IniFiles->new( -file => $cfg_file ) 
                or die "'$cfg_file' doesn't look like a valid enzembl config file\n";
        
        if ($cfg->SectionExists('enzembl')) {
                
                # the following settings are all 'unless'ed so that command line options 
                # override config file settings
                
                unless (@feature_types) {
                        if ($cfg->val('enzembl','feature-types')) {
                                @feature_types = split $CFG_DELIM, $cfg->val('enzembl','feature-types');
                        }
                }
                
                unless (@analyses) {
                        if ($cfg->val('enzembl','analyses')) {
                                @analyses = split $CFG_DELIM, $cfg->val('enzembl','analyses');
                        }
                }
                
                unless ($dbname) {
                        die "No databases specified!\n" unless $cfg->val('enzembl','dbs');
                        @dbnames = split $CFG_DELIM, $cfg->val('enzembl','dbs');
                }
                
                for my $db (@dbnames) {
                                
                        die "Can't find any settings for $db in $cfg_file\n" unless $cfg->val($db,'user');
                        
                        $dbs{$db}->{dbh} = dbh_from_cfg($cfg, $db);
                        
                        # command line AND [enzembl] stanza settings override database specific settings
                        # i.e. if the user supplies global analyses and feature types (in the [enzembl]
                        # stanza or on the command line), these will be searched for in all databases and
                        # database specific settings (in the [db_name] stanza) will be ignored
                        
                        if (@analyses) {
                                $dbs{$db}->{analyses} = \@analyses;
                        }
                        else {
                                # we do not require analyses to be specified
                                # - if they are not then to_gff will look for
                                # all analyses
                                my $analyses = $cfg->val($db,'analyses');
                                $dbs{$db}->{analyses} = [ split $CFG_DELIM, $analyses ] if $analyses;
                        }
                        
                        if (@feature_types) {
                                $dbs{$db}->{feature_types} = \@feature_types;
                        }
                        else {
                                die "No feature types supplied for $db\n" unless $cfg->val($db,'feature-types');
                                $dbs{$db}->{feature_types} = [ split $CFG_DELIM, $cfg->val($db,'feature-types') ];
                        }
                        
                        # note the name of all feature_types
                        
                        $feature_type_settings{$_} ||= {} for @{ $dbs{$db}->{feature_types} };
                }
                
                unless (keys %$requested_region || %features) {
                        die "No region supplied!\n" unless $cfg->val('enzembl','region');
                        
                        my ($cs, $id) = split $PART_DELIM, $cfg->val('enzembl','region');
        
                        $regions{$id} = $cs;
                }
                
                # look up settings for the feature types separately so that the user can supply types 
                # on the command line but leave settings in the config file
        for my $type (keys %feature_type_settings, @feature_types) {
            if ($cfg->SectionExists($type)) {
                $feature_type_settings{$type} ||= {};
                        $feature_type_settings{$type}->{parent_style} = $cfg->val($type,'parent-style');
                        $feature_type_settings{$type}->{colours} = [
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

if (%features) {
    
    # try to find a slice which contains the supplied feature(s)
    
    DBS : for my $db (keys %dbs) {
        
        my $dbh = $dbs{$db}->{dbh};
    
        my $slice_adaptor = $dbh->get_SliceAdaptor;
        
        for my $feature (keys %features) {
            
            my $type = $features{$feature};
            
            my $method = 'fetch_by_'.$type.'_stable_id';
            
            if ($slice_adaptor->can($method)) {
                
                my $slice = try {
                    return $slice_adaptor->$method($feature, $flank);
                };
                
                if ($slice) {
                    
                    my $cs = $slice->coord_system_name;
                    my $region = $slice->seq_region_name;
                                  
                    $requested_region->{cs_name} = $slice->coord_system->name;
                    $requested_region->{cs_version} = $slice->coord_system->version;
                    $requested_region->{name} = $slice->seq_region_name;
                    $requested_region->{start} = $slice->start;
                    $requested_region->{end} = $slice->end;
                    $requested_region->{strand} = $slice->strand;
                    
                    print "Found slice for feature: ".$slice->name."\n" if $verbose;
                    
                    last DBS;
                }
            }
            else {
                die "There doesn't seem to be a method $method on SliceAdaptors";
            }
        }
    }
    
    die "Failed to find a region for supplied features\n" unless keys %$requested_region;
}

# pull the data from each of the databases

my $gff_header;
my $gff;
my %sources_to_types;
my $sequence_name;

# first try to find a coordinate system that all dbs support

my %coord_systems;
my $delim = '---';

my $all_have_requested = 1;
my $db_with_requested;
my $mapper_db;

for my $db (keys %dbs) {
    
    my $dbh = $dbs{$db}->{dbh};
    my $csa = $dbh->get_CoordSystemAdaptor;
    my $css = $csa->fetch_all;
    
    my $has_requested = 0;
    
    for my $cs (@$css) {
        my $key = $cs->name.$delim.$cs->version;
        #print "$db has $key\n";
        $coord_systems{$key} ||= {};
        $coord_systems{$key}->{cs} = $cs;
        push @{ $coord_systems{$key}->{dbs} }, $db;
    
        if ($cs->name eq $requested_region->{cs_name} && $cs->version eq $requested_region->{cs_version}) {
            $requested_region->{cs} ||= $cs;
            $has_requested = 1;
            $db_with_requested = $db;
        }
    }
    
    $all_have_requested = 0 unless $has_requested;
}

my $target_slice;
my $common_slice;

unless ($db_with_requested) {
    die "None of the supplied databases support the requested coordinate system: ".
        $requested_region->{cs_name}.":".$requested_region->{cs_version}."\n"; 
}

unless ($all_have_requested) {
    
    print "Not all databases support the requested coordinate system: ".
        $requested_region->{cs}->name.":".$requested_region->{cs}->version, ", searching for common one...\n" if $verbose;
    
    my $found = 0;
    
    SEARCH : for my $cs (keys %coord_systems) {
        
        my @supporting_dbs = @{ $coord_systems{$cs}->{dbs} };
        
        if (@supporting_dbs == keys %dbs) {
            
            my $coord_sys = $coord_systems{$cs}->{cs};
            
            print "Found common coordinate system: ".$coord_sys->name.":".$coord_sys->version."\n" if $verbose;
            
            $found = 1;
            
            $common_region->{cs} = $coord_sys;
            
            for my $db (keys %dbs) {
                my $dbh = $dbs{$db}->{dbh};
                my $asma = $dbh->get_AssemblyMapperAdaptor;
                
                # stop ensembl moaning
                my $old_verbose_level = verbose();
                verbose(0);
                
                my $mapper = $asma->fetch_by_CoordSystems($coord_sys, $requested_region->{cs});
                
                verbose($old_verbose_level);
                
                if ($mapper) {
                    print "Database $db can map ".$coord_sys->name.":".$coord_sys->version.
                        " to ".$requested_region->{cs}->name.":".$requested_region->{cs}->version.
                        "\n" if $verbose;
                    $mapper_db = $db;
                    
                    my $slice_adaptor = $dbh->get_SliceAdaptor;
                    
                    $target_slice = $slice_adaptor->fetch_by_region(
                        $requested_region->{cs}->name, 
                        $requested_region->{name},
                        $requested_region->{start}, 
                        $requested_region->{end}, 
                        $requested_region->{strand}, 
                        $requested_region->{cs}->version
                     );
                     
                     die "Failed to get slice on mapper DB" unless $target_slice;
                     
                     my $projection = $target_slice->project(
                        $common_region->{cs}->name,
                        $common_region->{cs}->version,
                     );
                     
                     if ($projection && @$projection == 1) {
                         $common_slice = $projection->[0]->to_Slice;
                         print "Successfully mapped requested region to common region: ".$common_slice->name."\n" if $verbose;
                         $common_region->{name} = $common_slice->seq_region_name;
                         $common_region->{start} = $common_slice->start;
                         $common_region->{end} = $common_slice->end;
                         $common_region->{strand} = $common_slice->strand;
                     }
                     else {
                         die "Funky mapping";
                     }
                    
                     last SEARCH;
                }
            }
        }
    }
    
    die "Failed to find coordinate system supported by all databases\n" unless $found;
}
else {
    print "Found common coordinate system: ".$requested_region->{cs}->name.":".$requested_region->{cs}->version."\n";
    $common_region = $requested_region;
}

for my $db (keys %dbs) {

        my $dbh = $dbs{$db}->{dbh};

        my $slice_adaptor = $dbh->get_SliceAdaptor;
    
    my $slice;
    my $t_slice;
    my $c_slice;
    
    if ($mapper_db && $db eq $mapper_db) {
        $slice = $slice_adaptor->fetch_by_region(
            $requested_region->{cs}->name, 
            $requested_region->{name},
            $requested_region->{start}, 
            $requested_region->{end}, 
            $requested_region->{strand}, 
            $requested_region->{cs}->version
       );
    }
    else {
        $slice = $slice_adaptor->fetch_by_region(
            $common_region->{cs}->name, 
            $common_region->{name},
            $common_region->{start}, 
            $common_region->{end}, 
            $common_region->{strand}, 
            $common_region->{cs}->version
           );
           
           $t_slice = $target_slice;
       $c_slice = $common_slice;
    }
                
        #print "cs name: ".$slice->coord_system->name." version: ".$slice->coord_system->version."\n";  
        #$slice->project('chromosome', 'Otter');
                                
        die "Failed to fetch slice for requested region\n" unless $slice;
        
        # and append the slice's gff representation
        
        print "Database $db:\n" if $verbose;

        $gff_header ||=
            ($t_slice || $slice)->gff_header(include_dna => 1);
        $gff .= $slice->to_gff(
                analyses                        => $dbs{$db}->{analyses},
                feature_types           => $dbs{$db}->{feature_types},
                sources_to_types        => \%sources_to_types,
                verbose                         => $verbose,
                target_slice        => $t_slice,
                common_slice        => $c_slice,        
    );
        
        # save off the first sequence name for zmap
        
        $sequence_name = $slice->seq_region_name unless $sequence_name;
        
}

# create the styles file

my $styles_cfg = Config::IniFiles->new( -file => $styles_file ) 
        or die "Failed to read styles file: $styles_file\n";
        
my %provided_styles = map { $_ => 1 } $styles_cfg->Sections;
        
my $styles_list = join (';', keys %provided_styles);
        
if ($create_missing_styles) {
        
        # create a style for each source which doesn't have one
                
        for my $source (keys %sources_to_types) {
                
                # skip if there is a style already defined for this source
                next if $styles_cfg->SectionExists($source);
                
                my $type = $sources_to_types{$source};
                
                my $type_settings = $feature_type_settings{$type};
                
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
                
                if ($type eq 'Genes' && $colour eq 'RANDOM') {
                    
                    my @vs = ('00', '33', '66', '99', 'CC', 'FF'); 
                    
                    my $r = hex($vs[rand(@vs)]);
                    my $g = hex($vs[rand(@vs)]);
                    my $b = hex($vs[rand(@vs)]);
                    
                    if ($r == 255 && $g == 255 && $b == 255) {
                        shift @vs;
                        $r = hex($vs[rand(@vs)]);
                    }
                    
                    my $border = sprintf("#%02x%02x%02x", $r, $g, $b);
                    my $cds_border = sprintf("#%02x%02x%02x", $r-10, $g-10, $b-10);
                    my $fill = sprintf("#%02x%02x%02x", $r-30, $g-30, $b-30);
                    
                    $cds_border = $border;
                    $fill = $border;
                    
                $styles_cfg->newval(
                $source, 
                'colours', 
                "normal fill white ; normal border $border"
            );
            
            $styles_cfg->newval(
                $source, 
                'transcript-cds-colours', 
                "normal fill $fill ; normal border $cds_border ; selected fill gold"
            );
                    
                    # reset the colours list
                    
                    push @{ $type_settings->{colours} }, 'RANDOM';
                }
        }
                
        my $styles_fh;
        
        ($styles_fh, $styles_file) = tempfile(
                'enzembl_styles_XXXXXX', 
                SUFFIX => '.ini', 
                UNLINK => !$persist, 
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
        UNLINK => !$persist, 
        DIR => '/tmp'
);

print $gff_fh $gff_header . $gff;

# build up ZMap file

my $sources_list = 'DNA;Locus;'.join(';', keys %sources_to_types); # always include DNA and Locus

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

# add the necessary entries to the zmap config file, over-writing existing entries

my $zmap_cfg = Config::IniFiles->new( -file => $zmap_config_file );

$zmap_cfg->newval('ZMap', 'default-sequence', $sequence_name);
$zmap_cfg->newval('source', 'url','file:///'.$gff_filename);
$zmap_cfg->newval('source', 'featuresets', $sources_list);
$zmap_cfg->newval('source', 'stylesfile', $styles_file);
$zmap_cfg->newval('blixem', 'dna-featuresets', $dna_sources);
$zmap_cfg->newval('blixem', 'protein-featuresets', $protein_sources);
$zmap_cfg->newval('blixem', 'featuresets', $tsct_sources);

my $zmap_dir = tempdir(
        'enzembl_zmap_XXXXXX', 
        DIR => '/tmp', 
        CLEANUP => !$persist
);

$zmap_cfg->WriteConfig($zmap_dir.'/ZMap') or die "Failed to write zmap config file\n";

# and run zmap...

system($zmap_exe, "--conf_dir", $zmap_dir);

if ($persist) {
    print "\nFiles created by enzembl have been left in /tmp, remember to delete them! You can rerun this session with:\n\n";
    print "$zmap_exe --conf_dir $zmap_dir\n\n";
}

__END__
        
=head1 NAME 

enzembl

=head1 DESCRIPTION

Connect to EnsEMBL schema databases and show features directly in ZMap.

=head1 SYNOPSIS

enzembl [options]

=head1 EXAMPLE COMMAND LINES

assuming you've specified some style settings and a zmap executable in your config file
(see below for details):

  enzembl -region clone::AC068644.15 -analyses Halfwise,vertrna -types Genes,DnaAlignFeatures\ 
          -db pipe_human -host otterpipe1 -port 3322 -user ottro

or with databases and types specified in the config file:

  enzembl -region chromosome:GRCh37:chr14-03 -coords 1000-2000 -analyses Est2genome_human

=head1 OPTIONS

B<NB:> All of these settings can also be set in the config file. Command line options override config file settings.

=over 4

=item B<-cfg FILE>

Read configuration from the specified file (defaults to ~/.enzembl_config). Supply '-h'
on the command line to see an example file.

=item B<-region coord_system:version:name:start:end:strand>

Grab features from the specified region, e.g. chromosome:GRCh37:15:10000:30000:1 etc.
Must be supplied here or in the config file

=item B<-analyses logic_name1,logic_name2,...>

Grab features created by these analyses. Must be supplied here or in the config file.

=item B<-types type_name1,type_name2,...>

Only look for features of these types (== EnsEMBL feature classes). Must be supplied here or in the config file.

=item B<-styles FILE>

Use provided zmap styles file.

=item B<-create_styles>

Automatically create a style for features from each feature type found. The parent style and
some colours to use to differentiate features of the same type from different analyses can be
specified in the config file (supply '-h' on the command line to see an example styles file).

=item B<-zmap /path/to/zmap>

Use this zmap executable. Must be supplied here or in the config file.

=item B<-zmap_cfg FILE>

Use the given file as the ZMap configuration file (normally found in ~/.ZMap/ZMap). Note that 
this script automatically fills in the parameters shown below, if you specify any of these in 
this file they will be ignored. All other settings are passed unaltered to zmap. Supply '-h'
on the command line to see a working example file.

 stanza         parameters set by this script
 ------------------------------------------------------------------------
 [ZMap]         default-sequence
 [source]       url, featuresets, stylesfile
 [blixem]       dna-featuresets, protein-featuresets, featuresets

=item B<-db | -dbs dbname1,dbname2,...>

Grab features from these (EnsEMBL schema) databases. If you supply more than one database
name you need to have supplied the necessary settings (host, user, and optionally port and 
password) in the config file (you may also have done so for a single database). If you supply 
a single database name you can supply these settings on the command line with the next set 
of options described below. If you use multiple databases bear in mind that no mapping between 
coordinate systems is (yet) supported, so all features are assumed to lie in the same 
coordinate space. Must be supplied here or in the config file.

=item B<-host HOST -port PORT -user USER -pass PASSWORD>

Use these settings to connect to the (single) database name supplied with the -db option.

=item B<-v | -verbose>

Produce verbose output.

=item B<-h | -help>

Print extended usage instructions, including example configuration and styles files.

=head1 CONFIG FILE

If supplied vith '-cfg' (or in ~/.enzembl_config), should look something like this:

 [enzembl]
 dbs = loutre_human, pipe_human
 zmap = /software/anacode/otter/otter_production_main/bin/zmap
 zmap-config = /nfs/team71/analysis/gr5/.enzembl/ZMap
 feature-types = DnaAlignFeatures,ProteinAlignFeatures,Genes,SimpleFeatures,RepeatFeatures,PredictionTranscripts
 stylesfile = /nfs/team71/analysis/gr5/.enzembl/basic_styles.ini
 create-missing-styles = 1

 [loutre_human]
 host = otterlive
 port = 3324
 user = ottro
 analyses = Otter

 [pipe_human]
 host = otterpipe1
 port = 3322
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





