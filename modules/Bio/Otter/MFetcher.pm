package Bio::Otter::MFetcher;

# Previously a part of ServerScriptSupport,
# this module only deals with data layer:
# interprets the metakeys to create and manage DBAdaptors
# and performs mapping between assemblies.
#
# Author: lg4

use strict;
use warnings;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::Otter::DBSQL::DBAdaptor;
use Bio::Vega::DBSQL::DBAdaptor;

use base ('Bio::Otter::SpeciesDat');

sub new { # just to make it possible to instantiate an object
    my $pkg = shift @_;

    my $self = bless { @_ }, $pkg;

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

sub otter_dba {
    my $self = shift @_;

    if($self->{'_odba'} && !scalar(@_)) {   # cached value and no override
        return $self->{'_odba'};
    }

    my $adaptor_class = 'Bio::Vega::DBSQL::DBAdaptor';

    if(@_) { # let's check that the class is ok
        my $odba = shift @_;
        if(UNIVERSAL::isa($odba, $adaptor_class)) {
            return $self->{'_odba'} = $odba;
        } else {
            die "The object you assign to otter_dba must be a '$adaptor_class'";
        }
    }


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

sub default_assembly {
    my ($self, $dba) = @_;

    my ($asm_def) = @{ $dba->get_MetaContainer()->list_value_by_key('assembly.default') };

    return $asm_def || 'UNKNOWN';
}

sub satellite_dba {
    my ($self, $metakey) = @_;

    # Note: as multiple satellite_db's can be used, we have to explicitly send $metakey

    $metakey ||= '';

        # It may well be true that the caller
        # is interested in features from otter_db itself.
        # (This is NOT the default behaviour,
        #  so he has to specify it by setting metakey='.')

    if($metakey eq '.') {
        $self->log("Connecting to the otter_db itself");
        return $self->otter_dba();
    }

    my $kind;

    if(! $metakey) {
        $metakey = 'pipeline_db_head';
        $kind    = 'pipeline DB'
    } else {
        $kind    = 'satellite DB';
    }

    if($self->{_sdba}{$metakey}) {
        $self->log("Get the cached [$metakey] adapter...");
        return $self->{_sdba}{$metakey};
    }

    $self->log("connecting to the $kind using [$metakey] meta entry...");

    my $adaptor_class = 'Bio::EnsEMBL::DBSQL::DBAdaptor'; # get the minimal adaptor (may be extended to Vega in future)

    my ($opt_str) = @{ $self->otter_dba()->get_MetaContainer()->list_value_by_key($metakey) };

    if(!$opt_str) {
        $self->error_exit("Could not find meta entry for '$metakey' satellite db");
    } elsif($opt_str =~ /^\=otter/) {
        return $self->otter_dba();
    } elsif($opt_str =~ /^\=pipeline/) {
        return $self->satellite_dba('');
    } elsif($opt_str =~ /^\=(\w+)$/) {
        return $self->satellite_dba($1);
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

        # Unfortunately we can only do it once the connection established, hence re-blessing:
    if( lc($self->default_assembly($sdba)) eq 'otter') {
        bless $sdba,'Bio::Vega::DBSQL::DBAdaptor';
    }

    $self->log("... with parameters: ".join(', ', map { "$_=".$uppercased_options{$_} } keys %uppercased_options ));

    return $self->{_sdba}{$metakey} = $sdba;
}

sub get_slice { # codebase-independent version for scripts
    my ($self, $dba, $cs, $name, $type, $start, $end, $csver) = @_;

    my $slice;

    $cs ||= 'chromosome'; # can't make a slice without cs

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

sub otter_assemby_is_equivalent { # to the desired $csver_remote
    my ($self, $cs, $name, $type, $csver_orig, $csver_remote) = @_;

    my $edba = $self->satellite_dba( 'equiv_asm_db' ); # the value is either '=otter' (for new schema)
                                                       # or '=pipeline' (for old schema DB with new schema pipeline)

        # this slice does not have to be completely defined (no start/end/strand),
        # as we only need it to get the attributes
    my $equiv_slice = $self->get_slice($edba, $cs, $name, $type, undef, undef, undef, $csver_orig);

    my %asm_is_equiv = map { ($_->value() => 1) } @{ $equiv_slice->get_all_Attributes('equiv_asm') };

    return $asm_is_equiv{$csver_remote};
}

sub init_csver {
    my ($self, $cs, $metakey) = @_; # metakey can even be '.' or ''

    if($cs eq 'chromosome') {
        if(!$metakey || ($metakey eq '.')) {
            return 'Otter'; # just for saving time,
                            # as we know already that otter and pipeline databases should have 'Otter'
                            # as their meta.'assembly.default' value
        } else {
            return $self->default_assembly($self->satellite_dba($metakey));
        }
    } else {
        return undef;  # defaults to NULL in the DB
    }
}

    # fetch things from Otter chromosome and map it to another assembly
sub fetch_and_export {
    my ($self, $fetching_method, $call_parms,
        $cs, $name, $type, $start, $end, $csver_orig, $csver_target,
    ) = @_;

    my $odba = $self->otter_dba();
    my $original_slice = $self->get_slice($odba, $cs, $name, $type, $start, $end, $csver_orig);

    my $orig_features = $original_slice->$fetching_method(@$call_parms) || die "Could not fetch anything";

    if($self->otter_assemby_is_equivalent($cs, $name, $type, $csver_orig, $csver_target)) {
        # no transformation is needed:

        return $orig_features;

        # do the transformation if it is needed:
    } else {

        my $mapper_metakey = "mapper_db.${csver_target}";
        if(my $mdba = $self->satellite_dba($mapper_metakey) ) {
            my $original_slice_on_mapper = $self->get_slice($mdba, $cs, $name, $type, $start, $end, $csver_orig);

            my @transformed_features = ();

            foreach my $orig_feature (@$orig_features) {

                    # move each feature to the mapper first:
                if($orig_feature->can('propagate_slice')) {
                    $orig_feature->propagate_slice($original_slice_on_mapper);
                } else {
                    $orig_feature->slice($original_slice_on_mapper);
                }

                if( my $target_feature = $orig_feature->transform($cs, $csver_target) ) {
                    push @transformed_features, $target_feature;
                    warn "Transformed $csver_orig:".$orig_feature->start().'..'.$orig_feature->end()
                        ." --> $csver_target:".$target_feature->start().'..'.$target_feature->end()."\n";
                } else {
                    warn "Could not transform the feature ".$orig_feature->start().'..'.$orig_feature->end();
                }
            }

            return \@transformed_features;

        } else {
            die "Can't connect to the mapper ($mapper_metakey)";
        }

    }
}

sub fetch_mapped_features {
    my ($self, $feature_name, $fetching_method, $call_parms,
        $cs, $name, $type, $start, $end, $metakey, $csver_orig, $csver_remote,
        $das_style_mapping,
    ) = @_;

    $metakey      ||= ''; # defaults to pipeline
    $cs           ||= 'chromosome';
    $csver_orig   ||= $self->init_csver($cs, '');
    $csver_remote ||= $self->init_csver($cs, $metakey);

    my $features = [];

    if( ($cs ne 'chromosome') || ($csver_orig eq $csver_remote)
       || $self->otter_assemby_is_equivalent($cs, $name, $type, $csver_orig, $csver_remote) ) {
                # no mapping, just (cross)-fetching:

        my $csver_target = (!$metakey || ($metakey eq '.'))
                ? $csver_orig
                : $csver_remote;

        $self->log("Assuming the mappings to be identical, just fetching from {$metakey}$cs:$csver_target");

        my $sdba = $self->satellite_dba( $metakey );
        my $original_slice = $self->get_slice($sdba, $cs, $name, $type, $start, $end, $csver_target);

        $features = $original_slice->$fetching_method(@$call_parms)
            || $self->error_exit("Could not fetch anything - analysis may be missing from the DB");

    } else { # let's try to do the mapping:

        my $mapper_metakey = "mapper_db.${csver_remote}";

        if( my $mdba = $self->satellite_dba($mapper_metakey) ) {

            $self->log("Proceeding with mapping code");

            my $original_slice_on_mapper = $self->get_slice($mdba, $cs, $name, $type, $start, $end, $csver_orig);

            my $proj_segments_on_mapper;
            eval {
                $proj_segments_on_mapper = $original_slice_on_mapper->project( $cs, $csver_remote );
            };
            if($@) {
                die "Unable to project: $type:$csver_orig($start..$end)->$csver_remote. Check the mapping.";
            }

            if($das_style_mapping) { # In this mode there is no target_db involved.
                                     # Features are put directly on the mapper target slice and then mapped back.
                foreach my $segment (@$proj_segments_on_mapper) {
                    my $projected_slice_on_mapper = $segment->to_Slice();

                    my $target_fs_on_mapper_segment
                        = $projected_slice_on_mapper->$fetching_method(@$call_parms) ||
                            $self->error_exit("Could not fetch anything - analysis may be missing from the DB");

                    $self->log('***** : '.scalar(@$target_fs_on_mapper_segment)." ${feature_name}s created on the slice");

                    while (my $target_feature = shift @$target_fs_on_mapper_segment) {
                        my $fname = sprintf( "%s [%d..%d]", 
                                            $target_feature->display_id(),
                                            $target_feature->start(),
                                            $target_feature->end() );
                        $self->log("Transferring $feature_name $fname from {".$target_feature->slice->name
                                   ."} onto {".$original_slice_on_mapper->name.'}');
                        if( my $transferred = $target_feature->transfer($original_slice_on_mapper) ) {
                            push @$features, $transferred;
                            $self->log("Transfer OK");
                        } else {
                            $self->log("Transfer failed");
                        }
                    }
                }

            } else { # full mapping with target database involved

                my $sdba = $self->satellite_dba( $metakey );
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

                    $self->log('***** : '.scalar(@$target_fs_on_target_segment)." ${feature_name}s found on the slice $metakey:".$target_slice_on_target->start().'..'.$target_slice_on_target->end());

                    # foreach my $target_feature (@$target_fs_on_target_segment) {
                    ## this is supposed to be faster:
                    #
                    while (my $target_feature = shift @$target_fs_on_target_segment) {

                        if($target_feature->can('propagate_slice')) {
                            $target_feature->propagate_slice($projected_slice_on_mapper);
                        } else {
                            $target_feature->slice($projected_slice_on_mapper);
                        }

                        my $fname = sprintf( "%s [%d..%d]", 
                                            $target_feature->display_id(),
                                            $target_feature->start(),
                                            $target_feature->end() );
                        $self->log("Transferring $feature_name $fname from {".$target_feature->slice->name
                                   ."} onto {".$original_slice_on_mapper->name.'}');
                        if( my $transferred = $target_feature->transfer($original_slice_on_mapper) ) {
                            push @$features, $transferred;
                            $self->log("Transfer OK");
                        } else {
                            $self->log("Transfer failed");
                        }
                    } # for each feature
                } # for each segment
            }

        } else { # if it wasn't possible to connect to the mapper
            $self->error_exit("No '$mapper_metakey' defined in meta table => cannot map between assemblies");
        }
    }

    $self->log("Total of ".scalar(@$features).' '.join('/', grep { defined($_) && !ref($_) } @$call_parms)
              ." ${feature_name}s have been sent to the client");

    return $features;
}

1;

__END__

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk


