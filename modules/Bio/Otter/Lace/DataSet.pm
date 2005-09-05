
### Bio::Otter::Lace::DataSet

package Bio::Otter::Lace::DataSet;

use strict;
use Carp;
use Bio::Otter::DBSQL::DBAdaptor;
use Bio::Otter::Lace::CloneSequence;
use Bio::Otter::CloneLock;
use Bio::Otter::Author;
use Bio::Otter::Lace::Chromosome;
use Bio::Otter::Lace::SequenceSet;
use Bio::Otter::Lace::ResultSet;
use Bio::Otter::Lace::SequenceNote;
use Bio::Otter::Lace::PipelineDB;
use Bio::Otter::Lace::SatelliteDB;
use Bio::Otter::Lace::Defaults;
use Bio::Otter::Lace::PipelineStatus;

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub author {
    my( $self, $author ) = @_;
    
    if ($author) {
        $self->{'_author'} = $author;
        $self->{'_author_id'} = undef;
    }
    return $self->{'_author'};
}
sub taxon{
    my ($self) = @_;
    unless($self->{'_taxon_id'}){
	my $dba      = $self->get_cached_DBAdaptor;
	my $meta_con = $dba->get_MetaContainer;
	$self->{'_taxon_id'} = $meta_con->get_taxonomy_id();
    }
    return $self->{'_taxon_id'};
}
sub species{
    my ($self) = @_;
    unless($self->{'_species'}){
	my $dba      = $self->get_cached_DBAdaptor;
	my $meta_con = $dba->get_MetaContainer;
#	$self->{'_species'} = $meta_con->get_Species(); # this requires 'species.classification' meta key
	my $t_species= $meta_con->list_value_by_key('species.common_name');
	if ($t_species && scalar(@{$t_species})){
	    $self->{'_species'} = $t_species->[0];
	}else{
	    warn "species unavailable, check <species.common_name> meta key\n";
	}
    }
    return $self->{'_species'};
}
sub _author_id {
    my( $self ) = @_;
    
    my( $id );
    unless ($id = $self->{'_author_id'}) {
        my $author = $self->author or confess "author not set";
        my $dba = $self->get_cached_DBAdaptor;
        my $sth = $dba->prepare(q{
            SELECT author_id
            FROM author
            WHERE author_name = ?
            });
        $sth->execute($author);
        ($id) = $sth->fetchrow;
        confess "No author_id for '$author'" unless $id;
        $self->{'_author_id'} = $id;
    }
    return $id;
}

sub save_author_if_new{
    my ($self , $client) = @_;
    
    my( $id );   
    eval{ $id =  $self->_author_id } ;
    return if  $id ; 
    my $username =  $self->author;
    my $email = $client->email ;
    my $dba = $self->get_cached_DBAdaptor;
    my $add_author = $dba->prepare(q{
        INSERT author ( author_email,
                        author_name)
        VALUES ( ?, ?)          
    });    
    $add_author->execute($email , $username);
    $id = $add_author->{'mysql_insertid'}
        or confess "Failed to get insertid";
    $self->_author_id($id);
}

sub sequence_set_access_list {
    my( $self ) = @_;
    
    my( $al );
    unless ($al = $self->{'_sequence_set_access_list'}) {
        $al = $self->{'_sequence_set_access_list'} = {};
        
        my $dba = $self->get_cached_DBAdaptor;
        my $sth = $dba->prepare(q{
            SELECT ssa.assembly_type
              , ssa.access_type
              , au.author_name
            FROM sequence_set_access ssa
              , author au
            WHERE ssa.author_id = au.author_id
            });
        $sth->execute;
        
        while (my ($set_name, $access, $author) = $sth->fetchrow) {
            $al->{$author}{$set_name} = $access eq 'RW' ? 1 : 0;
        }
    }
    
    return $al;
}

sub get_all_visible_SequenceSets {
    my( $self ) = @_;
    
    my $ss_list = $self->get_all_SequenceSets;
    my $visible = [];
    foreach my $ss (@$ss_list) {
        push(@$visible, $ss) unless $ss->is_hidden;
    }
    return $visible;
}

sub get_all_SequenceSets {
    my( $self, $ss_array ) = @_;

    # If using xml transfer for sequence set remove old bit below
    # note need to call $client->get_SequenceSets_for_DataSet($datasetObj) FIRST
    # that's the rub when this object hasn't got a client or isn't using 
    # a direct db connection. See SequenceSetChooser version 1.28 line 130
    if($ss_array 
       && ref($ss_array)
       && ref($ss_array) eq 'ARRAY'){
        $self->{'_sequence_sets'} = $ss_array;
    }
    # this is the old bit of this method.
    # doesn't need $client->get_SequenceSets_for_DataSet($datasetObj)
    # to be called first
    my( $ss );
    unless ($ss = $self->{'_sequence_sets'}) {
        $ss = $self->{'_sequence_sets'} = [];
        my @a = caller(0);
        return [] if $a[0] eq 'Bio::Otter::Lace::Client';

        warn "Client->get_SequenceSets_for_DataSet(DataSetObject) should replace this\n";

        my $this_author = $self->author or confess "author not set";
        my $ssal = $self->sequence_set_access_list;
        
    
        my $dba = $self->get_cached_DBAdaptor;
        my $sth = $dba->prepare(q{
            SELECT assembly_type
              , description
	      , analysis_priority
              , hide
              , vega_set_id
            FROM sequence_set
            ORDER BY assembly_type
            });
        $sth->execute;
        
        my $ds_name = $self->name;
        while (my ($name, $desc, $priority, $hide, $vega_id) = $sth->fetchrow) {
            my( $write_flag );
            if (%$ssal && $ssal->{$this_author}) {
                $write_flag = $ssal->{$this_author}{$name};
                # If an author doesn't have an entry in the sequence_set_access
                # table for this set, then it is invisible to them.
                next unless defined $write_flag;
            } else {
                # No entries for person in sequence_set_access table - person
                # can write and see everything.
                $write_flag = 1;
            }
        
            my $set = Bio::Otter::Lace::SequenceSet->new;
            $set->name($name);
            $set->dataset_name($ds_name);
            $set->description($desc);
	    $set->priority($priority);
            $set->is_hidden($hide eq 'Y');
            $set->vega_set_id($vega_id);
            $set->write_access($write_flag);
            
            push(@$ss, $set);
        }
    }
    return $ss;
}

