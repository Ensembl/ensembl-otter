### Bio::Otter::Lace:ResultSet
## this object is used to store the results of a search for a particular clone.
## sequence sets are now stored in an array so they should come out in order,
## but there is no check that a sequence set already exists

package Bio::Otter::Lace::ResultSet;
use Data::Dumper ;
use strict;
use Carp;

my $DEBUG = 0;

sub new {
    my $pkg = shift;
    
    return bless {}, $pkg;
}

# possibly the most evil thing I've done in this module.
# extends the CloneSequence obj
sub Bio::Otter::Lace::CloneSequence::is_match{
    my ($self, $is_match) = @_;
    $self->{'_is_match'} = $is_match if defined($is_match);
    return $self->{'_is_match'};
}

sub add_SequenceSet{
    my ($self, $ss) = @_ ;
    $self->{'_rs_sequence_sets'} ||= [];
    push(@{$self->{'_rs_sequence_sets'}}, $ss);
}

sub get_SequenceSet_by_name{
    my ($self , $name ) = @_ ;

    confess "I can't fetch without a name" unless $name;

    foreach my $ss ( @{$self->get_all_SequenceSets} ){
        if ($ss->name eq $name) {
            return $ss;
        }
    }
    return;
}

sub get_all_SequenceSets{
    my ($self) = @_;
    return $self->{'_rs_sequence_sets'};
}

sub search_array{
    my ($self , $string) = @_ ;
    if ($string){
        $self->{'_search_string'} = $string ;           
    }
    return $self->{'_search_string'}; 
}

sub search_type{
    my ($self , $type) = @_;

    if ($type){
        $self->{'search_type'} = $type ;
    }
    return $self->{'search_type'};
}

#------------
sub DataSet{
    my ( $self , $ds ) = @_ ; 
    
    if ($ds){
        $self->{'_DataSet'} = $ds ;
    }else{
        return $self->{'_DataSet'} || confess "No DataSet in the ResultSet object" ;
    }
}

