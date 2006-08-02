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
                    &odba_to_sdba
                    &get_slice
                    &get_Author_from_CGI
                    &get_DBAdaptor_from_CGI_species
                    );
our %EXPORT_TAGS = (all => [qw(
                               server_log
                               set_nph
                               send_response
                               error_exit
                               odba_to_sdba
                               get_slice
                               get_Author_from_CGI
                               get_DBAdaptor_from_CGI_species 
                               )
                            ],
                    );

sub server_log {
    my $line = shift @_;
    my $csn = $ENV{CURRENT_SCRIPT_NAME} || $0;
    print STDERR "[$csn] $line\n";
}

sub set_nph{
    my ($sq) = @_;
    error_exit('', 'I need a CGI object') unless $sq && UNIVERSAL::isa($sq, 'CGI');
    if (defined($ENV{SERVER_SOFTWARE})
    && ( $ENV{SERVER_SOFTWARE} =~ /libwww-perl-daemon/)) {
        # server_log('NOTE: Setting nph to 1');
        $sq->nph(1);
    }
}

sub send_response{
    my ($sq, $response, $wrap) = @_;

    server_log('Sending the response =====================');
    print $sq->header('text/plain') if $sq && UNIVERSAL::isa($sq, 'CGI');

    if($wrap) {
        print qq`<?xml version="1.0" encoding="UTF-8"?>\n`;
        print qq`<otter schemaVersion="$SCHEMA_VERSION" xmlVersion="$XML_VERSION">\n`;
    }

    print $response;

    if($wrap) {
        print "</otter>\n";
    }
}

sub error_exit {
    my ($sq, $reason) = @_;

    chomp($reason);

    send_response($sq, " <response>\n    ERROR:\n$reason\n </response>", 1);
    server_log("ERROR: $reason\n");

    exit(1);
}

sub odba_to_sdba {
    my ($sq, $odba, $pipehead, $metakey) = @_;

    server_log("called with: ".join(' ', map { "$_=".$sq->getarg($_) } @{$sq->getargs()} ));

    my $kind = 'satellite DB';

    if(! $metakey) {
        $metakey = $pipehead
            ? 'pipeline_db_head'
            : 'pipeline_db';
        $kind = 'pipeline DB'
    }

    server_log("connecting to the ".($pipehead?'NEW':'OLD')." schema $kind using [$metakey] meta entry...");

    my $class = $pipehead
        ? 'Bio::EnsEMBL::DBSQL::DBAdaptor'
        : 'Bio::Otter::DBSQL::DBAdaptor';

    my ($sdba, $sdb_options) =
        Bio::Otter::Lace::SatelliteDB::_get_DBAdaptor_and_options(
            $odba,
            $metakey,
            $class,
        );

    error_exit($sq, "Could not create satellite_db for '$metakey' in otter database")
        unless ($sdba);

    error_exit($sq, "No connection parameters for '$metakey' in otter database")
        unless ($sdb_options && keys %$sdb_options);

    $sdba->assembly_type($odba->assembly_type()) unless $pipehead;

    server_log("... with parameters: ".join(', ', map { "$_=".$sdb_options->{$_} } keys %$sdb_options ));

    return $sdba;
}

sub get_slice { # codebase-independent version for scripts
    my ($sq, $dba, $pipehead) = @_;

    my $slice;

    my $cs    = $sq->getarg('cs') || 'chromosome';
    my $name  = $sq->getarg('name');
    my $type  = $sq->getarg('type');
    my $start = $sq->getarg('start');
    my $end   = $sq->getarg('end');

    if($pipehead) {

        my $strand= $sq->getarg('strand');
        my $csver = $sq->getarg('csver');
        if(!$csver && ($cs eq 'chromosome')) {
            $csver = 'Otter';
        }

            # The following statement ensures
            # that we use 'assembly type' as the chromosome name
            # only for Otter chromosomes.
            # Vega chromosomes will have simple names.
        my $segment_attr = (($cs eq 'chromosome') && ($csver eq 'Otter'))
			? 'type'
		    : 'name';
        my $segment_name = $sq->getarg($segment_attr);

        error_exit($sq, "$cs '$segment_attr' attribute not set") unless $segment_name;

        $slice =  $dba->get_SliceAdaptor()->fetch_by_region(
            $cs,
	        $segment_name,
            $start,
            $end,
            $strand,
            $csver,
        );

    } else {

        error_exit($sq, "$cs 'name' attribute not set") unless $name;

        if($cs eq 'chromosome') {
            $start ||= 1;
            $end   ||= $dba->get_ChromosomeAdaptor()->fetch_by_chr_name($name)->length();

            $slice = $dba->get_SliceAdaptor()->fetch_by_chr_start_end(
                $name,
                $start,
                $end,
            );
        } elsif($cs eq 'contig') {
            $slice = $dba->get_RawContigAdaptor()->fetch_by_name(
                $name,
            );
        } else {
            error_exit($sq, "Other coordinate systems are not supported");
        }
    }

    if(!defined($slice) && $pipehead) {
        server_log('Could not get a slice, probably not yet loaded into new pipeline');
        send_response($sq, '', 1);
        exit(0); # <--- this forces all the scripts to exit normally
    }

    return $slice;
}

