package Bio::Otter::ServerScriptSupport;

use strict;

use OtterDefs;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::Otter::DBSQL::DBAdaptor;
use Bio::Vega::DBSQL::DBAdaptor;
use Bio::Otter::Author;
use Bio::Vega::Author;
use Bio::Otter::Version;
use Bio::Otter::Lace::TempFile;

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

sub csn {   # needed by logging mechanism
    my $self = shift @_;

    my @syll = split(/\//, $ENV{CURRENT_SCRIPT_NAME} || $0);
    return pop(@syll);
}

sub species_hash {      # could move out into a separate class, living on top of species.dat
    my $self = shift @_;

    return $OTTER_SPECIES; # inherited from OtterDefs (ultimately from species.dat)
}

sub dataset_param {     # could move out into a separate class, living on top of species.dat
    my ($self, $param) = @_;

        # Check the dataset has been entered:
    my $dataset = $self->require_argument('dataset');

        # get the overriding dataset options from species.dat 
    my $dbinfo   = $self->species_hash()->{$dataset} || $self->error_exit("Unknown data set $dataset");

        # get the defaults from species.dat
    my $defaults = $self->species_hash()->{'defaults'};

    return $dbinfo->{$param} || $defaults->{$param};
}

sub dataset_headcode {
    my $self = shift @_;

    return $self->dataset_param('HEADCODE');
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

sub tempfile_from_argument {
    my $self      = shift @_;
    my $argname   = shift @_;

    my $file_name = shift @_ || $self->csn().'_'.$self->require_argument('author').'.xml';

    my $tmp_file = Bio::Otter::Lace::TempFile->new;
    $tmp_file->root('/tmp');
    $tmp_file->name($file_name);
    my $full_name = $tmp_file->full_name();

    $self->log("Dumping the data to the temporary file '$full_name'");

    my $write_fh = eval{
        $tmp_file->write_file_handle();
    } || $self->error_exit("Can't write to '$full_name' : $!");
    print $write_fh $self->require_argument($argname);

    return $tmp_file;
}

############# Creation of an Author object from arguments #######

sub make_Author_obj {
    my $self = shift @_;

    my $author_name  = $self->require_argument('author');
    my $author_email = $self->require_argument('email');
    my $class        = $self->running_headcode() ? 'Bio::Vega::Author' : 'Bio::Otter::Author';

    return $class->new(-name => $author_name, -email => $author_email);
}

sub fetch_Author_obj {
    my $self = shift @_;

    if($self->running_headcode() != $self->dataset_headcode()) {
        $self->error_exit("RunningHeadcode != DatasetHeadcode, cannot fetch Author");
    }

    my $author_name    = $self->require_argument('author');
    my $author_adaptor = $self->otter_dba()->get_AuthorAdaptor();

    my $author_obj;
    eval{
        $author_obj = $author_adaptor->fetch_by_name($author_name);
    };
    if($@){
        eval{
            $author_obj = $author_adaptor->fetch_by_name($OTTER_GLOBAL_ACCESS_USER);
        };
        if($@){
            $self->error_exit("Failed to get an author.\n$@") unless $author_obj;
        }
    }
    return $author_obj;
}

############## DB connections and slices: #######################

sub otter_dba {
    my $self = shift @_;

    if($self->{_odba}) {            # cached value
        return $self->{_odba};
    }

    ########## CODEBASE tricks ########################################

    my $running_headcode = $self->running_headcode();
    my $dataset_headcode = $self->dataset_headcode();

    my $adaptor_class = $running_headcode
        ? ( $dataset_headcode
                ? 'Bio::Vega::DBSQL::DBAdaptor'     # headcode anyway, get the best adaptor
                : 'Bio::EnsEMBL::DBSQL::DBAdaptor'  # new pipeline of the old otter, get the minimal adaptor
          )
        : ( $dataset_headcode
                ? 'Bio::EnsEMBL::DBSQL::DBAdaptor'  # old pipeline of the new otter, get the minimal adaptor
                : 'Bio::Otter::DBSQL::DBAdaptor'    # oldcode anyway, get the best adaptor
        );

    ########## AND DB CONNECTION #######################################

    my( $odba, $dnadb );

    if(my $dbname = $self->dataset_param('DBNAME')) {
        eval {
           $odba = $adaptor_class->new( -host   => $self->dataset_param('HOST'),
                                        -port   => $self->dataset_param('PORT'),
                                        -user   => $self->dataset_param('USER'),
                                        -pass   => $self->dataset_param('PASS'),
                                        -dbname => $dbname);
        };
        $self->error_exit("Failed opening otter database [$@]") if $@;

        $self->log("Connected to otter database");
    } else {
		$self->error_exit("Failed opening otter database [No database name]");
    }

    if(my $dna_dbname = $self->dataset_param('DNA_DBNAME')) {
        eval {
            $dnadb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host   => $self->dataset_param('DNA_HOST'),
                                                        -port   => $self->dataset_param('DNA_PORT'),
                                                        -user   => $self->dataset_param('DNA_USER'),
                                                        -pass   => $self->dataset_param('DNA_PASS'),
                                                        -dbname => $dna_dbname);
        };
        $self->error_exit("Failed opening dna database [$@]") if $@;
        $odba->dnadb($dnadb);
        
        $self->log("Connected to dna database");
    }

    if(!$running_headcode && !$dataset_headcode) {
        if(my $type = $self->getarg('type') || $self->dataset_param('TYPE')) {
            $self->log("Assembly_type='" . $odba->assembly_type($type)."'");
        }
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
    my ($self, $metakey, $cs, $csver_orig, $csver_remote, $name, $type) = @_;

    if(!$metakey) {
        $self->log("Working with pipeline_db directly, no remapping is needed.");
        return;
    } elsif($metakey eq '.') {
        $self->log("Working with otter_db directly, no remapping is needed.");
        return;
    }

    my $csver = $self->cached_csver($metakey, $cs, $csver_remote);
    if($cs eq 'chromosome') {
        if($csver =~/^otter$/i) {
            $self->log("Working with another Otter database, no remapping is needed.");
            return;
        } elsif($csver eq 'UNKNOWN') {
            $self->log("The database's default assembly is not set correctly");
            $self->return_emptyhanded();
        }
    }

    if(!$self->running_headcode()) {
        $self->log("Working with unknown OLD API database, please do the remapping on client side.");
        return;
    }

    ## What remains is head version of a non-otter satellite_db

        # Currently we keep assembly equivalency information in the pipeline_db_head seq_region_attrib.
        # Once otter_db is converted into new schema, we can keep this information there.
    my $pdba = $self->satellite_dba( '' ); # it will be NEW pipeline by exclusion

        # this slice does not have to be completely defined (no start/end/strand),
        # as we only need it to get the attributes
    my $pipe_slice = $self->get_slice($pdba, $cs, $name, $type, undef, undef, undef, $csver_orig);

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
    my ($self, $feature_name, $call_parms) = @_;

    my $fetching_method = shift @$call_parms;

    my $cs           = $self->getarg('cs')           || 'chromosome';
    my $csver_orig   = $self->getarg('csver')        || undef;
    my $csver_remote = $self->getarg('csver_remote') || undef;
    my $metakey      = $self->getarg('metakey')      || ''; # defaults to pipeline
    my $name         = $self->getarg('name');
    my $type         = $self->getarg('type');
    my $start        = $self->getarg('start');
    my $end          = $self->getarg('end');
    my $strand       = $self->getarg('strand');

    my $sdba = $self->satellite_dba( $metakey );
    my ($mdba, $csver) = $self->get_mapper_dba( $metakey, $cs, $csver_orig, $csver_remote, $name, $type);

    my $features = [];

    if($mdba) {
        $self->log("Proceeding with mapping code");

        my $original_slice_on_mapper = $self->get_slice($mdba, $cs, $name, $type, $start, $end, $strand, $csver_orig);
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
                    $self->log("Could not transfer $feature_name $fname from {".$target_feature->slice->name."} onto {".$original_slice_on_mapper->name.'}');
                }
            }
        }

    } else {
        $self->log("No mapping is needed, just fetching");

        my $original_slice = $self->get_slice($sdba, $cs, $name, $type, $start, $end, $strand, $csver);

        $features = $original_slice->$fetching_method(@$call_parms);
    }

    $self->log("Total of ".scalar(@$features).' '.join('/', grep { !ref($_) } @$call_parms)
              ." ${feature_name}s have been sent to the client");

    return $features;
}

1;