sub execute_search{
    my ( $self , $search_list ) = @_ ;

    if ($self->search_type eq 'locus'){
        $self->fetch_Clones_containing_locus($search_list) ;
    }elsif($self->search_type eq 'stable_id'){
        $self->fetch_Clones_containing_stable_id($search_list) ;
    }else{
        $self->fetch_Clones_containing_CloneNames($search_list) ;
    }
}
sub fetch_Clones_containing_stable_id{
    my ($self, $stable_ids) = @_;

    confess "Missing locus name argument " unless ($stable_ids);

    my $dba = $self->DataSet->get_cached_DBAdaptor ;    
    my $meta_con = $dba->get_MetaContainer();

    my $prefix_primary = $meta_con->get_primary_prefix() || confess "Missing prefix.primary in meta table ";
    my $prefix_species = $meta_con->get_species_prefix() || confess "Missing prefix.species in meta table ";

    my $stable_id_types = {};
    foreach my $id(@$stable_ids){
        if($id =~ /^$prefix_primary$prefix_species([TPG])\d+/i){
            push(@{$stable_id_types->{uc $1}}, $id);
        }else{
            print STDERR "'$id' doesn't look like a stable id. It doesn't start with '$prefix_primary$prefix_species'\n";
        }
    }

    my $geneAdapt       = $dba->get_GeneAdaptor();
    my $transcriptAdapt = $dba->get_TranscriptAdaptor();
    my $clone_names     = {};

    $stable_id_types->{'G'} ||= [];
    foreach my $stable_id (@{$stable_id_types->{'G'}}){
        eval{
            print STDERR "Looking for '$stable_id' and assuming it's a gene\n";
            my $geneObj     = $geneAdapt->fetch_by_stable_id($stable_id);
            # print STDERR "Found '$stable_id' with version " . $geneObj->version . "\n";
            foreach my $exonObj(@{$geneObj->get_all_Exons}){
                my $clone_name = $exonObj->contig->clone->id();
                #print STDERR "Found '$clone_name'\n";
                $clone_names->{$clone_name} = 1;
            }
        };        
        if ($@){
            ## assume error was caused by not being able to create a $geneNameObjList - as name didnt exist
            #print STDERR "nothing found for $stable_id" ; 
        }
    }

    $stable_id_types->{'T'} ||= [];
    foreach my $stable_id (@{$stable_id_types->{'T'}}){
        eval{
            print STDERR "Looking for '$stable_id' and assuming it's a transcript\n";
            my $transcriptObj     = $transcriptAdapt->fetch_by_stable_id($stable_id);
            # print STDERR "Found '$stable_id' with version " . $transcriptObj->version . "\n";
            foreach my $exonObj(@{$transcriptObj->get_all_Exons}){
                my $clone_name = $exonObj->contig->clone->id();
                #print STDERR "Found '$clone_name'\n";
                $clone_names->{$clone_name} = 1;
            }
        };        
        if ($@){
            ## assume error was caused by not being able to create a $geneNameObjList - as name didnt exist
            print STDERR "nothing found for $stable_id" ; 
        }
    }

    $stable_id_types->{'P'} ||= [];
    foreach my $stable_id (@{$stable_id_types->{'P'}}){
        eval{
            print STDERR "Looking for '$stable_id' and assuming it's a translation\n";
            my $transcriptObj     = $transcriptAdapt->fetch_by_translation_stable_id($stable_id);
            print STDERR "Found transcript with id '".$transcriptObj->stable_id."' & version " . $transcriptObj->version . "\n";
            foreach my $exonObj(@{$transcriptObj->get_all_Exons}){
                my $clone_name = $exonObj->contig->clone->id();
                #print STDERR "Found '$clone_name'\n";
                $clone_names->{$clone_name} = 1;
            }
        };        
        if ($@){
            ## assume error was caused by not being able to create a $geneNameObjList - as name didnt exist
            print STDERR "nothing found for $stable_id" ; 
        }

    }

    my @cl_names = keys(%$clone_names);
    if (@cl_names){
        print STDERR "Found " . join(', '=> @cl_names)  . "\n";
        return $self->fetch_Clones_containing_CloneNames( \@cl_names);    
    }
    else{
        return 0 ;
    }    
}

sub fetch_Clones_containing_locus{
    my ($self, $locus_names) = @_ ;
    
    confess "Missing locus name argument " unless ($locus_names);
    
    my $locus_names_string = join(',', map "'$_'", @$locus_names);

    my $dba = $self->DataSet->get_cached_DBAdaptor ;    
    
    my $geneNameAdapt = $dba->get_GeneNameAdaptor();
    my $geneInfoAdapt = $dba->get_GeneInfoAdaptor();
    my $geneAdapt     = $dba->get_GeneAdaptor();
    my $clone_names   = {};
    
    foreach my $locus_name (@$locus_names){
        eval{
            print STDERR "Looking for $locus_name\n";
            my $geneNameObjList = $geneNameAdapt->fetch_by_name($locus_name);
            foreach my $geneNameObj (@$geneNameObjList){
                my $geneInfoObj = $geneInfoAdapt->fetch_by_dbID($geneNameObj->gene_info_id());    
                my $geneObj     = $geneAdapt->fetch_by_stable_id($geneInfoObj->gene_stable_id());
                foreach my $exonObj(@{$geneObj->get_all_Exons}){
                    my $clone_name = $exonObj->contig->clone->id();
                    print STDERR "Found '$clone_name'\n";
                    $clone_names->{$clone_name} = 1;
                }
            }
        };
        
        if ($@){
            ## assume error was caused by not being able to create a $geneNameObjList - as name didnt exist
            print STDERR "nothing found for $locus_name" ; 
        }
    }
    my @cl_names = keys(%$clone_names);
    print STDERR "Found " . join(', '=> @cl_names)  . "\n";
    if (@cl_names){
        return $self->fetch_Clones_containing_CloneNames( \@cl_names);    
    }
    else{
        return 0 ;
    }
}

