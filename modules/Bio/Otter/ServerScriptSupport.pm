package Bio::Otter::ServerScriptSupport;

use strict;

use OtterDefs;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::Otter::DBSQL::DBAdaptor;
use Bio::Vega::DBSQL::DBAdaptor;
use Bio::Otter::Author;
use Bio::Otter::Version;

use base 'Bio::Otter::ServerQuery';

sub new {
    my $pack = shift @_;

    $|=1; # autoflush

    my $self = $pack->SUPER::new(@_);                       # ServerQuery is incorporated

    if( defined($ENV{SERVER_SOFTWARE})
    && ( $ENV{SERVER_SOFTWARE} =~ /libwww-perl-daemon/)) {
        $self->nph(1);
    }

    return $self;
}

############## getters: ###########################

sub running_headcode {
    my $self = shift @_;

    return $ENV{PIPEHEAD};    # the actual running code (0=>rel.19, 1=>rel.20+)
}

sub csn {
    my $self = shift @_;

    return $ENV{CURRENT_SCRIPT_NAME} || $0;   # needed by logging mechanism
}

sub species_hash {
    my $self = shift @_;

    return $OTTER_SPECIES; # inherited from OtterDefs (ultimately from species.dat)
}

############## I/O: ################################

sub log {
    my ($self, $line) = @_;

    print STDERR '['.$self->csn()."] $line\n";
}
    
sub send_response{
    my ($self, $response, $wrap) = @_;

    $self->log('Sending the response =====================');
    print $self->header('text/plain');

    if($wrap) {
        print qq`<?xml version="1.0" encoding="UTF-8"?>\n`;
        print qq`<otter schemaVersion="$SCHEMA_VERSION" xmlVersion="$XML_VERSION">\n`;
        print $response;
        print "</otter>\n";
    } else {
        print $response;
    }
}

sub error_exit {
    my ($self, $reason) = @_;

    chomp($reason);

    $self->send_response(" <response>\n    ERROR:\n$reason\n </response>", 1);
    $self->log("ERROR: $reason\n");

    exit(1);
}

sub require_argument {
    my ($self, $argname) = @_;

    my $value = $self->getarg($argname);
    
    if(!defined($value)) {
        $self->error_exit("No '$argname' argument defined");
    } else {
        return $value;
    }
}

sub return_emptyhanded {
    my $self = shift @_;

    $self->send_response('', 1);
    exit(0); # <--- this forces all the scripts to exit normally
}

############# Creation of an Author object from arguments #######

sub make_Author_obj {
    my $self = shift @_;

    my $auth_name = $self->require_argument('author');
    my $email     = $self->require_argument('email');
    my $class     = $self->running_headcode() ? 'Bio::Vega::Author' : 'Bio::Otter::Author';

    return $class->new(-name => $auth_name, -email => $email);
}

############## DB connections and slices: #######################

