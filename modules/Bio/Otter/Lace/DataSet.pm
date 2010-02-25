
### Bio::Otter::Lace::DataSet

package Bio::Otter::Lace::DataSet;

use strict;
use warnings;
use Carp;
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

sub get_config {
    my ($self, $section) = @_;
    
    my $conf = $self->{'_get_config_cache'}{$section}
        ||= $self->_config_from_client($section);
    return $conf;
}

sub _config_from_client {
    my ($self, $section) = @_;
    
    my $client = $self->Client or confess "No Client attached";
    
    my $ds = $self;
    # Used to fetch config from both ALIAS dataset and this dataset
    # but this does not work because the "default" setting in
    # this dataaset override the settings in the ALIAS dataset.
    if (my $alias = $ds->ALIAS) {
        $ds = $client->get_DataSet_by_name($alias);
    }
    
    my $config = {};
    my $name = $ds->name;
    my $nc = $client->option_from_array([$name, $section]);
    while (my ($tag, $val) = each %$nc) {
        $config->{$tag} = $val;
    }
    
    return $config;
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

    my $values = $self->meta_hash->{$key};

    confess "No entry in meta table under key '$key'" if ! @{$values};
    confess "Multiple entries in meta table under key '$key'" if @{$values} > 1;

    return $values->[0];
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

sub fetch_all_CloneSequences_for_selected_SequenceSet {
    my( $self ) = @_;
    
    my $ss = $self->selected_SequenceSet
        or confess "No SequenceSet is selected";
    return $self->fetch_all_CloneSequences_for_SequenceSet($ss);
}

sub fetch_all_CloneSequences_for_SequenceSet {
    my( $self, $ss, $other_things_too ) = @_;
    confess "Missing SequenceSet argument" unless $ss;
    my $client = $self->Client or confess "No otter Client attached";

    my $cs_list=$client->get_all_CloneSequences_for_DataSet_SequenceSet($self, $ss);
    if($other_things_too) {
        $client->fetch_all_SequenceNotes_for_DataSet_SequenceSet($self, $ss);
        $client->lock_refresh_for_DataSet_SequenceSet($self, $ss);
        $client->status_refresh_for_DataSet_SequenceSet($self, $ss);
    }

    return $cs_list;
}

#
# DB connection handling
#-------------------------------------------------------------------------------
#
sub get_cached_DBAdaptor {
    my( $self ) = @_;

    unless($self->{'_dba_cache'}){
	    $self->{'_dba_cache'} = $self->make_Vega_DBAdaptor;
	    $self->_attach_DNA_DBAdaptor($self->{'_dba_cache'});
    }
    #warn "OTTER DBADAPTOR = '$dba'";
    return $self->{'_dba_cache'};
}

sub make_EnsEMBL_DBAdaptor {
    my( $self ) = @_;
    
    require Bio::EnsEMBL::DBSQL::DBAdaptor;
    return $self->_make_DBAdaptor_with_class('Bio::EnsEMBL::DBSQL::DBAdaptor');
}

sub make_Vega_DBAdaptor {
    my( $self ) = @_;

    require Bio::Vega::DBSQL::DBAdaptor;
    return $self->_make_DBAdaptor_with_class('Bio::Vega::DBSQL::DBAdaptor');
}

sub _make_DBAdaptor_with_class {
    my( $self, $class ) = @_;
    
    my(@args) = (
        # Extra arguments to stop Bio::EnsEMBL::Registry issuing warnings
        -GROUP      => "otter:$class",
        -SPECIES    => $self->name,
        );

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
    foreach my $this ($self->list_all_db_properties) {
        if (my ($prop) = $this =~ /^DNA_(\w+)/) {
            if (my $val = $self->$this()) {
                push(@dna_args, "-$prop", $val);
                push(@ott_args, "-$prop", $self->$prop());
            }
        }
    }

    if(("@dna_args" eq "@ott_args") && @dna_args){
        #warn "They are the same the DBAdaptor will just return itself\n";
    }elsif(@dna_args){
        #warn "dna_args: @dna_args\n";
        my $dnadb = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
            @dna_args,
            # Extra arguments to stop Bio::EnsEMBL::Registry issuing warnings
            -GROUP      => 'dnadb',
            -SPECIES    => $self->name,
            );
        $dba->dnadb($dnadb);
    }else{
        warn "No DNA_* options found. *** CHECK species.dat ***\n";
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
        ALIAS
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

sub ALIAS {
    my( $self, $ALIAS ) = @_;
    
    if(defined($ALIAS)) {
        $self->{'_ALIAS'} = $ALIAS;
    }
    return $self->{'_ALIAS'};
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
does.  It contains methods for saving data
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