sub fetch_Clones_containing_CloneNames{
    my ($self , $clone_names) = @_ ;
    
    # this bit is not really necessary, but may be useful if we want a 'refresh' option 
    if ($clone_names){
        $self->search_array($clone_names) ;
    }else{
        $clone_names = $self->search_array;
    }
    confess "Missing clone names argument " unless $clone_names ;
    
    my $clone_names_string = join(',', map "'$_'", @$clone_names);
    warn "looking for clone names $clone_names_string" if $DEBUG;
 
    
    my $dba= $self->DataSet->get_cached_DBAdaptor ;
    my %id_chr = map {$_->chromosome_id, $_} $self->DataSet->get_all_Chromosomes;
    my %cs_hash ;

    my $results = 0;
    my $sth = $dba->prepare (qq{
        SELECT 
--            DISTINCT 
            cl.name, cl.embl_acc, cl.embl_version 
            , c.contig_id, c.name, c.length	
            , a.chromosome_id, a.chr_start, a.chr_end
            , a.contig_start, a.contig_end, a.contig_ori
            , a.type
            , lk.clone_lock_id
        FROM assembly a, contig c STRAIGHT_JOIN clone cl
        LEFT JOIN clone_lock lk ON lk.clone_id = cl.clone_id
        WHERE cl.clone_id = c.clone_id
        AND a.contig_id = c.contig_id
        AND (cl.name IN ($clone_names_string)
             OR cl.embl_acc IN ($clone_names_string)
             OR CONCAT(cl.embl_acc, '.', cl.embl_version) IN ($clone_names_string))
        ORDER BY a.chromosome_id , a.chr_start
    });

    $sth->execute();
    my(  $name, $acc,  $sv,
         $ctg_id,  $ctg_name,  $ctg_length,
         $chr_id,  $chr_start,  $chr_end,
         $contig_start,  $contig_end,  $strand,
         $type ,
         $clone_lock_id );
    $sth->bind_columns(
        \$name, \$acc, \$sv,
        \$ctg_id, \$ctg_name, \$ctg_length,
        \$chr_id, \$chr_start, \$chr_end,
        \$contig_start, \$contig_end, \$strand,
        \$type ,
        \$clone_lock_id
        );
    # add each CS to a diff anonymous array according to its assembly type - all the  
    while ($sth->fetch) {
        my $cl = Bio::Otter::Lace::CloneSequence->new;
        $cl->clone_name($name);
        $cl->accession($acc);
        $cl->sv($sv);
        $cl->length($ctg_length);
        $cl->chromosome($id_chr{$chr_id});
        $cl->chr_start($chr_start);
        $cl->chr_end($chr_end);
        $cl->contig_start($contig_start);
        $cl->contig_end($contig_end);
        $cl->contig_strand($strand);
        $cl->contig_name($ctg_name);
        $cl->contig_id($ctg_id);
        $cl->is_match(1);
        if (defined $clone_lock_id){
            $cl->set_lock_status(1) ;
        }   
        push ( @{ $cs_hash{$type} }  , $cl )  ;
        $results ++ ;      
    }

    # for each element of the hash, create a sequenceSet and add it to the ResultSet
    while ( my ($type , $cs_list)  = each (%cs_hash) ){
        my $ss = $self->uncached_SequenceSet_by_name($type);
        $ss->CloneSequence_list($cs_list);
#        $self->DataSet->status_refresh_for_SequenceSet($ss);
        $self->add_SequenceSet($ss);
    }
    $self->get_context_and_intron_clones();
    ## sets the things in ResultSet, but the return value is the number of clones returned
    return $results ;
}

