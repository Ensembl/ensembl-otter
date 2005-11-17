package Bio::Otter::ServerSide;

use strict;
use Exporter;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::Otter::DBSQL::DBAdaptor;
use Bio::Otter::Author;
use Bio::Otter::Version;
use Bio::Otter::Lace::SatelliteDB;
use Bio::Otter::LogFile;

our @ISA       = qw(Exporter);
our @EXPORT    = qw();
our @EXPORT_OK = qw(
                    &server_log
                    &set_nph
                    &send_response
                    &error_exit
                    &get_pipeline_adaptor_slice_parms
                    &get_Author_from_CGI
                    &get_DBAdaptor_from_CGI_species
                    );
our %EXPORT_TAGS = (all => [qw(
                               server_log
                               set_nph
                               send_response
                               error_exit
                               get_pipeline_adaptor_slice_parms
                               get_Author_from_CGI
                               get_DBAdaptor_from_CGI_species 
                               )
                            ],
                    );

sub server_log {
    my $line = shift @_;
    print STDERR "[$ENV{CURRENT_SCRIPT_NAME}] $line\n";
}

sub set_nph{
    my ($cgi) = @_;
    error_exit('', 'I need a CGI object') unless $cgi && UNIVERSAL::isa($cgi, 'CGI');
    if ($ENV{SERVER_SOFTWARE} =~ /libwww-perl-daemon/) {
        # server_log('NOTE: Setting nph to 1');
        $cgi->nph(1);
    }
}

sub send_response{
    my ($cgi, $response, $wrap) = @_;
    error_exit('', 'I need a CGI object') unless $cgi && UNIVERSAL::isa($cgi, 'CGI');
    server_log('Sending the response =====================');
    print $cgi->header('text/plain');

    if($wrap) {
        print qq`<otter schemaVersion="$SCHEMA_VERSION" xmlVersion="$XML_VERSION">\n`;
    }

    print $response;

    if($wrap) {
        print "</otter>\n";
    }
}

sub error_exit {
  my ($cgi,$reason) = @_;

  print $cgi->header() if $cgi && UNIVERSAL::isa($cgi,'CGI');

  chomp($reason);

  print qq`<otter schemaVersion="$SCHEMA_VERSION" xmlVersion="$XML_VERSION">\n`;
  print qq` <response>\n`;
  print qq`    ERROR:\n$reason\n`;
  print qq`  </response>\n`;
  print qq`</otter>\n`;

  server_log("ERROR: $reason\n");

  exit(1);
}

sub get_pipeline_adaptor_slice_parms { # codebase-independent version for scripts
    my ($cgi, $odb, $enshead) = @_;

    my %cgi_args = $cgi->Vars;

    server_log("called with: ".join(' ', map { "$_=$cgi_args{$_}" } keys %cgi_args) );

    my $pipekey = $enshead
        ? 'pipeline_db_head'
        : 'pipeline_db';

    my ($pdb, $pipedb_options) =
    Bio::Otter::Lace::SatelliteDB::_get_DBAdaptor_and_options(
        $odb,
        $pipekey
    );

    my $pipeline_slice;

        # CS defaults:
    $cgi_args{cs} ||= 'chromosome';
    if(!$cgi_args{csver} && ($cgi_args{cs} eq 'chromosome')) {
        $cgi_args{csver} = 'Otter';
    }

    if($enshead) {

        server_log("connecting to the NEW pipeline using [$pipekey] meta entry");

		# The following statement ensures
		# that we use 'assembly type' as the chromosome name
		# only for Otter chromosomes.
		# Vega chromosomes will have simple names.
	my $segment_name = (($cgi_args{cs} eq 'chromosome') && ($cgi_args{csver} eq 'Otter'))
			? $cgi_args{type}
		        : $cgi_args{name};

        $pipeline_slice = $pdb->get_SliceAdaptor()->fetch_by_region(
            $cgi_args{cs},
	    $segment_name,
            $cgi_args{start},
            $cgi_args{end},
            $cgi_args{strand},
            $cgi_args{csver},
        );
    } else {

        server_log("connecting to the OLD pipeline using [$pipekey] meta entry");

        $pdb->assembly_type($odb->assembly_type());

        if($cgi_args{cs} eq 'chromosome') {
            $pipeline_slice = $pdb->get_SliceAdaptor()->fetch_by_chr_start_end(
                $cgi_args{name},
                $cgi_args{start},
                $cgi_args{end},
            );
        } elsif($cgi_args{cs} eq 'contig') {
            $pipeline_slice = $pdb->get_RawContigAdaptor()->fetch_by_name(
                $cgi_args{name},
            );
        } else {
            die "Other coordinate systems are not supported";
        }
    }

    return ($pdb, $pipeline_slice, $pipedb_options);
}