sub otter_dba {
    my $self = shift @_;

    if($self->{_odba}) {            # cached value
        return $self->{_odba};
    }

    my $running_headcode = $self->running_headcode();

        # Check the dataset has been entered:
    my $dataset = $self->require_argument('dataset');

        # get the overriding dataset options from species.dat 
    my $dbinfo   = $self->species_hash()->{$dataset} || $self->error_exit("Unknown data set $dataset");

        # get the defaults from species.dat
    my $defaults = $self->species_hash()->{'defaults'};

    ########## CODEBASE tricks ########################################
    my $dataset_headcode  = $dbinfo->{HEADCODE} || $defaults->{HEADCODE};

    my $type     = $self->getarg('type') || $dbinfo->{TYPE} || $defaults->{TYPE};

    ########## AND DB CONNECTION #######################################

    my $dbhost    = $dbinfo->{HOST}     || $defaults->{HOST};
    my $dbuser    = $dbinfo->{USER}     || $defaults->{USER};
    my $dbpass    = $dbinfo->{PASS}     || $defaults->{PASS};
    my $dbport    = $dbinfo->{PORT}     || $defaults->{PORT};
    my $dbname    = $dbinfo->{DBNAME}   ||
		$self->error_exit("Failed opening otter database [No database name]");

    my $dnahost    = $dbinfo->{DNA_HOST}    || $defaults->{DNA_HOST};
    my $dnauser    = $dbinfo->{DNA_USER}    || $defaults->{DNA_USER};
    my $dnapass    = $dbinfo->{DNA_PASS}    || $defaults->{DNA_PASS};
    my $dnaport    = $dbinfo->{DNA_PORT}    || $defaults->{DNA_PORT};
    my $dna_dbname = $dbinfo->{DNA_DBNAME};
  

    my $adaptor_class = $running_headcode
        ? ( $dataset_headcode
                ? 'Bio::Vega::DBSQL::DBAdaptor'     # headcode anyway, get the best adaptor
                : 'Bio::EnsEMBL::DBSQL::DBAdaptor'  # new pipeline of the old otter, get the minimal adaptor
          )
        : ( $dataset_headcode
                ? 'Bio::EnsEMBL::DBSQL::DBAdaptor'  # old pipeline of the new otter, get the minimal adaptor
                : 'Bio::Otter::DBSQL::DBAdaptor'    # oldcode anyway, get the best adaptor
        );

    my( $odba, $dnadb );

    $self->log("OtterDB='$dbname' host='$dbhost' user='$dbuser' pass='$dbpass' port='$dbport'");
    eval {
       $odba = $adaptor_class->new( -host   => $dbhost,
                                    -user   => $dbuser,
                                    -pass   => $dbpass,
                                    -port   => $dbport,
                                    -dbname => $dbname);
    };
    $self->error_exit("Failed opening otter database [$@]") if $@;

    if ($dna_dbname) {
        eval {
            $dnadb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host   => $dnahost,
                                                        -user   => $dnauser,
                                                        -pass   => $dnapass,
                                                        -port   => $dnaport,
                                                        -dbname => $dna_dbname);
        };
        $self->error_exit("Failed opening dna database [$@]") if $@;
        $odba->dnadb($dnadb);
        
        $self->log("Connected to dna database");
    }

    if(!$running_headcode && !$dataset_headcode && $type) {
        $self->log("Assembly_type='" . $odba->assembly_type($type)."'");
    }

    return $self->{_odba} = $odba;
}

sub satellite_dba {
    my ($self, $metakey, $satehead) = @_;

    if(!defined($satehead)) { # not just 'false', but truly undefined
        $satehead = $self->running_headcode();
    }

    # Note: as multiple satellite_db's can be used, we have to explicitly send $metakey

    $metakey ||= '';

        # It may well be true that the caller
        # is interested in features from otter_db itself.
        # (This is NOT the default behaviour,
        #  so he has to specify it by setting metakey='.')

    if($metakey eq '.') {
        $self->log("Connecting to the otter_db itself");
        return $self->otter_dba();      # so $satehead is ignored
    }

    my $kind;

    if(! $metakey) {
        $metakey = $satehead
            ? 'pipeline_db_head'
            : 'pipeline_db';
        $kind = 'pipeline DB'
    } else {
        $kind = 'satellite DB';
    }

    if($self->{_sdba}{$metakey}) {
        $self->log("Get the cached [$metakey] adapter...");
        return $self->{_sdba}{$metakey};
    }

    $self->log("connecting to the ".($satehead?'NEW':'OLD')." schema $kind using [$metakey] meta entry...");

    my $running_headcode = $self->running_headcode();
    my $adaptor_class = ($running_headcode || $satehead)
            ? 'Bio::EnsEMBL::DBSQL::DBAdaptor'  # get the minimal adaptor (may be extended to Vega in future)
            : 'Bio::Otter::DBSQL::DBAdaptor';   # get the best adaptor for old API satellite

    my ($opt_str) = @{ $self->otter_dba()->get_MetaContainer()->list_value_by_key($metakey) };

    if(!$opt_str) {
        $self->error_exit("Could not find meta entry for '$metakey' satellite db");
    } elsif($opt_str =~ /^\=otter/) { # can't guarantee it is specifically '_head'
        return $self->otter_dba();    # and can't pass it further
    } elsif($opt_str =~ /^\=pipeline/) { # can't guarantee it is specifically '_head'
        return $self->satellite_dba('', $satehead);
    } elsif($opt_str =~ /^\=(\w+)$/) {
        return $self->satellite_dba($1, $satehead);
    }

    my %anycase_options = (eval $opt_str);
    if ($@) {
        $self->error_exit("Error evaluating '$opt_str' : $@");
    }

    my %uppercased_options = ();
    while( my ($k,$v) = each %anycase_options) {
        $uppercased_options{uc($k)} = $v;
    }
    
    my $sdba = $adaptor_class->new(%uppercased_options)
        || $self->error_exit("Couldn't connect to '$metakey' satellite db");

    $self->error_exit("No connection parameters for '$metakey' in otter database")
        unless (keys %uppercased_options);

        # if it's needed AND we can...
    $sdba->assembly_type($self->otter_dba()->assembly_type()) unless ($satehead || $running_headcode);

    $self->log("... with parameters: ".join(', ', map { "$_=".$uppercased_options{$_} } keys %uppercased_options ));

    return $self->{_sdba}{$metakey} = $sdba;
}

