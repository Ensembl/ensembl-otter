#!/usr/local/bin/perl -w

###############################################################################
#   
#   Name:           OtterDefs.pm
#   
#   Description:    Config for Otter server.
#
###############################################################################

package OtterDefs;

use strict;
use vars qw(
    @ISA     @EXPORT     @EXPORT_OK     %EXPORT_TAGS     $VERSION

   $OTTER_PREFIX
   $OTTER_SPECIES
   $OTTER_SERVER_ROOT
   $OTTER_SERVER_PORT
   $OTTER_ALTROOT
   $OTTER_SCRIPTDIR
   $OTTER_SERVER
   $OTTER_PORT
   $OTTER_MAX_CLIENTS
   $OTTER_DBNAME 
   $OTTER_USER
   $OTTER_HOST
   $OTTER_PORT
   $OTTER_PASS
   $OTTER_TYPE
   $OTTER_DNA_DBNAME 
   $OTTER_DNA_USER
   $OTTER_DNA_HOST
   $OTTER_DNA_PORT
   $OTTER_DNA_PASS
   $OTTER_DEFAULT_SPECIES
   $OTTER_SPECIES_FILE
);

use Sys::Hostname;
use Exporter();

@ISA=qw(Exporter);

$OTTER_SERVER_ROOT 	    = '/nfs/acari/michele/cvs/ensembl-otter';
$OTTER_ALTROOT    	    = '/nfs/acari/michele/cvs/ensembl-otter/otter_alt';
$OTTER_SCRIPTDIR            = '/nfs/acari/michele/cvs/ensembl-otter/scripts/server';
$OTTER_SERVER		    = 'localhost';#Sys::Hostname::hostname();  # Local machine name
$OTTER_MAX_CLIENTS          = 5;
$OTTER_SERVER_PORT          = 19312;

$OTTER_SPECIES_FILE         = $OTTER_SERVER_ROOT . "/conf/species.dat";
$OTTER_SPECIES              = read_species($OTTER_SPECIES_FILE);
$OTTER_DEFAULT_SPECIES      = 'human_chr22';
$OTTER_PREFIX               = 'OTT';

################################################################################################
#
# Nothing below here should need to be edited
#
################################################################################################

$OTTER_DBNAME        = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{DBNAME};
$OTTER_USER          = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{USER} || $OTTER_SPECIES->{defaults}{USER};
$OTTER_HOST          = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{HOST} || $OTTER_SPECIES->{defaults}{HOST};
$OTTER_PORT          = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{PORT} || $OTTER_SPECIES->{defaults}{PORT};
$OTTER_PASS          = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{PASS} || $OTTER_SPECIES->{defaults}{PASS};
$OTTER_TYPE          = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{TYPE} || $OTTER_SPECIES->{defaults}{TYPE};

$OTTER_DNA_DBNAME    = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{DNA_DBNAME};

$OTTER_DNA_HOST       = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{DNA_HOST} || $OTTER_SPECIES->{defaults}{DNA_HOST};
$OTTER_DNA_USER       = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{DNA_USER} || $OTTER_SPECIES->{defaults}{DNA_USER};
$OTTER_DNA_PORT       = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{DNA_PORT} || $OTTER_SPECIES->{defaults}{DNA_PORT};
$OTTER_DNA_PASS       = $OTTER_SPECIES->{$OTTER_DEFAULT_SPECIES}{DNA_PASS} || $OTTER_SPECIES->{defaults}{DNA_PASS};

@EXPORT = qw
  (
   $OTTER_SERVER_ROOT
   $OTTER_SERVER_PORT
   $OTTER_ALTROOT
   $OTTER_SCRIPTDIR
   $OTTER_SERVER
   $OTTER_PORT
   $OTTER_MAX_CLIENTS
   $OTTER_SPECIES
   $OTTER_DEFAULT_SPECIES
   $OTTER_PREFIX
   
   $OTTER_DBNAME 
   $OTTER_USER
   $OTTER_HOST
   $OTTER_PORT
   $OTTER_PASS
   $OTTER_TYPE

   $OTTER_DNA_DBNAME 
   $OTTER_DNA_USER
   $OTTER_DNA_HOST
   $OTTER_DNA_PORT
   $OTTER_DNA_PASS
);

sub read_species {
  my ($file) = @_;

  open(IN,"<$file") || die "Can't read species file [$file]\n";

  my $cursect = undef;
  my %defhash;
  my $curhash;
  
  my %info;
  
  while (<IN>) {
    next if /^\#/;
    next unless /\w+/;
    chomp;

    if (/\[(.*)\]/) {
      if (!defined($cursect) && $1 ne "defaults") {
        die "ERROR: First section in species.dat should be defaults\n";
      } elsif ($1 eq "defaults") {
	    #print STDERR "Got default section\n";
        $curhash = \%defhash;
      } else {
        $curhash = {};
        foreach my $key (keys %defhash) {
          $key =~ tr/a-z/A-Z/;
          $curhash->{$key} = $defhash{$key};
        }
      }
      $cursect = $1;
      $info{$cursect} = $curhash;

    } elsif (/(\S+)\s+(\S+)/) {
      #print "Reading entry $1 $2\n";
      $curhash->{$1} = $2;
    }
  }
  return (\%info);
}

	
1;