sub get_Author_from_CGI{
    my ($sq) = @_;
    error_exit('', 'I need a CGI object') unless $sq && UNIVERSAL::isa($sq, 'CGI');

    my $auth_name = $sq->getarg('author') || error_exit($sq, "Need author for this script...");
    my $email     = $sq->getarg('email')  || error_exit($sq, "Need email for this script...");

    my $author    = Bio::Otter::Author->new(-name  => $auth_name,
                                            -email => $email);
    return $author;
}

sub get_DBAdaptor_from_CGI_species{
    my ($sq, $SPECIES, $pipehead) = @_;

    my $adaptor_class = $pipehead
        ? 'Bio::EnsEMBL::DBSQL::DBAdaptor'
        : 'Bio::Otter::DBSQL::DBAdaptor';

    error_exit('', 'I need two arguments') unless $sq && $SPECIES;
    error_exit('', 'I need a CGI object') unless UNIVERSAL::isa($sq, 'CGI');

    ####################################################################
    # Check the dataset has been entered
    my $dataset = $sq->getarg('dataset') || error_exit($sq, "No dataset type entered.");

    # get the overriding dataset options from species.dat 
    my $dbinfo   = $SPECIES->{$dataset} || error_exit($sq, "Unknown data set $dataset");

    # get the defaults from species.dat
    my $defaults = $SPECIES->{'defaults'};

    my $type     = $sq->getarg('type') || $dbinfo->{TYPE} || $defaults->{TYPE};

    ########## AND DB CONNECTION #######################################
    my $dbhost    = $dbinfo->{HOST}     || $defaults->{HOST};
    my $dbuser    = $dbinfo->{USER}     || $defaults->{USER};
    my $dbpass    = $dbinfo->{PASS}     || $defaults->{PASS};
    my $dbport    = $dbinfo->{PORT}     || $defaults->{PORT};
    my $dbname    = $dbinfo->{DBNAME}   || 
        error_exit($sq, "Failed opening otter database [No database name]");

    my $dnahost    = $dbinfo->{DNA_HOST}    || $defaults->{DNA_HOST};
    my $dnauser    = $dbinfo->{DNA_USER}    || $defaults->{DNA_USER};
    my $dnapass    = $dbinfo->{DNA_PASS}    || $defaults->{DNA_PASS};
    my $dnaport    = $dbinfo->{DNA_PORT}    || $defaults->{DNA_PORT};
    my $dna_dbname = $dbinfo->{DNA_DBNAME};
  
    my( $odba, $dnadb );

    server_log("OtterDB='$dbname' host='$dbhost' user='$dbuser' pass='$dbpass' port='$dbport'");
    eval {
       $odba = $adaptor_class->new( -host   => $dbhost,
                                    -user   => $dbuser,
                                    -pass   => $dbpass,
                                    -port   => $dbport,
                                    -dbname => $dbname);
    };
    error_exit($sq, "Failed opening otter database [$@]") if $@;
    if ($dna_dbname) {
        eval {
            $dnadb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host   => $dnahost,
                                                        -user   => $dnauser,
                                                        -pass   => $dnapass,
                                                        -port   => $dnaport,
                                                        -dbname => $dna_dbname);
        };
        error_exit($sq, "Failed opening dna database [$@]") if $@;
        $odba->dnadb($dnadb);
        
        server_log("Connected to dna database");
    }
    if(!$pipehead) {
        server_log("Assembly_type='" . $odba->assembly_type($type)."'");
    }
    return $odba;
}

1;

