
### Bio::Otter::Lace::DataSet

package Bio::Otter::Lace::DataSet;

use strict;
use Carp;
use Bio::Otter::DBSQL::DBAdaptor;
use Bio::Otter::Lace::CloneSequence;
use Bio::Otter::Lace::Chromosome;
use Bio::Otter::Lace::SequenceSet;
use Bio::Otter::Lace::SequenceNote;

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
            $al->{$set_name}{$author} = $access eq 'RW' ? 1 : 0;
        }
    }
    
    return $al;
}

sub get_all_SequenceSets {
    my( $self ) = @_;
    
    my( $ss );
    unless ($ss = $self->{'_sequence_sets'}) {
        $ss = $self->{'_sequence_sets'} = [];
        
        my $this_author = $self->author or confess "author not set";
        my $ssal = $self->sequence_set_access_list;
        
        my $dba = $self->get_cached_DBAdaptor;
        my $sth = $dba->prepare(q{
            SELECT assembly_type
              , description
            FROM sequence_set
            ORDER BY assembly_type
            });
        $sth->execute;
        
        my $ds_name = $self->name;
        while (my ($name, $desc) = $sth->fetchrow) {
            my( $write_flag );
            if (%$ssal) {
                $write_flag = $ssal->{$name}{$this_author};
                # If an author doesn't have an entry in the sequence_set_access
                # table for this set, then it is invisible to them.
                next unless defined $write_flag;
            } else {
                # No entries in sequence_set_access table - everyone can write
                $write_flag = 1;
            }
        
            my $set = Bio::Otter::Lace::SequenceSet->new;
            $set->name($name);
            $set->dataset_name($ds_name);
            $set->description($desc);
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

sub fetch_all_CloneSequences_for_SequenceSet {
    my( $self, $ss ) = @_;
    
    confess "Missing SequenceSet argument" unless $ss;
    confess "CloneSequences already fetched" if $ss->CloneSequence_list;
    
    my %id_chr = map {$_->chromosome_id, $_} $self->get_all_Chromosomes;
    my $cs = [];
    
    my $dba = $self->get_cached_DBAdaptor;
    my $type = $ss->name;
    my $sth = $dba->prepare(q{
        SELECT c.embl_acc, c.embl_version
          , g.contig_id, g.name, g.length
          , a.chromosome_id, a.chr_start, a.chr_end
          , a.contig_start, a.contig_end, a.contig_ori
        FROM assembly a
          , contig g
          , clone c
        WHERE a.contig_id = g.contig_id
          AND g.clone_id = c.clone_id
          AND a.type = ?
        ORDER BY a.chromosome_id
          , a.chr_start
        });
    $sth->execute($type);
    my(  $acc,  $sv,
         $ctg_id,  $ctg_name,  $ctg_length,
         $chr_id,  $chr_start,  $chr_end,
         $contig_start,  $contig_end,  $strand,
         );
    $sth->bind_columns(
        \$acc, \$sv,
        \$ctg_id, \$ctg_name, \$ctg_length,
        \$chr_id, \$chr_start, \$chr_end,
        \$contig_start, \$contig_end, \$strand,
        );
    while ($sth->fetch) {
        my $cl = Bio::Otter::Lace::CloneSequence->new;
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
        push(@$cs, $cl);
    }

    $ss->CloneSequence_list($cs);
}

sub fetch_all_SequenceNotes_for_SequenceSet {
    my( $self, $ss ) = @_;
    
    my $name = $ss->name or confess "No name in SequenceSet object";
    my $cs_list = $ss->CloneSequence_list;
    
    my $dba = $self->get_cached_DBAdaptor;
    my $sth = $dba->prepare(q{
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
    
    my( $ctg_id, $text, $time, $is_current, $author );
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
        if (my $notes = $ctg_notes{$cs->contig_id}) {
            foreach my $sn (sort {$b->timestamp <=> $a->timestamp} @$notes) {
                if ($sn->is_current) {
                    $cs->current_SequenceNote($sn);
                }
                $cs->add_SequenceNote($sn);
            }
        }
    }
}

sub save_current_SequenceNote_for_CloneSequence {
    my( $self, $cs ) = @_;
    
    confess "Missing CloneSequence argument" unless $cs;
    my $dba = $self->get_cached_DBAdaptor;
    my $author_id = $self->_author_id;

    my $contig_id = $cs->contig_id
        or confess "contig_id not set";
    my $current_note = $cs->current_SequenceNote
        or confess "current_SequenceNote not set";
    
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

sub get_cached_DBAdaptor {
    my( $self ) = @_;
    
    my $dba = $self->{'_dba_cache'} ||= $self->make_DBAdaptor;
    return $dba;
}

sub make_DBAdaptor {
    my( $self ) = @_;
    
    my(@args);
    foreach my $prop ($self->list_all_db_properties) {
        if (my $val = $self->$prop()) {
            #print STDERR "-$prop  $val\n";
            push(@args, "-$prop", $val);
        }
    }
    return Bio::Otter::DBSQL::DBAdaptor->new(@args);
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

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

