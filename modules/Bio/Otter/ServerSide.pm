package Bio::Otter::ServerSide;

use strict;
use Exporter;

use Bio::Otter::DBSQL::DBAdaptor;
use Bio::Otter::Author;

our @ISA       = qw(Exporter);
our @EXPORT    = qw();
our @EXPORT_OK = qw(&error_exit
                    &get_Author_from_CGI
                    &get_DBAdaptor_from_CGI_species
                    &set_nph
                    &send_response);
our %EXPORT_TAGS = (all => [qw(error_exit
                               get_Author_from_CGI
                               get_DBAdaptor_from_CGI_species 
                               set_nph
                               send_response)
                            ],
                    );

sub error_exit {
  my ($q,$reason) = @_;

  print $q->header() if $q && UNIVERSAL::isa($q,'CGI');

  chomp($reason);

  print "<otter>\n";
  print "  <response>\n";
  print "    ERROR:\n$reason\n";
  print "  </response>\n";
  print "</otter>\n";

  print STDERR "ERROR: $reason";

  exit(1);
}

sub get_Author_from_CGI{
    my ($q) = @_;
    error_exit('', 'I need a CGI object') unless $q && UNIVERSAL::isa($q, 'CGI');
    my %params   = $q->Vars;
    my $auth_name = $params{author} || 
        error_exit($q, "Need author for this script...");
    my $email     = $params{email}  || 
        error_exit($q, "Need email for this script...");
    my $author    = Bio::Otter::Author->new(-name  => $auth_name,
                                            -email => $email);
    return $author;
}

sub get_DBAdaptor_from_CGI_species{
    my ($q, $SPECIES) = @_;
    error_exit('', 'I need two arguments') unless $q && $SPECIES;
    error_exit('', 'I need a CGI object') unless UNIVERSAL::isa($q, 'CGI');
    my %params   = $q->Vars;
    ####################################################################
    # Check the dataset has been entered and it's valid
    my $dataset = $params{'dataset'} || 
        error_exit($q,"No dataset type entered.");
    if (!defined($SPECIES->{$dataset})) {
        error_exit($q, "Unknown data set $dataset");
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
        error_exit($q, "Failed opening otter database [No database name]");
    my $dnahost    = $dbinfo{DNA_HOST}    || $defaults{DNA_HOST},
    my $dnauser    = $dbinfo{DNA_USER}    || $defaults{DNA_USER},
    my $dnapass    = $dbinfo{DNA_PASS}    || $defaults{DNA_PASS},
    my $dnaport    = $dbinfo{DNA_PORT}    || $defaults{DNA_PORT},
    my $dna_dbname = $dbinfo{DNA_DBNAME};
  
    my( $odb, $dnadb );

    print STDERR "Database dbname : [$dbname] host : [$dbhost] user : [$dbuser] pass : [$dbpass] port : [$dbport]";
    eval {
        $odb = new Bio::Otter::DBSQL::DBAdaptor(-host   => $dbhost,
                                                -user   => $dbuser,
                                                -pass   => $dbpass,
                                                -port   => $dbport,
                                                -dbname => $dbname);
    };
    error_exit($q, "Failed opening otter database [$@]") if $@;
    if ($dna_dbname) {
        eval {
            $dnadb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host   => $dnahost,
                                                        -user   => $dnauser,
                                                        -pass   => $dnapass,
                                                        -port   => $dnaport,
                                                        -dbname => $dna_dbname);
        };
        error_exit($q, "Failed opening dna database [$@]") if $@;
        $odb->dnadb($dnadb);
        
        print STDERR "Connected to dna database";
    }
    print STDERR "Assembly type " . $odb->assembly_type($type);
    return $odb;
}

sub set_nph{
    my ($q) = @_;
    error_exit('', 'I need a CGI object') unless $q && UNIVERSAL::isa($q, 'CGI');
    if ($ENV{SERVER_SOFTWARE} =~ /libwww-perl-daemon/) {
        print STDERR "NOTE : Setting nph to 1";
        $q->nph(1);
    }
}
sub send_response{
    my ($q, $response) = @_;
    error_exit('', 'I need a CGI object') unless $q && UNIVERSAL::isa($q, 'CGI');
    print STDERR "************** PRINTING RESPONSE ******************";
    print $q->header('text/plain');
    print $response;
}