sub get_slice { # codebase-independent version for scripts
    my ($self, $dba, $cs, $name, $type, $start, $end, $strand, $csver) = @_;

    my $slice;

    $cs ||= 'chromosome'; # can't make a slice without cs

    if($self->running_headcode()) {

        $strand ||= 1;
        if(!$csver && ($cs eq 'chromosome')) {
            $csver = 'Otter';
        }

            # The following statement ensures
            # that we use 'assembly type' as the chromosome name
            # only for Otter chromosomes.
            # EnsEMBL chromosomes will have simple names.
        my ($segment_attr, $segment_name);
        ($segment_attr, $segment_name) = (($cs eq 'chromosome') && ($csver eq 'Otter'))
            ? ('type', $type)
            : ('name', $name);

        $self->error_exit("$cs '$segment_attr' attribute not set ") unless $segment_name;

        $slice =  $dba->get_SliceAdaptor()->fetch_by_region(
            $cs,
	        $segment_name,
            $start,
            $end,
            $strand,
            $csver,
        );

    } else { # not running_headcode()

        $self->error_exit("$cs 'name' attribute not set") unless $name;

        if($cs eq 'chromosome') {
            $start ||= 1;

            eval {
                my $chr_obj = $dba->get_ChromosomeAdaptor()->fetch_by_chr_name($name);
                $end ||= $chr_obj->length();
            };
            if($@) {
                $self->log("Could not get chromosome '$name', returning an empty list");
                $self->return_emptyhanded();
            }

            $slice = $dba->get_SliceAdaptor()->fetch_by_chr_start_end(
                $name,
                $start,
                $end,
            );

            if($slice and ! @{ $slice->get_tiling_path() } ) {
                $self->log('Could not get a slice, probably not (yet) loaded into satellite db');
                $self->return_emptyhanded();
            }
        } elsif($cs eq 'contig') {
            eval {
                $slice = $dba->get_RawContigAdaptor()->fetch_by_name(
                    $name,
                );
            };
            if($@) {
                $self->log("Could not get contig '$name', returning an empty list");
                $self->return_emptyhanded();
            }

        } else {
            $self->error_exit("Other coordinate systems are not supported");
        }

    }

    if(not $slice) {
        $self->log('Could not get a slice, probably not (yet) loaded into satellite db');
        $self->return_emptyhanded();
    }

    return $slice;
}

sub cached_csver { # with optional override

    my ($self, $metakey, $cs, $override) = @_; # metakey can even be '.' or ''

    return $self->{_target_asm}{$metakey}{$cs}
         = $override
        || $self->{_target_asm}{$metakey}{$cs}
        || (   ($cs eq 'chromosome')
            && eval { # FIXME: why does it have to be 'eval'?
                my ($asm_def) = @{ $self->satellite_dba($metakey)
                                   ->get_MetaContainer()->list_value_by_key('assembly.default') };
                $asm_def;
           }
           )
        || 'UNKNOWN';
}

sub get_mapper_dba {
    my ($self, $metakey, $satehead, $cs, $override_csver, $name, $type) = @_;

    if(!$metakey) {
        $self->log("Working with pipeline_db directly, no remapping is needed.");
        return;
    } elsif($metakey eq '.') {
        $self->log("Working with otter_db directly, no remapping is needed.");
        return;
    }

    my $csver = $self->cached_csver($metakey, $cs, $override_csver);
    if($cs eq 'chromosome') {
        if($csver =~/^otter$/i) {
            $self->log("Working with another Otter database, no remapping is needed.");
            return;
        } elsif($csver eq 'UNKNOWN') {
            $self->log("The database's default assembly is not set correctly");
            $self->return_emptyhanded();
        }
    }

    my $running_headcode = $self->running_headcode();
    if($running_headcode && !$satehead) {
        $self->log("Working with unknown OLD API database, please do the remapping on client side.");
        return;
    } elsif(!$running_headcode) {
        $self->log("Can't possibly do any remapping while running OLD API code");
        $self->return_emptyhanded();
    }

    ## What remains is head version of a non-otter satellite_db

        # Currently we keep assembly equivalency information in the pipeline_db_head seq_region_attrib.
        # Once otter_db is converted into new schema, we can keep this information there.
    my $pdba = $self->satellite_dba( '' ); # it will be NEW pipeline by exclusion

        # this slice does not have to be completely defined (no start/end/strand),
        # as we only need it to get the attributes
    my $pipe_slice = $self->get_slice($pdba, $cs, $name, $name, undef, undef, undef, $csver);

    my %asm_is_equiv = map { ($_->value() => 1) } @{ $pipe_slice->get_all_Attributes('equiv_asm') };

    if($asm_is_equiv{$csver}) { # we can simply rename instead of mapping

        $self->log("This $cs is equivalent to '$name' in our reference '$csver' assembly");
        return (undef, $csver);

    } else { # assemblies are guaranteed to differ!

        my $mapper_metakey = "mapper_db.${csver}";

        if( my $mdba = $self->satellite_dba($mapper_metakey) ) {
            return ($mdba, $csver);
        } else {
            $self->log("No '$mapper_metakey' defined in meta table => cannot map between assemblies => exiting");
            $self->return_emptyhanded();
        }
    }
}

sub fetch_mapped_features {
    my ($self, $satehead, $feature_name, $call_parms) = @_;

    my $fetching_method = shift @$call_parms;

    my $cs           = $self->getarg('cs')      || 'chromosome';
    my $csver_wanted = $self->getarg('csver')   || undef;
    my $metakey      = $self->getarg('metakey') || ''; # defaults to pipeline
    my $name         = $self->getarg('name');
    my $type         = $self->getarg('type');
    my $start        = $self->getarg('start');
    my $end          = $self->getarg('end');
    my $strand       = $self->getarg('strand');

    my $sdba = $self->satellite_dba( $metakey );
    my ($mdba, $csver) = $self->get_mapper_dba( $metakey, $satehead, $cs, $csver_wanted, $name, $type);

    my $features = [];

    if($mdba) {
        $self->log("Proceeding with mapping code");

        my $original_slice_on_mapper = $self->get_slice($mdba, $cs, $name, $type, $start, $end, $strand, $csver);
        my $proj_segments_on_mapper = $original_slice_on_mapper->project( $cs, $csver );

        my $sa_on_target = $sdba->get_SliceAdaptor();

        foreach my $segment (@$proj_segments_on_mapper) {
            my $projected_slice_on_mapper = $segment->to_Slice();

            my $target_slice_on_target = $sa_on_target->fetch_by_region(
                $projected_slice_on_mapper->coord_system()->name(),
                $projected_slice_on_mapper->seq_region_name(),
                $projected_slice_on_mapper->start(),
                $projected_slice_on_mapper->end(),
                $projected_slice_on_mapper->strand(),
                $projected_slice_on_mapper->coord_system()->version(),
            );

            my $target_fs_on_target_segment
                = $target_slice_on_target->$fetching_method(@$call_parms);

            $self->log('***** : '.scalar(@$target_fs_on_target_segment)." ${feature_name}s found on the slice");

            foreach my $target_feature (@$target_fs_on_target_segment) {

                if($target_feature->can('propagate_slice')) {
                    $target_feature->propagate_slice($projected_slice_on_mapper);
                } else {
                    $target_feature->slice($projected_slice_on_mapper);
                }

                if( my $transferred = $target_feature->transfer($original_slice_on_mapper) ) {
                    push @$features, $transferred;
                } else {
                    my $fname = sprintf( "%s [%d..%d]", 
                                        $target_feature->display_id(),
                                        $target_feature->start(),
                                        $target_feature->end() );
                    $self->log("Could not transfer $feature_name $fname onto {$cs:$csver}");
                }
            }
        }

    } else {
        $self->log("No mapping is needed, just fetching");

        my $original_slice = $self->get_slice($sdba, $cs, $name, $type, $start, $end, $strand, $csver);

        $features = $original_slice->$fetching_method(@$call_parms);
    }

    return $features;
}

1;