sub get_Author_from_CGI{
    my ($cgi) = @_;
    error_exit('', 'I need a CGI object') unless $cgi && UNIVERSAL::isa($cgi, 'CGI');
    my %params   = $cgi->Vars;
    my $auth_name = $params{author} || 
        error_exit($cgi, "Need author for this script...");
    my $email     = $params{email}  || 
        error_exit($cgi, "Need email for this script...");
    my $author    = Bio::Otter::Author->new(-name  => $auth_name,
                                            -email => $email);
    return $author;
}

sub get_DBAdaptor_from_CGI_species{
    my ($cgi, $SPECIES, $enshead) = @_;

    my $adaptor_class = $enshead
        ? 'Bio::EnsEMBL::DBSQL::DBAdaptor'
        : 'Bio::Otter::DBSQL::DBAdaptor';

    error_exit('', 'I need two arguments') unless $cgi && $SPECIES;
    error_exit('', 'I need a CGI object') unless UNIVERSAL::isa($cgi, 'CGI');
    my %params   = $cgi->Vars;
    ####################################################################
    # Check the dataset has been entered and it's valid
    my $dataset = $params{'dataset'} || 
        error_exit($cgi,"No dataset type entered.");
    if (!defined($SPECIES->{$dataset})) {
        error_exit($cgi, "Unknown data set $dataset");
    }
    # get the defaults from species.dat
    my %defaults = %{$SPECIES->{'defaults'}};
    # get the overriding dataset options from species.dat 
    my %dbinfo   = %{$SPECIES->{$dataset}};
    my $type     = $params{type} || $dbinfo{TYPE} || $defaults{TYPE};

    ########## AND DB CONNECTION #######################################
    my $dbhost    = $dbinfo{HOST}     || $defaults{HOST},
    my $dbuser    = $dbinfo{USER}     || $defaults{USER},
    my $dbpass    = $dbinfo{PASS}     || $defaults{PASS},
    my $dbport    = $dbinfo{PORT}     || $defaults{PORT},
    my $dbname    = $dbinfo{DBNAME}   || 
        error_exit($cgi, "Failed opening otter database [No database name]");
    my $dnahost    = $dbinfo{DNA_HOST}    || $defaults{DNA_HOST},
    my $dnauser    = $dbinfo{DNA_USER}    || $defaults{DNA_USER},
    my $dnapass    = $dbinfo{DNA_PASS}    || $defaults{DNA_PASS},
    my $dnaport    = $dbinfo{DNA_PORT}    || $defaults{DNA_PORT},
    my $dna_dbname = $dbinfo{DNA_DBNAME};
  
    my( $odb, $dnadb );

    server_log("OtterDB='$dbname' host='$dbhost' user='$dbuser' pass='$dbpass' port='$dbport'");
    eval {
        $odb = $adaptor_class->new( -host   => $dbhost,
                                    -user   => $dbuser,
                                    -pass   => $dbpass,
                                    -port   => $dbport,
                                    -dbname => $dbname);
    };
    error_exit($cgi, "Failed opening otter database [$@]") if $@;
    if ($dna_dbname) {
        eval {
            $dnadb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host   => $dnahost,
                                                        -user   => $dnauser,
                                                        -pass   => $dnapass,
                                                        -port   => $dnaport,
                                                        -dbname => $dna_dbname);
        };
        error_exit($cgi, "Failed opening dna database [$@]") if $@;
        $odb->dnadb($dnadb);
        
        server_log("Connected to dna database");
    }
    if(!$enshead) {
        server_log("Assembly_type='" . $odb->assembly_type($type)."'");
    }
    return $odb;
}

1;