sub get_SequenceSet_by_name {
    my( $self, $name ) = @_;
    
    confess "missing name argument" unless $name;
    my $ss_list = $self->get_all_SequenceSets;
    foreach my $ss (@$ss_list) {
        if ($name eq $ss->name) {
            return $ss;
        }
    }
    confess "No SequenceSet called '$name'";
}
sub selected_SequenceSet {
    my( $self, $selected_SequenceSet ) = @_;
    
    if ($selected_SequenceSet) {
        $self->{'_selected_SequenceSet'} = $selected_SequenceSet;
    }
    return $self->{'_selected_SequenceSet'};
}

sub unselect_SequenceSet {
    my( $self ) = @_;
    
    $self->{'_selected_SequenceSet'} = undef;
}

sub fetch_all_CloneSequences_for_selected_SequenceSet {
    my( $self ) = @_;
    
    my $ss = $self->selected_SequenceSet
        or confess "No SequenceSet is selected";
    return $self->fetch_all_CloneSequences_for_SequenceSet($ss);
}

#   this forces a refresh of the $self->status query
#   but doesn't re fetch all CloneSequences of the SequenceSet
sub status_refresh_for_SequenceSet{
    my ($self, $ss) = @_;

    return unless Bio::Otter::Lace::Defaults::fetch_pipeline_switch();

    my $dba = $self->get_cached_DBAdaptor;
    my $pipe_dba = Bio::Otter::Lace::PipelineDB::get_pipeline_DBAdaptor($dba);
    $self->fetch_pipeline_ctg_ids_for_SequenceSet($ss);

    my( %id_cs );
    foreach my $cs (@{$ss->CloneSequence_list}) {
        $cs->drop_pipelineStatus;
        $id_cs{$cs->pipeline_contig_id} = $cs;
    }

    my $rule_list = []; # all the analysis which can run for this species.
    if (1) {
        my $ruleAdapt      = $pipe_dba->get_RuleAdaptor();
        my %rules = map {$_->goalAnalysis->logic_name, $_} $ruleAdapt->fetch_all;

        ### Would be nice to see rules in correct order.
        #@rules = sort_rules_by_dependency(@rules);

        # Only show analyses that descend from 'SubmitContig'
        while (my ($name, $rule) = each %rules) {
            my $will_be_run = 0;
            foreach my $cond_name (@{$rule->list_conditions}) {
                # The "SubmitContig" rule does not show up by itself
                if ($cond_name eq 'SubmitContig' or $rules{$cond_name}) {
                    $will_be_run = 1;
                }
            }
            if ($will_be_run) {
                push(@$rule_list, $name);
            }
        }
    }

    # Used to depend on the list of filters in the config file
    #my $species = $self->species();
    #my $filters = Bio::Otter::Lace::Defaults::option_from_array([$species, 'use_filters']);
    #foreach my $s (keys %$filters){
    #    # filter name can be present and have value 0.
    #    next unless $filters->{$s};
    #    push(@$rule_list, $s);
    #}

    Bio::Otter::Lace::PipelineStatus->set_rule_list([sort @$rule_list]);

    my $sql = q{
        SELECT c.contig_id
          , y.logic_name
          , i.created
          , i.db_version
        FROM analysis y
          , input_id_analysis i
          , contig c
        WHERE c.name = i.input_id
          AND y.analysis_id = i.analysis_id
          AND i.input_id = c.name
          AND c.contig_id IN (} . join(', ', keys %id_cs) . q{)};
    #warn "pipeline status query = '$sql'";
    my $sth = $pipe_dba->prepare($sql);
    $sth->execute();
    
    my( $ctg_id, $ana_name, $created, $version );
    $sth->bind_columns(\$ctg_id, \$ana_name, \$created, \$version);
    
    my( %id_status );
    while ($sth->fetch) {
        next if $ana_name eq 'SubmitContig';
        my $status = $id_status{$ctg_id};
        unless ($status) {
            # Make a new PipelineStatus object, and attach it to its CloneSequence
            $status = $id_status{$ctg_id} = Bio::Otter::Lace::PipelineStatus->new;
            my $cs = $id_cs{$ctg_id};
            $cs->pipelineStatus($status);
        }
        $status->add_completed_analysis($ana_name, $created, $version);
    }

    Bio::Otter::Lace::SatelliteDB::disconnect_DBAdaptor($pipe_dba);
}

