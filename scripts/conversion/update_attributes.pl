#!/usr/local/bin/perl

=head1 NAME

update_attributes.pl - populate the attrib_type table from a file with
attribute type definitions

=head1 SYNOPSIS

update_attributes.pl [options]

General options:
    --conffile, --conf=FILE             read parameters from FILE
                                        (default: conf/Conversion.ini)

    --dbname, db_name=NAME              use database NAME
    --host, --dbhost, --db_host=HOST    use database host HOST
    --port, --dbport, --db_port=PORT    use database port PORT
    --user, --dbuser, --db_user=USER    use database username USER
    --pass, --dbpass, --db_pass=PASS    use database passwort PASS
    --logfile, --log=FILE               log to FILE (default: *STDOUT)
    --logpath=PATH                      write logfile to PATH (default: .)
    --logappend, --log_append           append to logfile (default: truncate)
    -v, --verbose                       verbose logging (default: false)
    -i, --interactive=0|1               run script interactively (default: true)
    -n, --dry_run, --dry=0|1            don't write results to database
    -h, --help, -?                      print help (this message)

Specific options:

    --attribtypefile=FILE               read attribute type definition from FILE

=head1 DESCRIPTION

This script populates the attrib_type table from a file with attribute type
definitions. This file is maintained by Ensembl and stored in cvs.

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

=head1 AUTHOR

Patrick Meidl <pm2@sanger.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use FindBin qw($Bin);
use vars qw($SERVERROOT);

BEGIN {
    $SERVERROOT = "$Bin/../../..";
    unshift(@INC, "$SERVERROOT/ensembl-otter/modules");
    unshift(@INC, "$SERVERROOT/ensembl/modules");
    unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options('attribtypefile=s');
$support->allowed_params($support->get_common_params, 'attribtypefile');

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# check required params
$support->check_required_params('attribtypefile');

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# there is nothing to do for a dry run, so exit
if ($support->param('dry_run')) {
    $support->log("Nothing to do for a dry run. Aborting.\n");
    exit;
}

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;

# finish logfile
$support->finish_log;

# read attrib_type entries from file
$support->log("Reading attrib_type entries from file...\n");
my $fh = $support->filehandle('<', $support->param('attribtypefile'));
my @rows;
while (my $row = <$fh>) {
    chomp($row);
    next if ($row =~ /^\S*$/);
    next if ($row =~ /^\#/);

    my @a = split(/\t/, $row);
    push @rows, {
        'attrib_type_id' => $a[0],
        'code' => $a[1],
        'name' => $a[2],
        'description'  => $a[3],
    };
}
close($fh);
$support->log("Done reading ".scalar(@rows)." entries.\n");

# if any attrib_types are loaded that are different from 
# the file, a consistency problem is reported and the 
# upload is not done.
if (check_consistency($dbh, \@rows)) {
    # consistent
    $dbh->do("DELETE FROM attrib_type");

    load_attribs($dbh, \@rows);
} else {
    print STDERR "Repairing database, not consistent!\n";
    repair($dbh, \@rows);
}


# move attrib types wih the same code to the common attrib_type table
# ones that are not in the table move to an attrib_type_id that is not used
sub repair {
  my ($dbh, $attribs) = @_;
  
  my @tables = qw( seq_region_attrib misc_attrib translation_attrib transcript_attrib );
  my $ref = $dbh->selectall_arrayref( "show create table attrib_type" );
  my $create_table = $ref->[0]->[1];

  $dbh->do( "alter table attrib_type rename old_attrib_type" );
  $dbh->do( $create_table );


  load_attribs($dbh, $attribs);

  $dbh->do( "delete oat " .
	   "from old_attrib_type oat, attrib_type at " .
	   "where oat.attrib_type_id = at.attrib_type_id " .
	   "and oat.code = at.code" );

  # what remains in old attrib type ?
  #  Entries with a code that is unknown in general file 
  #  and that shouldnt really happen. If it happens, the code
  #  needs to ne appended to attrib_type table and the attrib
  #  type_ids will be updated in the feature tables.

  #  Entries with a code that is known, but has different 
  #  attrib_type_id. Feature tables will be updated.

  $dbh->do( "create table tmp_attrib_types ".
	   "select oat.attrib_type_id, oat.code, oat.name, oat.description " .
	   "from old_attrib_type oat " .
	   "left join attrib_type at " .
	   "on oat.code = at.code " .
	   "where at.code is null" );
  $dbh->do( "insert into attrib_type( code, name, description) ".
	   "select code, name, description ". 
	   "from tmp_attrib_types" );

  $ref = $dbh->selectall_arrayref( "select code from tmp_attrib_types" );
  $dbh->do( "drop table tmp_attrib_types" );

  print STDERR "Todo:\n";
  if( @$ref ) {
    print STDERR "  Missing codes ",join( ", ", map { $_->[0] } @$ref ),"\n";
  }

  my %missing_codes = map { $_->[0], 1 } @$ref;

  $ref = $dbh->selectall_arrayref( "select code from old_attrib_type oat " );

  my @updated_codes;
  for my $code_ref ( @$ref ) {
    if( ! exists $missing_codes{ $code_ref->[0] } ) {
      push( @updated_codes, $code_ref->[0] );
    }
  }

  print STDERR "  Updated codes ", join( ", ", @updated_codes ), "\n";

  # now do multi table updates on all tables
  for my $up_table ( @tables ) {
    $dbh->do( "update $up_table tb, attrib_type at, old_attrib_type oat ".
	     "set tb.attrib_type_id = at.attrib_type_id ".
	     "where tb.attrib_type_id = oat.attrib_type_id ".
	     "and oat.code = at.code " );
  }

  $dbh->do( "drop table old_attrib_type" );
}


sub load_attribs {
  my ($dbh, $attribs) = @_;
    my $sth;
    $sth = $dbh->prepare( "insert into attrib_type( attrib_type_id, code, name, description) ".
			 "values(?,?,?,?)" ); 
    for my $attrib ( @$attribs ) {
      $sth->execute( $attrib->{'attrib_type_id'}, $attrib->{'code'},
		     $attrib->{'name'}, $attrib->{'description'} );
    }
}
  


# alternatively consistency can be enforceed to a certain degree 
sub check_consistency {
  my $dbh = shift;
  my $attribs = shift;

  my ( %db_codes, %file_codes );
  map { $file_codes{$_->{'attrib_type_id'}} = $_->{'code'}} @$attribs;
  
  my $sth = $dbh->prepare( "SELECT attrib_type_id, code, name, description ".
			  "FROM attrib_type" );
  $sth->execute();
  while( my $arr = $sth->fetchrow_arrayref() ) {
    $db_codes{ $arr->[0] } = $arr->[1];
  }

  # check if any ids in the database colide with the file
  my $consistent = 1;
  for my $dbid ( keys %db_codes ) {
    if(! exists $file_codes{ $dbid } || 
       $file_codes{$dbid} ne $db_codes{ $dbid } ) {
      $consistent = 0;
    }
  }

  return $consistent;
}