sub get_context_and_intron_clones{
    my ($self) = @_;

    my $context_size = $self->context_size();
    # return unless $context_size;
    
    my $ss_list = $self->get_all_SequenceSets ;  
    my $ds = $self->DataSet;

    foreach my $ss (@$ss_list){ 
        my @cs_assembly_list = ();
        my $ss_assembly = $ss->name();
        $ds->fetch_all_SequenceNotes_for_SequenceSet($ss);
        my $results_list = $ss->CloneSequence_list;

        my ($first_idx, $last_idx, $full_ss_size, @prefix_slice, @postfix_slice);

        # must do this to stop caching
        my $full_ss      = $self->uncached_SequenceSet_by_name($ss_assembly);
        my $full_cs_list = $ds->fetch_all_CloneSequences_for_SequenceSet($full_ss);
        my $first        = $results_list->[0];
        my $last         = $results_list->[$#{$results_list}];
        $full_ss_size    = scalar(@$full_cs_list) ;
        $full_ss_size--; # make it the last array index

        # search for the indices of the matches in the full seq set.
        my $sync_idx = 0;
        for my $i(0..$full_ss_size){
            my $cs = $full_cs_list->[$i];
            # needs to be 2 if statements in case there's only one match
            # only check the accession is this wise? I think it'll be enough
            if($cs->accession eq $first->accession){
                $first_idx = $i;
            }
            if($cs->accession eq $last->accession){
                $last_idx = $i;
            }
            last if $last_idx; # not need to keep on searching

            if($first_idx){
                $sync_idx = $i - $first_idx;
                my $sync = $results_list->[$sync_idx];
                warn "\ti = $i first_idx = $first_idx, sync_idx = $sync_idx "
                    . "current acc = '".$cs->accession."' current sync acc = '"
                    . $sync->accession."'\n" if $DEBUG;
                if($sync && $sync->accession ne $cs->accession){
                    warn "\tI've found a gap " . $sync->accession . " - " . $cs->accession
                        . " - need to insert " . $cs->accession . " into \@results_list"
                        . "\n" if $DEBUG;
                    my $size = scalar(@$results_list);
                    splice(@$results_list, $sync_idx, $size - $sync_idx, $cs, @{$results_list}[$sync_idx..($size - 1)]);
                }
            }
        }
        # RP11-134H2, PRKG1
        warn "first = $first_idx, last = $last_idx, lower = 0, upper = $full_ss_size\n" if $DEBUG;

        if($context_size){
            # make this faster easier to read
            my $prefix_start = ($first_idx - $context_size < 0 ? 0 : $first_idx - $context_size);
            my $postfix_end  = ($last_idx + $context_size > $full_ss_size ? $full_ss_size : $last_idx + $context_size);

            @prefix_slice  = @{$full_cs_list}[$prefix_start..--$first_idx];
            @postfix_slice = @{$full_cs_list}[++$last_idx..$postfix_end];
        }


        # add the context before
        push (@cs_assembly_list, @prefix_slice) if @prefix_slice;

        # add the matches
         push (@cs_assembly_list, @$results_list);

        # add the context after
        push (@cs_assembly_list, @postfix_slice) if @postfix_slice;
        $ss->drop_CloneSequence_list();
        $ss->CloneSequence_list(\@cs_assembly_list);
    }
}

sub context_size{
    my ($self, $context) = @_;
    $self->{'_context'} = $context if $context;
    return $self->{'_context'} || 0;
}

sub matching_assembly_types{
    my ($self) = @_;
    my @types  = map { $_->name } @{$self->get_all_SequenceSets};
    return \@types;
}

#this creates a SequenceSet object, but does NOT cache the results (the method in DataSet does cache results))
sub uncached_SequenceSet_by_name{
    my ($self, $ass_name ) = @_ ;

    my $DataSet =  $self->DataSet or confess "no DataSet object";

    my $cached = $DataSet->get_SequenceSet_by_name($ass_name)
        or return;

    my $set = Bio::Otter::Lace::SequenceSet->new;
    foreach my $method (
        qw{ name dataset_name description priority write_access }
        )
    {
        $set->$method($cached->$method());
    }

    return $set ;
}


sub DESTROY{
    warn "Destroying ResultSet" ;
}

1 ;