# used when the locks column on sequence notes needs to be refereshed , rather than query for every detail
sub lock_refresh_for_SequenceSet{
    my ($self , $ss) = @_ ;
 
    my $dba = $self->get_cached_DBAdaptor;
   
    my $type = $ss->name  ;
    my @id_list ;
    foreach my $clone ( @{$ss->CloneSequence_list}){
        push (@id_list , $clone->contig_id);
    }
     
    my $id_string =  join( ", " , map { qq`'$_'`} @id_list );        

    my $sql = qq{
        SELECT DISTINCT cl.clone_lock_id , g.contig_id, t.author_id
            , t.author_name, t.author_email, cl.hostname
        FROM assembly a
          , contig g
          , clone c
        LEFT JOIN clone_lock cl ON cl.clone_id = c.clone_id
        LEFT JOIN author t ON t.author_id = cl.author_id
        WHERE a.contig_id = g.contig_id
          AND g.clone_id = c.clone_id
--          AND a.type = "$type"
          AND cl.clone_lock_id IS NOT NULL
          AND g.contig_id in ($id_string)          
        };
        #warn $sql;
        my $sth = $dba->prepare($sql);
             
    $sth->execute;
    my ($clone_lock_id , $contig_id, $author_id,
        $author_name, $author_email, $hostname);
    $sth->bind_columns( \$clone_lock_id , \$contig_id, \$author_id,
                        \$author_name, \$author_email, \$hostname );
    my %lock_hash ;
    while($sth->fetch) {
        #if(defined($clone_lock_id)){
            my $authorObj = Bio::Otter::Author->new(-dbid  => $author_id,
                                                    -name  => $author_name,
                                                    -email => $author_email);            
            $lock_hash{$contig_id} = Bio::Otter::CloneLock->new(-author   => $authorObj,
                                                                -hostname => $hostname,
                                                                -dbID     => $clone_lock_id);
        #}
    }
    
    foreach my  $clone (@{$ss->CloneSequence_list}){
        if (my $cloneLock = $lock_hash{$clone->contig_id} ){
            $clone->set_lock_status($cloneLock);
        }else{
            $clone->set_lock_status(0);
        }
    }
}



sub fetch_all_CloneSequences_for_SequenceSet {
    my( $self, $ss ) = @_;
    
    confess "Missing SequenceSet argument" unless $ss;
    #confess "CloneSequences already fetched" if $ss->CloneSequence_list;
    
    my %id_chr = map {$_->chromosome_id, $_} $self->get_all_Chromosomes;
    my $cs = [];
    
    my $dba = $self->get_cached_DBAdaptor;
    my $type = $ss->name;

    my $sth = $dba->prepare(qq{
        SELECT c.name, c.embl_acc, c.embl_version
          , g.contig_id, g.name, g.length
          , a.chromosome_id, a.chr_start, a.chr_end
          , a.contig_start, a.contig_end, a.contig_ori
          , cl.clone_lock_id, t.author_id, t.author_name
          , t.author_email, cl.hostname, a.superctg_name
        FROM assembly a
          , contig g
          , clone c
        LEFT JOIN clone_lock cl ON cl.clone_id = c.clone_id
        LEFT JOIN author t ON t.author_id = cl.author_id
        WHERE a.contig_id = g.contig_id
          AND g.clone_id = c.clone_id
          AND a.type = ?
        ORDER BY a.chromosome_id
          , a.chr_start
        });
    $sth->execute($type);
    my(  $name, $acc,  $sv,
         $ctg_id,  $ctg_name,  $ctg_length,
         $chr_id,  $chr_start,  $chr_end,
         $contig_start,  $contig_end,  $strand,
         $clone_lock_id, $author_id, $author_name, 
         $author_email, $hostname, $superctg_name );
    $sth->bind_columns(
        \$name, \$acc, \$sv,
        \$ctg_id, \$ctg_name, \$ctg_length,
        \$chr_id, \$chr_start, \$chr_end,
        \$contig_start, \$contig_end, \$strand,
        \$clone_lock_id, \$author_id, 
        \$author_name, \$author_email, \$hostname,
        \$superctg_name
        );
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
        $cl->super_contig_name($superctg_name);
        if (defined $clone_lock_id){
            my $authorObj = Bio::Otter::Author->new(-dbid  => $author_id,
                                                    -name  => $author_name,
                                                    -email => $author_email);
            my $cloneLock = Bio::Otter::CloneLock->new(-author   => $authorObj,
                                                       -hostname => $hostname,
                                                       -dbID     => $clone_lock_id);
            $cl->set_lock_status($cloneLock);
        }
        push(@$cs, $cl);
    }

    $ss->CloneSequence_list($cs);
}

