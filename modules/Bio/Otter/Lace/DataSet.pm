
### Bio::Otter::Lace::DataSet

package Bio::Otter::Lace::DataSet;

use strict;
use Carp;
use Bio::Otter::DBSQL::DBAdaptor;
use Bio::Vega::DBSQL::DBAdaptor;
use Bio::Otter::Lace::CloneSequence;
#use Bio::Otter::CloneLock;
use Bio::Otter::Author;
use Bio::Otter::Lace::SequenceSet;
use Bio::Otter::Lace::SequenceNote;
use Bio::Otter::Lace::PipelineDB;
use Bio::Otter::Lace::SatelliteDB;
use Bio::Otter::Lace::Defaults;
use Scalar::Util 'weaken';

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

sub Client {
  my( $self, $client ) = @_;
  if ($client) {
    $self->{'_Client'} = $client;
    weaken $self->{'_Client'};
  }
  return $self->{'_Client'};
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub meta_hash {
    my ($self) = @_;

    my $meta;
    unless ($meta = $self->{'_meta_hash'}) {

        # Get all of meta table in one call
        $meta = $self->{'_meta_hash'} =
          $self->Client()->get_meta($self->name, 'otter');
    }
    return $meta;
}

sub get_meta_value {
    my ($self, $key) = @_;

    if (my $val = $self->meta_hash->{$key}) {
        # Return string of all values (often just one!) in scalar context
        return wantarray ? @$val : "@$val";
    }
    else {
        warn "No entry in meta table under key '$key'";
    }
}

sub taxon {
    my ($self) = @_;

    unless ($self->{'_taxon_id'}) {
        $self->{'_taxon_id'} = $self->get_meta_value('species.taxonomy_id');
    }
    return $self->{'_taxon_id'};
}

sub species {
    my ($self) = @_;

    unless ($self->{'_species'}) {
        $self->{'_species'} = $self->get_meta_value('species.common_name');
    }
    return $self->{'_species'};
}

sub stable_id_prefix {
    my ($self) = @_;

    unless ($self->{'_stable_id_prefix'}) {
        my $pri = $self->get_meta_value('prefix.primary');
        my $spe = $self->get_meta_value('prefix.species');
        confess
"Need entries for both 'prefix.primary' and 'prefix.species' in otter meta table"
          unless $pri and $spe;
        $self->{'_stable_id_prefix'} = "$pri$spe";
    }
    return $self->{'_stable_id_prefix'};
}

sub sequence_sets_cached {
  my( $self, $ss ) = @_;
  if ($ss) {
    $self->{'_sequence_sets'} = $ss;
  }
  return $self->{'_sequence_sets'};
}

sub sequence_set_access_list_cached {
  my( $self, $al ) = @_;
  if ($al) {
    $self->{'_sequence_set_access_list'} = $al;
  }
  return $self->{'_sequence_set_access_list'};
}

sub get_sequence_set_access_list {
    my( $self ) = @_;
    my $al = $self->sequence_set_access_list_cached;
    return $al if (defined $al && scalar(@$al));

    my $client = $self->Client or confess "No otter Client attached";
    $al = $client->get_SequenceSet_AccessList_for_DataSet($self);
    $self->sequence_set_access_list_cached($al);
    return $al;
}

sub get_all_visible_SequenceSets {
  my( $self) = @_;
  my $ss_list= $self->get_all_SequenceSets();
  my $visible = [];
  foreach my $ss (@$ss_list) {
     unless($ss->is_hidden) {
        push @$visible, $ss;
     }
  }
  return $visible;
}

sub get_all_SequenceSets {
  my ($self)=@_;
  my $seq_sets =$self->sequence_sets_cached;
  return $seq_sets if (defined($seq_sets) && scalar(@$seq_sets));

  my $client = $self->Client or confess "No otter Client attached";
  $seq_sets = $client->get_all_SequenceSets_for_DataSet($self);
  $self->sequence_sets_cached($seq_sets);

  return $seq_sets;
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

sub fetch_all_CloneSequences_for_SequenceSet {
    my( $self, $ss ) = @_;
    confess "Missing SequenceSet argument" unless $ss;
    my $client = $self->Client or confess "No otter Client attached";
    my $cs=$client->get_all_CloneSequences_for_DataSet_SequenceSet($self, $ss);
    return $cs;
}

sub _tmp_table_by_name{
    my ($self, $id) = @_;
    $self->{'temp_table_name_cache'}->{$id} ||= "storing_${id}_$$";
    return $self->{'temp_table_name_cache'}->{$id};
}

sub tmpstore_meta_info_for_SequenceSet {
    my ($self, $ss, $adaptors) = @_;

    # check I'm a nice sequence set in $ss
    confess("$ss says I'm not a sequence set")
      unless $ss->isa("Bio::Otter::Lace::SequenceSet");

    # write some sql
    my $tmp_tbl_meta   = $self->_tmp_table_by_name("meta_info");
    my $create_tmp_tbl =
qq{CREATE TEMPORARY TABLE $tmp_tbl_meta SELECT * FROM sequence_set WHERE 1 = 0};
    my $insert_ss =
qq{INSERT INTO $tmp_tbl_meta (assembly_type, description, analysis_priority, hide) VALUES(?, ?, ?, 'Y')};
    my $max_chr_end_q = qq{SELECT IFNULL(MAX(a.chr_end), 0) AS max_chr_end 
				   FROM $tmp_tbl_meta ss, assembly a 
				   WHERE ss.assembly_type = a.type 
				   && ss.assembly_type = ?};

    # some sequence set info
    my $new_desc     = $ss->description();
    my $new_name     = $ss->name();
    my $new_priority = $ss->priority() || 5;
    my $max_chr_end  = 0;

    # create/fill/read temporary table
    foreach my $adaptor (@$adaptors) {
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

sub store_SequenceSet {
    my ($self, $ss, $seqfetch_code, $allow_update, $store_pipe) = @_;

    require Bio::EnsEMBL::Clone;
    require Bio::EnsEMBL::RawContig;

    # check I'm a nice sequence set in $ss
    confess("$ss says I'm not a sequence set")
      unless $ss->isa("Bio::Otter::Lace::SequenceSet");

    # get the previous sequence_set with the same name.
    eval { $self->get_SequenceSet_by_name($ss->name) };
    if (!$@) {
        confess "Adding to a previos AGP with another is not allowed"
          unless $allow_update;
    }

    # write some sql
    my $tmp_tbl_assembly = $self->_tmp_table_by_name("assembly");
    my $create_tmp_tbl   = qq{
        CREATE TEMPORARY TABLE $tmp_tbl_assembly
        SELECT * FROM assembly WHERE 1 = 0
        };
    my $insert_query = qq{
        INSERT INTO $tmp_tbl_assembly (chromosome_id
              , chr_start
              , chr_end
              , superctg_name
              , superctg_start
              , superctg_end
              , superctg_ori
              , contig_id
              , contig_start
              , contig_end
              , contig_ori
              , type )
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
        };

    # database connections
    my $otter_db = $self->get_cached_DBAdaptor;
    my $dba_list = [];
    if (my $ens_db = $self->make_EnsEMBL_DBAdaptor) {
        push(@$dba_list, $ens_db);
    }
    else {
        confess "Can't connect to 'self' db";
    }

    # Only attempt to connect to pipeline_db
    # if we are asked to write to it and
    # it is mentioned in the meta table.
    if ($store_pipe and @{ $otter_db->get_MetaContainer->list_value_by_key('pipeline_db') }) {
        my $pipeline_db =
          Bio::Otter::Lace::PipelineDB::get_pipeline_rw_DBAdaptor($otter_db)
          or confess "Can't connect to pipeline db";
        push(@$dba_list, $pipeline_db);
    }

    my $max_chr_length =
      $self->tmpstore_meta_info_for_SequenceSet($ss, $dba_list);

    # execute query to create temp
    my $pipe_contigs = [];
    foreach my $dba (@$dba_list) {
        my $is_pipe = $dba->isa('Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor');
    
        $dba->do($create_tmp_tbl);

        # prepare the assembly insert query for each db
        my $insert_sth = $dba->prepare($insert_query);

        # get clone_adaptor
        my $clone_adaptor = $dba->get_CloneAdaptor;

        # go through the clones in the list storing them in the
        # clone/contig/dna tables
        # temp assembly table
        foreach my $cloneSeq (@{ $ss->CloneSequence_list }) {
            my $acc = $cloneSeq->accession();
            my $sv  = $cloneSeq->sv();

            my $clone = $self->_fetch_clone($clone_adaptor, $acc, $sv, $seqfetch_code);

            $self->_store_clone($clone_adaptor, $clone) unless $clone->dbID;
            my $contig = $clone->get_all_Contigs->[0];

            # store the assembly
            $insert_sth->execute(
                $is_pipe ? $cloneSeq->pipeline_chromosome : $cloneSeq->chromosome,
                $cloneSeq->chr_start,  $cloneSeq->chr_end,
                $cloneSeq->super_contig_name,
                $cloneSeq->chr_start,  $cloneSeq->chr_end,
                1,    # super_contig_orientation
                $contig->dbID,         $cloneSeq->contig_start,
                $cloneSeq->contig_end, $cloneSeq->contig_strand,
                $ss->name,
            );

            push(@$pipe_contigs, $contig) if $is_pipe;
        }
    }

    #    $self->__dump_table("assembly", [$pipeline_db, $ens_db]);
    #    $self->__dump_table("meta_info", [$pipeline_db, $ens_db]);

    # if everythings ok "commit" sequence_set table and assembly table
    # insert into sequence_set select from temporary table
    my $tmp_tbl_mi = $self->_tmp_table_by_name("meta_info");
    foreach my $dba (@$dba_list) {
        $dba->do(qq{INSERT IGNORE INTO assembly SELECT * FROM $tmp_tbl_assembly});
        $dba->do(qq{INSERT IGNORE INTO sequence_set SELECT * FROM $tmp_tbl_mi});
    }
    return $pipe_contigs;    # return the pipeline contigs
}



sub __dump_table {
    my ($self, $name, $adaptors, $other) = @_;
    my $tmp = ($other ? $other : $self->_tmp_table_by_name($name));
    return unless defined $tmp;
    my $query = "SELECT * FROM $tmp";
    foreach my $adaptor (@$adaptors) {
        my $sth = $adaptor->prepare($query);
        $sth->execute();
        print STDERR "TABLE: $tmp\n";
        while (my $row = $sth->fetchrow_arrayref) {
            print STDERR join("\t", @$row) . "\n";
        }
    }
}

sub _fetch_clone {
    my ($self, $clone_adaptor, $acc, $sv, $seqfetcher) = @_;

    my $clones = [];

    my $clone;
    eval { $clone = $clone_adaptor->fetch_by_accession_version($acc, $sv) };
    if ($clone) {
        warn "clone <"
          . $clone->embl_id
          . "> is already in the "
          . $clone_adaptor->db->dbname
          . " database\n";
        my $contigs = $clone->get_all_Contigs;
        my $count   = @$contigs;
        unless ($count == 1) {
            die "Clone '$acc' has $count contigs";
        }
    }
    else {
        my $acc_sv = "$acc.$sv";
        my $seq = $seqfetcher->($acc_sv);
        $clone = $self->_make_clone($seq, $acc, $sv);
    }

    return $clone;
}

sub _make_clone {
    my ($self, $seq, $acc, $sv) = @_;

    my $acc_sv = "$acc.$sv";

    # Create the clone
    my $clone  = Bio::EnsEMBL::Clone->new();
    $clone->id("$acc_sv");    ### Should set to international clone name
    $clone->embl_id($acc);
    $clone->embl_version($sv);
    $clone->htg_phase(3);     ### Not all are "Finished" (phase 3)
    $clone->version(1);
    $clone->created(time);
    $clone->modified(time);

    # Create the contig
    my $contig = Bio::EnsEMBL::RawContig->new;
    my $end    = $seq->length;
    $contig->name("$acc_sv.1." . $seq->length);
    $contig->length($seq->length);
    $contig->embl_offset(1);
    $contig->seq($seq->seq);
    $clone->add_Contig($contig);

    return $clone;
}

sub _store_clone {
    my ($self, $clone_adaptor, $clone) = @_;

    eval { $clone_adaptor->store($clone); };
    if ($@) {
        print STDERR "Problems writing "
          . $clone->id
          . " to database. \nProblem was "
          . $@;
    }
}

sub update_SequenceSet {
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

sub delete_SequenceSet {
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

sub make_DBAdaptor {
    my( $self ) = @_;

    return $self->HEADCODE() ? $self->make_Vega_DBAdaptor() : $self->make_Otter_DBAdaptor();
}

sub make_Otter_DBAdaptor {
    my( $self ) = @_;

    return $self->_make_DBAdptor_with_class('Bio::Otter::DBSQL::DBAdaptor');
}

sub make_EnsEMBL_DBAdaptor {
    my( $self ) = @_;
    
    return $self->_make_DBAdptor_with_class('Bio::EnsEMBL::DBSQL::DBAdaptor');
}

sub make_Vega_DBAdaptor {
    my( $self ) = @_;

    return $self->_make_DBAdptor_with_class('Bio::Vega::DBSQL::DBAdaptor');
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
        # warn "dna_args: @dna_args\n";
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
        HEADCODE
        };
}

sub HOST {
    my( $self, $HOST ) = @_;
    
    if(defined($HOST)) {
        $self->{'_HOST'} = $HOST;
    }
    return $self->{'_HOST'};
}

sub USER {
    my( $self, $USER ) = @_;
    
    if(defined($USER)) {
        $self->{'_USER'} = $USER;
    }
    return $self->{'_USER'};
}

sub DNA_PASS {
    my( $self, $DNA_PASS ) = @_;
    
    if(defined($DNA_PASS)) {
        $self->{'_DNA_PASS'} = $DNA_PASS;
    }
    return $self->{'_DNA_PASS'};
}

sub PASS {
    my( $self, $PASS ) = @_;
    
    if(defined($PASS)) {
        $self->{'_PASS'} = $PASS;
    }
    return $self->{'_PASS'};
}

sub DBNAME {
    my( $self, $DBNAME ) = @_;
    
    if(defined($DBNAME)) {
        $self->{'_DBNAME'} = $DBNAME;
    }
    return $self->{'_DBNAME'};
}

sub TYPE {
    my( $self, $TYPE ) = @_;
    
    if(defined($TYPE)) {
        $self->{'_TYPE'} = $TYPE;
    }
    return $self->{'_TYPE'};
}

sub DNA_PORT {
    my( $self, $DNA_PORT ) = @_;
    
    if(defined($DNA_PORT)) {
        $self->{'_DNA_PORT'} = $DNA_PORT;
    }
    return $self->{'_DNA_PORT'};
}

sub DNA_HOST {
    my( $self, $DNA_HOST ) = @_;
    
    if(defined($DNA_HOST)) {
        $self->{'_DNA_HOST'} = $DNA_HOST;
    }
    return $self->{'_DNA_HOST'};
}

sub DNA_USER {
    my( $self, $DNA_USER ) = @_;
    
    if(defined($DNA_USER)) {
        $self->{'_DNA_USER'} = $DNA_USER;
    }
    return $self->{'_DNA_USER'};
}
sub DNA_DBNAME {
    my( $self, $DNA_DBNAME ) = @_;
    
    if(defined($DNA_DBNAME)) {
        $self->{'_DNA_DBNAME'} = $DNA_DBNAME;
    }
    return $self->{'_DNA_DBNAME'};
}
sub PORT {
    my( $self, $PORT ) = @_;
    
    if(defined($PORT)) {
        $self->{'_PORT'} = $PORT;
    }
    return $self->{'_PORT'};
}
sub HEADCODE {
    my( $self, $HEADCODE ) = @_;
    
    if(defined($HEADCODE)) {
        $self->{'_HEADCODE'} = $HEADCODE;
    }
    return $self->{'_HEADCODE'};
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

