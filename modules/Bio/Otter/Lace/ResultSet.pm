### Bio::Otter::Lace:ResultSet
## this object is used to store the results of a search for a particular clone.
## sequence sets are now stored in an array so they should come out in order,
## but there is no check that a sequence set already exists

package Bio::Otter::Lace::ResultSet;
use Data::Dumper ;
use strict;
use Carp;

sub new {
    my $pkg = shift;
    
    return bless {}, $pkg;
}


sub add_SequenceSet{
    my ($self, $ss) = @_ ;
    
    unshift @{$self->{'sequence_set'} }  , $ss ;  
}

sub get_SequenceSet_by_name{
    my ($self , $name ) = @_ ;
    
    foreach my $ss ( @{$self->{'sequence_set'}} ){

        if ($ss->name eq $name) {
            return $ss;
        }
    }
}

sub get_all_SequenceSets{
    my ($self) = @_ ;
    
    my $list  = $self->{'sequence_set'} ;
    
    return $list
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
    }else{
        $self->fetch_Clones_containing_CloneNames($search_list) ;
    }
}

sub fetch_Clones_containing_locus{
    my ($self, $locus_names) = @_ ;
    
    confess "Missing locus name argument " unless ($locus_names);
    
    my $locus_names_string = join(',', map "'$_'", @$locus_names);

    my $dba = $self->DataSet->get_cached_DBAdaptor ;    
    my %id_chr = map {$_->chromosome_id, $_} $self->DataSet->get_all_Chromosomes;
    
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
    warn "looking for clone names $clone_names_string";
 
    
    my $dba= $self->DataSet->get_cached_DBAdaptor ;
    my %id_chr = map {$_->chromosome_id, $_} $self->DataSet->get_all_Chromosomes;
    my %cs_hash ;

    my $results = 0;
    my $sth = $dba->prepare (qq{
        SELECT DISTINCT cl.name, cl.embl_acc, cl.embl_version 
            , c.contig_id, c.name, c.length	
            , a.chromosome_id, a.chr_start, a.chr_end
            , a.contig_start, a.contig_end, a.contig_ori
            , a.type
            , lk.clone_lock_id
        FROM   contig c ,  assembly a , clone cl
        LEFT JOIN clone_lock lk ON lk.clone_id = cl.clone_id
        WHERE cl.clone_id = c.clone_id
        AND a.contig_id = c.contig_id
        AND (cl.name IN ($clone_names_string)
            OR cl.embl_acc IN ($clone_names_string))
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
        $self->DataSet->status_refresh_for_SequenceSet($ss);
        $self->add_SequenceSet($ss); 
    }
    ## sets the things in ResultSet, but the return value is the number of clones returned
    return $results ;
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