sub fetch_pipeline_ctg_ids_for_SequenceSet{
    my ($self, $ss) = @_;
    
    return unless Bio::Otter::Lace::Defaults::fetch_pipeline_switch();
    return if $ss->have_fetched_pipeline_contig_ids;
    
    my $dba            = $self->get_cached_DBAdaptor;
    my $cloneSeqList   = $ss->CloneSequence_list();
    my $pipeline_db    = Bio::Otter::Lace::PipelineDB::get_pipeline_DBAdaptor($dba);
    my $dbh            = $pipeline_db->db_handle();

    my( %ctgname_cs );
    foreach my $cs (@$cloneSeqList) {
        next if $cs->pipeline_contig_id;
        $ctgname_cs{$cs->contig_name} = $cs;
    }
    my $ctg_name_list = join(',', map $dbh->quote($_), keys %ctgname_cs);
    my $sql = qq{SELECT c.name, c.contig_id FROM contig c WHERE c.name IN ($ctg_name_list)};
    # warn $sql;
    my $sth = $pipeline_db->prepare($sql);
    $sth->execute();
    my( $name, $ctg_id );
    $sth->bind_columns(\$name, \$ctg_id);
    while($sth->fetch){
        $ctgname_cs{$name}->pipeline_contig_id($ctg_id);
    }
    
    # Flag that we have fetched all the pipeline contig_ids that we can
    $ss->have_fetched_pipeline_contig_ids(1);
    Bio::Otter::Lace::SatelliteDB::disconnect_DBAdaptor($pipeline_db);

}

sub fetch_all_SequenceNotes_for_SequenceSet {
    my( $self, $ss ) = @_;
    
    my $name = $ss->name or confess "No name in SequenceSet object";
    my $cs_list = $ss->CloneSequence_list;

    my $dba = $self->get_cached_DBAdaptor;
    my $sth = $dba->prepare(qq{
        SELECT n.contig_id
          , n.note
          , UNIX_TIMESTAMP(n.note_time)
          , n.is_current
          , au.author_name
        FROM assembly ass
          , sequence_note n
          , author au
        WHERE ass.contig_id = n.contig_id
          AND n.author_id = au.author_id
          AND ass.type = ?
        });
    $sth->execute($name);
    
    my( $ctg_id, $text, $time, $is_current, $author);
    $sth->bind_columns(\$ctg_id, \$text, \$time, \$is_current, \$author);
    
    my( %ctg_notes );
    while ($sth->fetch) {
        my $note = Bio::Otter::Lace::SequenceNote->new;
        $note->text($text);
        $note->timestamp($time);
        $note->is_current($is_current eq 'Y' ? 1 : 0);
        $note->author($author);
        
        my $note_list = $ctg_notes{$ctg_id} ||= [];
        push(@$note_list, $note);
    }
    
    foreach my $cs (@$cs_list) {
	# added so that the complete fresh set is ALL 
	# that is in the cloneSequence's SequenceNotes [].
	$cs->truncate_SequenceNotes(); 
        if (my $notes = $ctg_notes{$cs->contig_id}) {
            foreach my $sn (sort {$a->timestamp <=> $b->timestamp} @$notes) {
		# logic in current_SequenceNote doesn't work
		# unless this is done first
		$cs->add_SequenceNote($sn); 
                if ($sn->is_current) {
                    $cs->current_SequenceNote($sn);
                }
            }
        }
    }
    return %ctg_notes;
}

sub save_current_SequenceNote_for_CloneSequence {
    my( $self, $cs ) = @_;
    
    confess "Missing CloneSequence argument" unless $cs;
    my $dba = $self->get_cached_DBAdaptor;
    my $author_id = $self->_author_id ;
    warn "author name and id " . $self->author . "  ". $author_id ;
    my $contig_id = $cs->contig_id
        or confess "contig_id not set";
    my $current_note = $cs->current_SequenceNote
        or confess "current_SequenceNote not set";
    unless($current_note->author){
        $current_note->author($self->author);
    }
    
    
    my $text = $current_note->text
        or confess "no text set for note";
    my $time = $current_note->timestamp;
    unless ($time) {
        $time = time;
        $current_note->timestamp($time);
    }
    
    my $not_current = $dba->prepare(q{
        UPDATE sequence_note
        SET is_current = 'N'
        WHERE contig_id = ?
        });
    
    my $insert = $dba->prepare(q{
        INSERT sequence_note(contig_id
              , author_id
              , is_current
              , note_time
              , note)
        VALUES (?,?,'Y',FROM_UNIXTIME(?),?)
        });
    
    $not_current->execute($contig_id);
    $insert->execute(
        $contig_id,
        $author_id,
        $time,
        $text,
        );
    
    # sync state of SequenceNote objects with database
    foreach my $note (@{$cs->get_all_SequenceNotes}) {
        $note->is_current(0);
    }
    $current_note->is_current(1);
}


# takes an existing sequence_note object and update the comment
sub update_current_SequenceNote{
    
    my ($self , $clone_sequence, $new_text) = @_ ;
    
    my $current_sequence_note = $clone_sequence->current_SequenceNote;
    
    my $dba = $self->get_cached_DBAdaptor;
    
    my $contig_id = $clone_sequence->contig_id 
        or confess 'contig_id not set';
    my $timestamp = $current_sequence_note->timestamp  
        or confess 'timestamp not set';
    my $author = $current_sequence_note->author 
        or confess 'author not set';  
    
    # sequence_note stores the username, we needto get the db id      
#    my $author_query = $dba->prepare(q{
#            SELECT author_id
#            FROM author
#            WHERE author_name = ?
#            });            
#    $author_query->execute($author);
#    my $author_id = $author_query->fetchrow; 
    
    my $author_id = $self->_author_id ;
        
    my $update = $dba->prepare(q{
        UPDATE  sequence_note
        SET     note    = ?
        WHERE   contig_id = ?
        AND     author_id = ?
        AND     note_time = FROM_UNIXTIME(?)  
        });
     
     my $rows = $update->execute($new_text , $contig_id , $author_id, $timestamp);
}

