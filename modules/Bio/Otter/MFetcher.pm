package Bio::Otter::MFetcher;

# Previously a part of ServerScriptSupport,
# this module only deals with data layer:
# interprets the metakeys to create and manage DBAdaptors
# and performs mapping between assemblies.
#
# Author: lg4

use strict;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::Otter::DBSQL::DBAdaptor;
use Bio::Vega::DBSQL::DBAdaptor;

use base ('Bio::Otter::Compatibility', 'Bio::Otter::SpeciesDat');

sub new { # just to make it possible to instantiate an object
    my $pkg = shift @_;

    my $self = bless {}, $pkg;

    return $self;
}

    # to be overloaded by ServerScriptSupport
sub dataset_name {
    my( $self, $dataset_name ) = @_;
    
    if($dataset_name) {
        $self->{'_dataset_name'} = $dataset_name;
    }
    return $self->{'_dataset_name'};
}

sub current_dataset_param {
    my ($self, $param_name) = @_;

    return $self->get_dataset_param( $self->dataset_name() , $param_name);
}

sub dataset_headcode {
    my $self = shift @_;

    return $self->current_dataset_param('HEADCODE');
}


sub otter_dba {
    my $self = shift @_;

    if($self->{'_odba'} && !scalar(@_)) {   # cached value and no override
        return $self->{'_odba'};
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

    if(@_) { # let's check that the class is ok
        my $odba = shift @_;
        if(UNIVERSAL::isa($odba, $adaptor_class)) {
            return $self->{'_odba'} = $odba;
        } else {
            die "The object you assign to otter_dba must be a '$adaptor_class'";
        }
    }

    ########## AND DB CONNECTION #######################################

    my( $odba, $dnadb );

    if(my $dbname = $self->current_dataset_param('DBNAME')) {
        eval {
           $odba = $adaptor_class->new( -host       => $self->current_dataset_param('HOST'),
                                        -port       => $self->current_dataset_param('PORT'),
                                        -user       => $self->current_dataset_param('USER'),
                                        -pass       => $self->current_dataset_param('PASS'),
                                        -dbname     => $dbname,
                                        -group      => 'otter',
                                        -species    => $self->dataset_name,
                                        );
        };
        $self->error_exit("Failed opening otter database [$@]") if $@;

        $self->log("Connected to otter database");
    } else {
		$self->error_exit("Failed opening otter database [No database name]");
    }

    if(my $dna_dbname = $self->current_dataset_param('DNA_DBNAME')) {
        eval {
            $dnadb = new Bio::EnsEMBL::DBSQL::DBAdaptor( -host      => $self->current_dataset_param('DNA_HOST'),
                                                         -port      => $self->current_dataset_param('DNA_PORT'),
                                                         -user      => $self->current_dataset_param('DNA_USER'),
                                                         -pass      => $self->current_dataset_param('DNA_PASS'),
                                                         -dbname    => $dna_dbname,
                                                         -group     => 'dnadb',
                                                         -species   => $self->dataset_name,
                                                         );
        };
        $self->error_exit("Failed opening dna database [$@]") if $@;
        $odba->dnadb($dnadb);
        
        $self->log("Connected to dna database");
    }

    return $self->{'_odba'} = $odba;
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

    my %anycase_options = (
         -group     => $metakey,
         -species   => $self->dataset_name,
        eval $opt_str,
    );
    if ($@) {
        $self->error_exit("Error evaluating '$opt_str' : $@");
    }

    my %uppercased_options = ();
    while( my ($k,$v) = each %anycase_options) {
        $uppercased_options{uc($k)} = $v;
    }
    
    $self->error_exit("No connection parameters for '$metakey' in otter database")
        unless (keys %uppercased_options);

    my $sdba = $adaptor_class->new(%uppercased_options)
        || $self->error_exit("Couldn't connect to '$metakey' satellite db");


        # not the most beautiful way (and place) to do it :(
    my ($asm_def) = @{ $sdba->get_MetaContainer()->list_value_by_key('assembly.default') };
    if($asm_def =~ /^otter$/i) {
        bless $sdba,'Bio::Vega::DBSQL::DBAdaptor';
    }


        # if it's needed AND we can...
    $sdba->assembly_type($self->otter_dba()->assembly_type()) unless ($satehead || $running_headcode);

    $self->log("... with parameters: ".join(', ', map { "$_=".$uppercased_options{$_} } keys %uppercased_options ));

    return $self->{_sdba}{$metakey} = $sdba;
}

sub get_slice { # codebase-independent version for scripts
    my ($self, $dba, $cs, $name, $type, $start, $end, $csver) = @_;

    my $slice;

    $cs ||= 'chromosome'; # can't make a slice without cs

    if($self->running_headcode()) {

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
            1,      # somehow strand parameter is needed
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

sub return_emptyhanded { # we probably only want to know about it only if using MFetcher directly,
                         # otherwise it gets overloaded by ServerScriptSupport
    my ($self) = @_;

    $self->log("Slice could not have been created");
    exit(0);
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
        return (undef, $csver_orig);
    } elsif($metakey eq '.') {
        $self->log("Working with otter_db directly, no remapping is needed.");
        return (undef, $csver_orig);
    }

    $csver_remote = $self->cached_csver($metakey, $cs, $csver_remote);
    if($cs eq 'chromosome') {
        if($csver_remote =~/^otter$/i) {
            $self->log("Working with another Otter database, no remapping is needed.");
            return (undef, $csver_remote);
        } elsif($csver_remote eq 'UNKNOWN') {
            $self->log("The database's default assembly is not set correctly, but you can override it manually");
            return (undef, undef);
        }
    }

    if(!$self->running_headcode()) {
        $self->log("Working with unknown OLD API database, please do the remapping on client side.");
        return (undef, $csver_remote);
    }

    ## What remains is head version of a non-otter satellite_db

    my $edba = $self->satellite_dba( 'equiv_asm_db' ); # the value is either '=otter' (for new schema)
                                                       # or '=pipeline' (for old schema DB with new schema pipeline)

        # this slice does not have to be completely defined (no start/end/strand),
        # as we only need it to get the attributes
    my $equiv_slice = $self->get_slice($edba, $cs, $name, $type, undef, undef, undef, $csver_orig);

    my %asm_is_equiv = map { ($_->value() => 1) } @{ $equiv_slice->get_all_Attributes('equiv_asm') };

    if($asm_is_equiv{$csver_remote}) { # we can simply rename instead of mapping

        $self->log("This $cs is equivalent to '$name' in our reference '$csver_remote' assembly");
        return (undef, $csver_remote);

    } else { # assemblies are guaranteed to differ!

        my $mapper_metakey = "mapper_db.${csver_remote}";

        if( my $mdba = $self->satellite_dba($mapper_metakey) ) {
            return ($mdba, $csver_remote);
        } else {
            $self->log("No '$mapper_metakey' defined in meta table => cannot map between assemblies => exiting");
            return (undef, undef);
        }
    }
}

sub fetch_mapped_features {
    my ($self, $feature_name, $fetching_method, $call_parms,
        $cs, $name, $type, $start, $end, $metakey, $csver_orig, $csver_remote,
    ) = @_;

    $metakey      ||= '';    # defaults to pipeline
    $csver_orig   ||= undef; # defaults to NULL in the DB
    $csver_remote ||= undef; # defaults to NULL in the DB

    my $sdba = $self->satellite_dba( $metakey );
    my ($mdba, $csver_target) = $self->get_mapper_dba( $metakey, $cs, $csver_orig, $csver_remote, $name, $type);

    my $features = [];

    if($mdba) {
        $self->log("Proceeding with mapping code");

        my $original_slice_on_mapper = $self->get_slice($mdba, $cs, $name, $type, $start, $end, $csver_orig);
        my $proj_segments_on_mapper = $original_slice_on_mapper->project( $cs, $csver_target );

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
                = $target_slice_on_target->$fetching_method(@$call_parms) ||
                $self->error_exit("Could not fetch anything - analysis may be missing from the DB");

            $self->log('***** : '.scalar(@$target_fs_on_target_segment)." ${feature_name}s found on the slice");

            # foreach my $target_feature (@$target_fs_on_target_segment) {
            ## this is supposed to be faster:
            #
            while (my $target_feature = shift @$target_fs_on_target_segment) {

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

    } elsif(($cs ne 'chromosome') || defined($csver_target)) {
        $self->log("Assuming the mappings to be identical, just cross-fetching");

        my $original_slice = $self->get_slice($sdba, $cs, $name, $type, $start, $end, $csver_target);

        $features = $original_slice->$fetching_method(@$call_parms)
            || $self->error_exit("Could not fetch anything - analysis may be missing from the DB");
    } else {
            # some not-so-critical mapping error,
            # $features == []
    }

    $self->log("Total of ".scalar(@$features).' '.join('/', grep { defined($_) && !ref($_) } @$call_parms)
              ." ${feature_name}s have been sent to the client");

    return $features;
}

1;

