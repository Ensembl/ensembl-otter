
### Bio::Otter::Lace::DataSet

package Bio::Otter::Lace::DataSet;

use strict;
use Carp;
use Bio::Otter::DBSQL::DBAdaptor;
use Bio::Otter::Lace::CloneSequence;
use Bio::Otter::Lace::Chromosome;

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

sub selected_CloneSequences {
    my( $self, $selected_CloneSequences ) = @_;
    
    if ($selected_CloneSequences) {
        $self->{'_selected_CloneSequences'} = $selected_CloneSequences;
    }
    return $self->{'_selected_CloneSequences'};
}

sub unselect_all_CloneSequences {
    my( $self ) = @_;
    
    $self->{'_selected_CloneSequences'} = undef;
}

sub selected_CloneSequences_as_contig_list {
    my( $self ) = @_;
    
    my $cs_list = $self->selected_CloneSequences
        or return;
    my $ctg = [];
    my $ctg_list = [$ctg];
    foreach my $this (sort {
        $a->chromosome->chromosome_id <=> $b->chromosome->chromosome_id ||
        $a->chr_start <=> $b->chr_start
        } @$cs_list)
    {
        my $last = $ctg->[$#$ctg];
        if ($last) {
            if ($last->chr_end + 1 == $this->chr_start) {
                push(@$ctg, $this);
            } else {
                $ctg = [$this];
                push(@$ctg_list, $ctg);
            }
        } else {
            push(@$ctg, $this);
        }
    }
    return $ctg_list;
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

sub get_all_CloneSequences {
    my( $self ) = @_;
    
    my( $cs );
    unless ($cs = $self->{'_clone_sequences'}) {
        my %id_chr = map {$_->chromosome_id, $_} $self->get_all_Chromosomes;
    
        $cs = $self->{'_clone_sequences'} = [];
        my $dba = $self->get_cached_DBAdaptor;
        my $type = $dba->assembly_type;
        my $sth = $dba->prepare(q{
            SELECT c.embl_acc
              , c.embl_version
              , g.length
              , a.chromosome_id
              , a.chr_start
              , a.chr_end
              , a.contig_start
              , a.contig_end
              , a.contig_ori
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
        my( $acc, $sv,
            $ctg_length, $chr_id,
            $chr_start, $chr_end,
            $contig_start, $contig_end, $strand );
        $sth->bind_columns( \$acc, \$sv,
            \$ctg_length, \$chr_id,
            \$chr_start, \$chr_end,
            \$contig_start, \$contig_end, \$strand );
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
            push(@$cs, $cl);
        }
    }
    return $cs;
}

sub get_cached_DBAdaptor {
    my( $self ) = @_;
    
    my( $dba );
    unless ($dba = $self->{'_dba_cache'}) {
        $dba = $self->{'_dba_cache'} = $self->make_DBAdaptor;
    }
    return $dba;
}

sub make_DBAdaptor {
    my( $self ) = @_;
    
    my(@args);
    foreach my $prop ($self->list_all_properties) {
        if (my $val = $self->$prop()) {
            push(@args, "-$prop", $val);
        }
    }
    return Bio::Otter::DBSQL::DBAdaptor->new(@args);
}

sub list_all_properties {
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