sub get_all_Chromosomes {
    my( $self ) = @_;
    
    my( $ch );
    unless ($ch = $self->{'_chromosomes'}) {
        $ch = $self->{'_chromosomes'} = [];
        
        my $dba = $self->get_cached_DBAdaptor;
        
        # Only want to show the user chomosomes
        # that we have in the assembly table.
        my $sth = $dba->prepare(q{
            SELECT distinct(chromosome_id)
            FROM assembly
            });
        $sth->execute;
        
        my( %have_chr );
        while (my ($chr_id) = $sth->fetchrow) {
            $have_chr{$chr_id} = 1;
        }
        
        $sth = $dba->prepare(q{
            SELECT chromosome_id
              , name
              , length
            FROM chromosome
            });
        $sth->execute;
        my( $chr_id, $name, $length );
        $sth->bind_columns(\$chr_id, \$name, \$length);
        
        while ($sth->fetch) {
            # Skip chromosomes not in assembly table
            next unless $have_chr{$chr_id};
            my $chr = Bio::Otter::Lace::Chromosome->new;
            $chr->chromosome_id($chr_id);
            $chr->name($name);
            $chr->length($length);
            
            push(@$ch, $chr);
        }
        
        # Sort chromosomes numerically then alphabetically
        @$ch = sort {
              my $a_name = $a->name;
              my $b_name = $b->name;
              my $a_name_is_num = $a_name =~ /^\d+$/;
              my $b_name_is_num = $b_name =~ /^\d+$/;

              if ($a_name_is_num and $b_name_is_num) {
                  $a_name <=> $b_name;
              }
              elsif ($a_name_is_num) {
                  -1
              }
              elsif ($b_name_is_num) {
                  1;
              }
              else {
                  $a_name cmp $b_name;
              }
            } @$ch;
    }
    return @$ch;
}

sub _tmp_table_by_name{
    my ($self, $id) = @_;
    $self->{'temp_table_name_cache'}->{$id} ||= "storing_${id}_$$";
    return $self->{'temp_table_name_cache'}->{$id};
}

sub tmpstore_meta_info_for_SequenceSet{
    my ($self, $ss, $adaptors) = @_;
    # check I'm a nice sequence set in $ss
    confess("$ss says I'm not a sequence set") unless $ss->isa("Bio::Otter::Lace::SequenceSet");
    # write some sql
    my $tmp_tbl_meta   = $self->_tmp_table_by_name("meta_info");
    my $create_tmp_tbl = qq{CREATE TEMPORARY TABLE $tmp_tbl_meta SELECT * FROM sequence_set WHERE 1 = 0};
    my $insert_ss      = qq{INSERT INTO $tmp_tbl_meta (assembly_type, description, analysis_priority) VALUES(?, ?, ?)};
    my $max_chr_end_q  = qq{SELECT IFNULL(MAX(a.chr_end), 0) AS max_chr_end 
				   FROM $tmp_tbl_meta ss, assembly a 
				   WHERE ss.assembly_type = a.type 
				   && ss.assembly_type = ?};
    # some sequence set info
    my $new_desc       = $ss->description();
    my $new_name       = $ss->name();
    my $new_priority   = $ss->priority() || 5;
    my $max_chr_end    = 0;

    # create/fill/read temporary table
    foreach my $adaptor(@$adaptors){
	my $sth = $adaptor->prepare($create_tmp_tbl);
	$sth->execute();
	$sth->finish();

	$sth = $adaptor->prepare($insert_ss);
	$sth->execute($new_name, $new_desc, $new_priority);
	$sth->finish();

	$sth = $adaptor->prepare($max_chr_end_q);
	$sth->execute($new_name);
	my ($tmp) = $sth->fetchrow();
	$sth->finish();

	$max_chr_end = ($tmp > $max_chr_end ? $tmp : $max_chr_end);
    }

    return $max_chr_end;
}

