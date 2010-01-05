
package Bio::Otter::MFetcher;

# Previously a part of ServerScriptSupport,
# this module only deals with data layer:
# interprets the metakeys to create and manage DBAdaptors
# and performs mapping between assemblies.
#
# Author: lg4

use strict;
use warnings;
use Carp qw{ longmess };

use Bio::EnsEMBL::DBSQL::DBAdaptor;
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
    my ($self, $metakey, $may_be_absent) = @_;

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

    $self->log("connecting to the '$kind' using [$metakey] meta entry...");

    my $adaptor_class = 'Bio::EnsEMBL::DBSQL::DBAdaptor'; # get the minimal adaptor (may be extended to Vega in future)

    my ($opt_str) = @{ $self->otter_dba()->get_MetaContainer()->list_value_by_key($metakey) };

    if(!$opt_str) {
        if($may_be_absent) {
            $self->log("cannot connect to metakey='$metakey' as this key is not defined in the meta table.");
            return;
        } else {
            $self->error_exit(longmess("Could not find meta entry for '$metakey' satellite db"));
        }
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

sub get_slice {
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
    my ($segment_attr, $segment_name) = (($cs eq 'chromosome') && ($csver eq 'Otter'))
        ? ('type', $type)
        : ('name', $name);

    $self->error_exit("$cs '$segment_attr' attribute not set") unless $segment_name;

    $slice =  $dba->get_SliceAdaptor()->fetch_by_region(
        $cs,
        $segment_name,
        $start,
        $end,
        1,      # somehow strand parameter is needed
        $csver,
    );
    
    $self->check_slice($slice);

    unless ($slice) {
        $self->log('Could not get a slice, probably not (yet) loaded into satellite db');
        $self->return_emptyhanded();
    }

    return $slice;
}

sub check_slice {
    my ($self, $slice) = @_;
    
    my $slice_projection = $slice->project('contig');

    my (%contig_strand, @both_strands_used);
    foreach my $seg (@$slice_projection) {
        my $contig_slice = $seg->to_Slice();
        my $name    = $contig_slice->seq_region_name;
        my $strand  = $contig_slice->strand;
        if (my $ns = $contig_strand{$name}) {
            if ($ns ne 'BOTH' and $ns != $strand) {
                push(@both_strands_used, $name);
                $contig_strand{$name} = 'BOTH';
            }
        }
        else {
            $contig_strand{$name} = $strand;
        }
    }
    if (@both_strands_used) {
        my $ctg = @both_strands_used == 1 ? 'this contig uses' : 'these contigs use';
        $self->error_exit("Smap will fail because $ctg both strands in the assembly: @both_strands_used");
    }
}

sub return_emptyhanded { # we probably only want to know about it only if using MFetcher directly,
                         # otherwise it gets overloaded by ServerScriptSupport
    my ($self) = @_;

    $self->log("Slice could not have been created");
    exit(0);
}

sub otter_assembly_equiv_hash { # $self->{_aeh}{NCBI36}{11} = 'chr11-02';
    my $self = shift;

    if (my $aeh = $self->{'_aeh'}) {
        return $aeh;
    }

    my $edba = $self->satellite_dba( 'equiv_asm_db' ); # the value is either '=otter' (for new schema)
                                                       # or '=pipeline' (for old schema DB with new schema pipeline)
    my $sql = qq{
        SELECT ae_val.value
          , cn_val.value
          , sr.name
        FROM seq_region sr
          , seq_region_attrib ae_val
          , seq_region_attrib cn_val
          , seq_region_attrib hi_val
          , attrib_type ae_at
          , attrib_type cn_at
          , attrib_type hi_at
        WHERE sr.seq_region_id = ae_val.seq_region_id
          AND ae_val.attrib_type_id = ae_at.attrib_type_id
          AND ae_at.code = 'equiv_asm'
          AND sr.seq_region_id = cn_val.seq_region_id
          AND cn_val.attrib_type_id = cn_at.attrib_type_id
          AND cn_at.code = 'chr'
          AND hi_at.code = 'hidden'
          AND hi_val.attrib_type_id = hi_at.attrib_type_id
          AND sr.seq_region_id = hi_val.seq_region_id
          AND hi_val.value = 0
        };

    my $sth = $edba->dbc()->prepare($sql);
    $sth->execute();

    my $aeh = $self->{'_aeh'} = {};
    while( my ($equiv_asm, $equiv_chr, $atype) = $sth->fetchrow()) {
        $aeh->{$equiv_asm}{$equiv_chr} = $atype;
    }
    return $aeh;
}

sub otter_assembly_mapping_hash { ## $self->{_amh}{NCBIM37}{11} = 'chr11-07';
                                  ## Note that 1st level hashes are filled independently.
    my ($self, $csver_remote) = @_;

    my $amh_sub;
    if($amh_sub = $self->{_amh}{$csver_remote}) {
        return $amh_sub;
    } else { # $self->{_amh} gets autovivified anyway, but it may not be true for the next level
        $amh_sub = $self->{_amh}{$csver_remote} = {};
    }

    my $mapper_metakey = "mapper_db.${csver_remote}";
    if(my $mdba = $self->satellite_dba($mapper_metakey) ) {
        my $sql = qq{
            SELECT DISTINCT cmp.name,asm.name
              FROM assembly a, seq_region asm, seq_region cmp, coord_system asm_cs, coord_system cmp_cs
             WHERE a.asm_seq_region_id=asm.seq_region_id
               AND a.cmp_seq_region_id=cmp.seq_region_id
               AND asm.coord_system_id=asm_cs.coord_system_id
               AND cmp.coord_system_id=cmp_cs.coord_system_id
               AND asm_cs.name='chromosome'
               AND asm_cs.version='Otter'
               AND cmp_cs.name='chromosome'
               AND cmp_cs.version=?
          ORDER BY cmp_cs.version, cmp.name
        };
        my $sth = $mdba->dbc()->prepare($sql);
        $sth->execute($csver_remote);

        while( my ($remote_chr, $atype) = $sth->fetchrow()) {
            $amh_sub->{$remote_chr} = $atype;
        }
        return $amh_sub;
    } else {
        die "Can't connect to the mapper ($mapper_metakey)";
    }
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

    # fetch things from Otter chromosome and map them to another assembly
sub fetch_and_export {
    my ($self, $fetching_method, $call_parms,
        $cs, $name, $type, $start, $end, $csver_orig, $csver_target,
    ) = @_;

    my $odba = $self->otter_dba();
    my $original_slice = $self->get_slice($odba, $cs, $name, $type, $start, $end, $csver_orig);

    my $orig_features = $original_slice->$fetching_method(@$call_parms) || die "Could not fetch anything";

    if ($self->otter_assembly_equiv_hash()->{$csver_target}{$name} eq $type) {
        # no transformation is needed:

        return $orig_features;

    } else {
        # do the transformation if it is needed:

        my $mapper_metakey = "mapper_db.${csver_target}";
        if (my $mdba = $self->satellite_dba($mapper_metakey) ) {
            my $original_slice_on_mapper = $self->get_slice($mdba, $cs, $name, $type, $start, $end, $csver_orig);

            my $transformed_features = [];

            foreach my $orig_feature (@$orig_features) {

                    # move each feature to the mapper first:
                if($orig_feature->can('propagate_slice')) {
                    $orig_feature->propagate_slice($original_slice_on_mapper);
                } else {
                    $orig_feature->slice($original_slice_on_mapper);
                }

                if( my $target_feature = $orig_feature->transform($cs, $csver_target) ) {
                    push @$transformed_features, $target_feature;
                    warn "Transformed $csver_orig:".$original_slice_on_mapper->name.":".$orig_feature->start().'..'.$orig_feature->end()
                        ." --> $csver_target:".$target_feature->start().'..'.$target_feature->end()."\n";
                } else {
                    warn "Could not transform the feature ".$original_slice_on_mapper->name." ".
		          $orig_feature->start().'..'.$orig_feature->end();
                }
            }

            return $transformed_features;

        } else {
            die "Can't connect to the mapper ($mapper_metakey)";
        }
    }
}

sub map_remote_slice_back {
    my ($self, $remote_slice) = @_;

    my $cs              = $remote_slice->coord_system()->name();
    my $csver_remote    = $remote_slice->coord_system()->version();

    unless($cs eq 'chromosome') {
        $self->log("We do not yet perform mapping from $cs:$csver_remote to Otter chromosomes");
        return [];
    }

    my $remote_chr_name = $remote_slice->seq_region_name();
    my $local_sa = $self->otter_dba()->get_SliceAdaptor();

    if(my $otter_chr_name = $self->otter_assembly_equiv_hash()->{$csver_remote}{$remote_chr_name}) {
            # chromosomes are equivalent, re-create the slice on loutre_db:

        my $local_slice = $local_sa->fetch_by_region(
            'chromosome',
            $otter_chr_name,
            $remote_slice->start(),
            $remote_slice->end(),
            $remote_slice->strand(),
            'Otter',
        );

        return [ $local_slice ];

    } else {
        # otherwise perform the mapping back:

        my $mapper_metakey = "mapper_db.${csver_remote}";
        if(my $mdba = $self->satellite_dba($mapper_metakey) ) {

            my $remote_slice_on_mapper = $mdba->get_SliceAdaptor()->fetch_by_region(
                $remote_slice->coord_system()->name(),
                $remote_slice->seq_region_name(),
                $remote_slice->start(),
                $remote_slice->end(),
                $remote_slice->strand(),
                $remote_slice->coord_system()->version(),
            );

            my @local_slices = ();
            foreach my $proj_segment (@{ $remote_slice_on_mapper->project('chromosome', 'Otter') }) {
                my $local_slice_on_mapper = $proj_segment->to_Slice();

                my $local_slice = $local_sa->fetch_by_region(
                    $local_slice_on_mapper->coord_system()->name(),
                    $local_slice_on_mapper->seq_region_name(),
                    $local_slice_on_mapper->start(),
                    $local_slice_on_mapper->end(),
                    $local_slice_on_mapper->strand(),
                    $local_slice_on_mapper->coord_system()->version(),
                );
                push @local_slices, $local_slice;
            }

            if(my $results = scalar(@local_slices)) {
                if($results>1) {
                    $self->log("Could not uniquely map '$csver_remote' slice to 'Otter' (got $results pieces)");
                }
            } else {
                $self->log("Could not map '$csver_remote' slice to 'Otter' at all");
            }
            return \@local_slices;

        } else { # if it wasn't possible to connect to the mapper
            $self->error_exit("No '$mapper_metakey' defined in meta table => cannot map between assemblies");
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
       || ( ($self->otter_assembly_equiv_hash()->{$csver_remote}{$name} || '') eq $type) ) {
                # no mapping, just (cross)-fetching:

        my $csver_target = (!$metakey || ($metakey eq '.'))
                ? $csver_orig
                : $csver_remote;

        $self->log("Assuming the mappings to be identical, just fetching from {$metakey}$cs:$csver_target");

        my $sdba = $self->satellite_dba( $metakey );
        my $original_slice = $self->get_slice($sdba, $cs, $name, $type, $start, $end, $csver_target);

        $features = $original_slice->$fetching_method(@$call_parms);

        unless($features) {
            die "Could not fetch anything - analysis may be missing from the DB";
        }

    } else { # let's try to do the mapping:

        my $mapper_metakey = "mapper_db.${csver_remote}";

        if( my $mdba = $self->satellite_dba($mapper_metakey) ) {

            $self->log("Proceeding with mapping code");

            my $original_slice_on_mapper = $self->get_slice($mdba, $cs, $name, $type, $start, $end, $csver_orig);

            my $proj_segments_on_mapper;
            eval {
                $proj_segments_on_mapper = $original_slice_on_mapper->project( $cs, $csver_remote );
                # Try to map to scaffold if coordinate system exists and mapping to chromosome failed
                # allow getting ensembl objects from Zfish scaffolds
                if(!@$proj_segments_on_mapper && $mdba->get_CoordSystemAdaptor->fetch_by_name('scaffold',$csver_remote)) {
					$proj_segments_on_mapper = $original_slice_on_mapper->project( 'scaffold', $csver_remote );
                }
            };
            if ($@ || ! @$proj_segments_on_mapper) {
                die "Unable to project: $type:$csver_orig($start..$end)->$csver_remote. Check the mapping.\n$@";
            }
            $self->log("Found ".scalar(@$proj_segments_on_mapper)." projection segments on mapper when projecting to $cs:$csver_remote");

	    # group the projected slices by their chromosome and,
	    # for each chromosome, calculate the endpoints of the
	    # slice that just covers all the projected slices on
	    # that chromosome

	    my $amalgamated_endpoints = { };
	    my $proj_slices_on_mapper;

	    foreach my $segment (@$proj_segments_on_mapper) {
		my $slice = $segment->to_Slice;
		my $chromosome = $slice->seq_region_name;
		my $start0 = $amalgamated_endpoints->{$chromosome}[0];
		my $start1 = $slice->start;
		my $end0 = $amalgamated_endpoints->{$chromosome}[1];
		my $end1 = $slice->end;
		$amalgamated_endpoints->{$chromosome}[0] = $start1 unless
		    defined $start0 && $start0 <= $start1;
		$amalgamated_endpoints->{$chromosome}[1] = $end1 unless
		    defined $end0 && $end0 >= $end1;
	    }

	    # create the amalgamated slices
	    my $strand = $original_slice_on_mapper->strand;
	    my $adaptor = $original_slice_on_mapper->adaptor;
	    $proj_slices_on_mapper = [ map {
		my $seq_region_name = $_;
		my ( $start, $end ) = @{$amalgamated_endpoints->{$_}};
		$adaptor->fetch_by_region($cs, $seq_region_name,
					  $start, $end, $strand, $csver_remote,);
	    } keys %$amalgamated_endpoints ];

            if($das_style_mapping) { # In this mode there is no target_db involved.
                                     # Features are put directly on the mapper target slice and then mapped back.
                foreach my $projected_slice_on_mapper (@$proj_slices_on_mapper) {

                    my $target_fs_on_mapper_segment
                        = $projected_slice_on_mapper->$fetching_method(@$call_parms);

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

                SEGMENT: foreach my $projected_slice_on_mapper (@$proj_slices_on_mapper) {

                    my $target_slice_on_target = $sa_on_target->fetch_by_region(
                        $projected_slice_on_mapper->coord_system()->name(),
                        $projected_slice_on_mapper->seq_region_name(),
                        $projected_slice_on_mapper->start(),
                        $projected_slice_on_mapper->end(),
                        $projected_slice_on_mapper->strand(),
                        $projected_slice_on_mapper->coord_system()->version(),
                    );

                    unless($target_slice_on_target) {
                        warn "MFetcher: cannot create the slice ["
                                .$projected_slice_on_mapper->coord_system()->name()
                                .':'
                                .$projected_slice_on_mapper->seq_region_name()
                                .':'
                                .$projected_slice_on_mapper->start()
                                .':'
                                .$projected_slice_on_mapper->end()
                                .':'
                                .$projected_slice_on_mapper->strand()
                                .':'
                                .$projected_slice_on_mapper->coord_system()->version()
                                ."] on target, please check the target.\n";
                        next SEGMENT; # it may be mappable, but not applicable!
                    }

                    my $target_fs_on_target_segment
                        = $target_slice_on_target->$fetching_method(@$call_parms) ||
                            die "Could not fetch anything - possible problem with external source";

                    $self->log('***** : '.scalar(@$target_fs_on_target_segment)." ${feature_name}s found on the slice $metakey:".$target_slice_on_target->start().'..'.$target_slice_on_target->end());

                    # foreach my $target_feature (@$target_fs_on_target_segment) {
                    # This is supposed to be faster:
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