sub store_SequenceSet{
    my ($self, $ss, $seqfetch_code, $allow_update) = @_;
    
    # check I'm a nice sequence set in $ss
    confess("$ss says I'm not a sequence set") unless $ss->isa("Bio::Otter::Lace::SequenceSet");
    
    # get the previous sequence_set with the same name.
    eval { $self->get_SequenceSet_by_name($ss->name) };
    if(!$@){ confess "Adding to a previos AGP with another is not allowed" unless $allow_update };
    # write some sql
    my $tmp_tbl_assembly = $self->_tmp_table_by_name("assembly");
    my $create_tmp_tbl   = qq{CREATE TEMPORARY TABLE $tmp_tbl_assembly SELECT * FROM assembly WHERE 1 = 0};
    my $insert_query     = qq{INSERT INTO $tmp_tbl_assembly (chromosome_id, chr_start,
							     chr_end, superctg_name,
							     superctg_start, superctg_end,
							     superctg_ori,contig_id,
							     contig_start, contig_end,
							     contig_ori,type )
				  VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
			      };
    # database connections
    my $otter_db    = $self->get_cached_DBAdaptor;
    my $pipeline_db = Bio::Otter::Lace::PipelineDB::get_pipeline_rw_DBAdaptor($otter_db)
        or confess "Can't connect to pipeline db";
    my $ens_db      = $self->make_EnsEMBL_DBAdaptor()
        or confess "Can't connect to 'self' db";

    my $max_chr_length = $self->tmpstore_meta_info_for_SequenceSet($ss, [$ens_db, $pipeline_db]);

    # execute query to create temp
    my $ens_sth = $ens_db->prepare($create_tmp_tbl);
    $ens_sth->execute();
    $ens_sth->finish();
    my $pipeline_sth = $pipeline_db->prepare($create_tmp_tbl);
    $pipeline_sth->execute();
    $pipeline_sth->finish();

    require Bio::EnsEMBL::Clone;
    require Bio::EnsEMBL::RawContig;

    # get clone_adaptors
    my $ens_clone_adaptor  = $ens_db->get_CloneAdaptor;
    my $pipe_clone_adaptor = $pipeline_db->get_CloneAdaptor;
    my $adaptors           = [$ens_clone_adaptor, $pipe_clone_adaptor];
    my @contigs            = (); # stores contig ids per adaptor/db
    my $all_contigs        = [];
    # prepare the assembly insert query for each db
    $ens_sth      = $ens_db->prepare($insert_query);
    $pipeline_sth = $pipeline_db->prepare($insert_query);

    # go through the clones in the list storing them in the 
    # clone/contig/dna tables
    # temp assembly table
    foreach my $cloneSeq(@{$ss->CloneSequence_list}){
	my $acc    = $cloneSeq->accession();
	my $sv     = $cloneSeq->sv();

	my @clones = @{$self->_fetch_clones($adaptors, $acc, $sv, $seqfetch_code)};
	for (my $i = 0; $i < @clones; $i++){
	    my $clone  = $clones[$i];
	    if(defined $clone->dbID){
		my $contig = $clone->get_all_Contigs->[0];
		$contigs[$i] = $contig;
	    }else{
		# store the clone
		my ($contig) = $self->_store_clone($adaptors->[$i], $clone);
		$contigs[$i] = $contig;
	    }
	    push(@{$all_contigs->[$i]}, $contigs[$i]);
	}

	# store the assembly
	$ens_sth->execute($cloneSeq->chromosome, $cloneSeq->chr_start,
			  $cloneSeq->chr_end, $cloneSeq->super_contig_name,
			  $cloneSeq->chr_start, $cloneSeq->chr_end,
			  1, # super_contig_orientation
			  $contigs[0]->dbID, $cloneSeq->contig_start,
			  $cloneSeq->contig_end, $cloneSeq->contig_strand,
			  $ss->name
			  );
	$pipeline_sth->execute($cloneSeq->pipeline_chromosome, $cloneSeq->chr_start,
			       $cloneSeq->chr_end, $cloneSeq->super_contig_name,
			       $cloneSeq->chr_start, $cloneSeq->chr_end,
			       1, # super_contig_orientation
			       $contigs[1]->dbID, $cloneSeq->contig_start,
			       $cloneSeq->contig_end, $cloneSeq->contig_strand,
			       $ss->name
			       );
    }
    ####################################################
#    $self->__dump_table("assembly", [$pipeline_db, $ens_db]);
#    $self->__dump_table("meta_info", [$pipeline_db, $ens_db]);
    # if everythings ok "commit" sequence_set table and assembly table
    # insert into sequence_set select from temporary table
    my $tmp_tbl_mi    = $self->_tmp_table_by_name("meta_info");
    my $copy_assembly = qq{INSERT IGNORE INTO assembly SELECT * FROM $tmp_tbl_assembly};
    my $copy_seq_set  = qq{INSERT IGNORE INTO sequence_set SELECT * FROM $tmp_tbl_mi};
    foreach my $dbA($ens_db, $pipeline_db){
	my $sth = $dbA->prepare($copy_assembly);
	$sth->execute();
	$sth = $dbA->prepare($copy_seq_set);
	$sth->execute();
    }
    return $all_contigs->[1]; # return the pipeline contigs
}


sub __dump_table{
    my ($self, $name, $adaptors, $other) = @_;
    my $tmp = ($other ? $other : $self->_tmp_table_by_name($name));
    return unless defined $tmp;
    my $query = "SELECT * FROM $tmp";
    foreach my $adaptor(@$adaptors){
	my $sth = $adaptor->prepare($query);
	$sth->execute();
	print STDERR "TABLE: $tmp\n";
	while(my $row = $sth->fetchrow_arrayref){
	    print STDERR join("\t", @$row) . "\n";
	}
    }
}

sub _fetch_clones{
    my ($self, $clone_adaptors, $acc, $sv, $seqfetcher) = @_;
    my $clones = [];
    my $seq;
    foreach my $clone_adaptor(@$clone_adaptors){
	my $clone;
	eval { $clone = $clone_adaptor->fetch_by_accession_version($acc, $sv) };
	if($clone){
	    warn "clone <".$clone->embl_id."> is already in the " . $clone_adaptor->db->dbname . " database\n" ;
	    my $contigs = $clone->get_all_Contigs;
            my $count = @$contigs;
            unless ($count == 1) {
                die "Clone '$acc' has $count contigs";
            }
	}else{
	    my $acc_sv = "$acc.$sv";
	    $seq ||= &$seqfetcher($acc_sv);
	    $clone = $self->_make_clone($seq, $acc, $sv);
	}
	push(@$clones, $clone);
    }
    return $clones;
}
sub _make_clone{
    my ($self, $seq, $acc, $sv) = @_;
    my $acc_sv = "$acc.$sv";
    my $clone = Bio::EnsEMBL::Clone->new();
    $clone->id("$acc_sv");    ### Should set to international clone name
    $clone->embl_id($acc);
    $clone->embl_version($sv);
    $clone->htg_phase(3);   ### Not all are "Finished" (phase 3)
    $clone->version(1);
    $clone->created(time);
    $clone->modified(time);
    
    # fetch sequences
    my $contig = Bio::EnsEMBL::RawContig->new;
    my $end = $seq->length;
    $contig->name("$acc_sv.1." . $seq->length);
    $contig->length($seq->length);
    $contig->embl_offset(1);
    $contig->seq($seq->seq);
    $clone->add_Contig($contig);
    return $clone;
}
sub _store_clone{
    my ($self, $clone_adaptor, $clone) = @_ ;

    eval{ $clone_adaptor->store($clone);  };
    if($@){
	print STDERR "Problems writing " . $clone->id . " to database. \nProblem was " . $@;             
    }
    return $clone->get_all_Contigs->[0];
}

sub update_SequenceSet{
    my ($self, $ss) = @_;
    # get the previous sequence_set with the same name.
    # eval { $self->get_SequenceSet_by_name($ss->name) };
    # if(!$@){ confess "not allowed" unless $allow_update };
    # database connections
    my $otter_db    = $self->get_cached_DBAdaptor;
    my $pipeline_db = Bio::Otter::Lace::PipelineDB::get_pipeline_rw_DBAdaptor($otter_db);
    # update sql
    my $update_meta_info = qq{UPDATE sequence_set SET description = ?, analysis_priority = ? WHERE assembly_type = ?};
    my $name = $ss->name();
    my $desc = $ss->description();
    my $pri  = $ss->priority();
    foreach my $adaptor($otter_db, $pipeline_db){
	my $sth = $adaptor->prepare($update_meta_info);
	$sth->execute($desc, $pri, $name);
    }
}

sub refresh_locks{
    my ($self , $ss ) = @_ ;
    
    my $cs_list = $ss->CloneSequence_list ;
    my @contig_ids ; # or could use embl acc / version combo - but this seems simpler
    
    # put all the clones in a hash with the contig_id as the key, also put contig id's in an array for the query
    my %cs_hash ;
    foreach my $cs (@$cs_list){
        $cs_hash{$cs->contig_id} = $cs ;
        push @contig_ids , $cs->contig_id ;
    }
    my $comma_list = join ',' , @contig_ids  ;
    
    my $dba = $self->get_cached_DBAdaptor ;
    my $sth = $dba->prepare(qq{
        SELECT  cg.contig_id
        FROM    clone_lock cl
            ,   contig cg 
        WHERE   cl.clone_id = cg.clone_id
        AND     cg.contig_id IN ($comma_list)     
        } ) ;
    $sth->execute() ;
    my ($contig_id) ;
    $sth->bind_columns(\$contig_id) ;
    
    # set all locks to 0
    while( my ($key , $clone) = each (%cs_hash)){
        $clone->set_lock_status(0) ;
    }
    
    # set the locked clones (from query result) to 1
    while ($sth->fetch){
        my $locked_clone  =  $cs_hash{$contig_id} ; 
        $locked_clone->set_lock_status(1) ;
    }
        
}

sub delete_SequenceSet{
    my ($self, $ss) = @_;

    # database connections
    my $otter_db    = $self->get_cached_DBAdaptor;
    my $pipeline_db = Bio::Otter::Lace::PipelineDB::get_pipeline_rw_DBAdaptor($otter_db);
    # delete sql
    my $delete_meta_info = qq{DELETE FROM sequence_set WHERE assembly_type = ?};
    my $delete_assembly  = qq{DELETE FROM assembly WHERE type = ?};
    my $name = $ss->name();
    warn "DELETING sequence set with name: $name \n";
    foreach my $adaptor($otter_db, $pipeline_db){
	my $sth = $adaptor->prepare($delete_meta_info);
	$sth->execute($name);
	$sth    = $adaptor->prepare($delete_assembly);
	$sth->execute($name);
    }
}

#
# DB connection handling
#-------------------------------------------------------------------------------
#
sub get_cached_DBAdaptor {
    my( $self ) = @_;

    unless($self->{'_dba_cache'}){
	    $self->{'_dba_cache'} = $self->make_DBAdaptor;
	    $self->_attach_DNA_DBAdaptor($self->{'_dba_cache'});
    }
    #warn "OTTER DBADAPTOR = '$dba'";
    return $self->{'_dba_cache'};
}

sub make_EnsEMBL_DBAdaptor {
    my( $self ) = @_;
    
    return $self->_make_DBAdptor_with_class('Bio::EnsEMBL::DBSQL::DBAdaptor');
}

sub make_DBAdaptor {
    my( $self ) = @_;

    return $self->_make_DBAdptor_with_class('Bio::Otter::DBSQL::DBAdaptor');
}

sub _make_DBAdptor_with_class {
    my( $self, $class ) = @_;
    
    my(@args);
    foreach my $prop ($self->list_all_db_properties) {
        if (my $val = $self->$prop()) {
            #print STDERR "-$prop  $val\n";
            push(@args, "-$prop", $val);
        }
    }

    return $class->new(@args);
}
sub _attach_DNA_DBAdaptor{
    my( $self, $dba ) = @_;

    return unless $dba;

    my(@ott_args, @dna_args);
    foreach my $prop (grep /^DNA/, $self->list_all_db_properties) {
	$prop =~ /DNA_(\w+)/;
        if (my $val = $self->$prop()) {
            push(@dna_args, "-$1", $val);
            push(@ott_args, "-$1", $self->$1);
        }
    }

    if(("@dna_args" eq "@ott_args") && @dna_args){
	#warn "They are the same the DBAdaptor will just return itself\n";
    }elsif(@dna_args){
	#warn "@dna_args\n";
	my $dnadb = Bio::EnsEMBL::DBSQL::DBAdaptor->new(@dna_args);
	$dba->dnadb($dnadb);
    }else{
	warn "No DNA_* options found. *** CHECK species.dat ***\n";
    }
}
sub disconnect_DBAdaptor {
    my( $self ) = @_;
    
    if (my $dba = $self->{'_dba_cache'}) {
        $self->{'_dba_cache'} = undef;
    }
}

sub list_all_db_properties {
    return qw{
        HOST
        USER
        DNA_PASS
        PASS
        DBNAME
        TYPE
        DNA_PORT
        DNA_HOST
        DNA_USER
	DNA_DBNAME
        PORT
        };
}

sub HOST {
    my( $self, $HOST ) = @_;
    
    if ($HOST) {
        $self->{'_HOST'} = $HOST;
    }
    return $self->{'_HOST'};
}

sub USER {
    my( $self, $USER ) = @_;
    
    if ($USER) {
        $self->{'_USER'} = $USER;
    }
    return $self->{'_USER'};
}

sub DNA_PASS {
    my( $self, $DNA_PASS ) = @_;
    
    if ($DNA_PASS) {
        $self->{'_DNA_PASS'} = $DNA_PASS;
    }
    return $self->{'_DNA_PASS'};
}

sub PASS {
    my( $self, $PASS ) = @_;
    
    if ($PASS) {
        $self->{'_PASS'} = $PASS;
    }
    return $self->{'_PASS'};
}

sub DBNAME {
    my( $self, $DBNAME ) = @_;
    
    if ($DBNAME) {
        $self->{'_DBNAME'} = $DBNAME;
    }
    return $self->{'_DBNAME'};
}

sub TYPE {
    my( $self, $TYPE ) = @_;
    
    if ($TYPE) {
        $self->{'_TYPE'} = $TYPE;
    }
    return $self->{'_TYPE'};
}

sub DNA_PORT {
    my( $self, $DNA_PORT ) = @_;
    
    if ($DNA_PORT) {
        $self->{'_DNA_PORT'} = $DNA_PORT;
    }
    return $self->{'_DNA_PORT'};
}

sub DNA_HOST {
    my( $self, $DNA_HOST ) = @_;
    
    if ($DNA_HOST) {
        $self->{'_DNA_HOST'} = $DNA_HOST;
    }
    return $self->{'_DNA_HOST'};
}

sub DNA_USER {
    my( $self, $DNA_USER ) = @_;
    
    if ($DNA_USER) {
        $self->{'_DNA_USER'} = $DNA_USER;
    }
    return $self->{'_DNA_USER'};
}
sub DNA_DBNAME {
    my( $self, $DNA_DBNAME ) = @_;
    
    if ($DNA_DBNAME) {
        $self->{'_DNA_DBNAME'} = $DNA_DBNAME;
    }
    return $self->{'_DNA_DBNAME'};
}
sub PORT {
    my( $self, $PORT ) = @_;
    
    if ($PORT) {
        $self->{'_PORT'} = $PORT;
    }
    return $self->{'_PORT'};
}


1;

__END__

=head1 NAME - Bio::Otter::Lace::DataSet

=head1 DESCRIPTION

The B<Bio::Otter::Lace> objects are designed for
use with the annotators' B<otterlace> interface,
where simple data objects for use behind the
graphical interface of the long-running client
are needed.  The standard Ensembl DBAdaptor
scheme was not used so that the database handle
can be dropped.  (Because of the DBAdaptor system
design, the database connection is usually only
dropped when all the data objects go out of
scope.)

There are also objects to represent the extra
tables found in the B<lace.sql> file in the otter
distribution (such as sequence sets and notes).

=head2 DataSet

The B<DataSet> object represents an entry in the
B<species.dat> file, which is, usually, a species
served by the otter server.

The DataSet object has an Ensembl B<DBAdaptor> -
it is the only object in the Lace system that
does, and there is a method
(B<disconnect_DBAdaptor>) to drop the database
connection.  It contains methods for saving data
to the extra tables defined in B<lace.sql>, and
which are represented by the other Lace data
objects.

Each DataSet contains one or more
B<SequenceSet>s.

=head2 SequenceSet

A SequenceSet is any list of clones that
annotators are working on, most often a
contiguous region of a genome.  Each SequenceSet
has a list of B<CloneSequence> objects.

=head2 CloneSequence

A CloneSequence is a container for some of the
data found in the Ensembl B<Clone> and B<Contig>
objects and in the B<assembly> table.  It has
zero or more B<SequenceNotes>, and, if there are
any, one of them is designated the current (most
recent) SeqeuenceNote.

=head2 SequenceNote

This is a remark added by an annotator to the
annotation interface to aid tracking the progress
of annotation.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

