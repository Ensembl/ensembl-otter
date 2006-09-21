package Bio::Otter::FromXML;

use strict;
use warnings;
use Carp qw{ cluck confess };

use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Translation;
use Bio::EnsEMBL::Gene;
use Bio::EnsEMBL::DBEntry;

use Bio::Otter::Author;

use Bio::Otter::AnnotatedTranscript;
use Bio::Otter::TranscriptInfo;
use Bio::Otter::TranscriptRemark;
use Bio::Otter::TranscriptClass;
use Bio::Otter::Evidence;

use Bio::Otter::AnnotatedGene;
use Bio::Otter::GeneInfo;
use Bio::Otter::GeneName;
use Bio::Otter::GeneRemark;
use Bio::Otter::GeneSynonym;

sub new {
    my ($class, $linearray, $slice) = @_;

    my $self = bless {}, $class;

    $self->linearray($linearray);
    $self->slice($slice);

    return $self;
}

sub linearray {
    my ($self, $linearray) = @_;

    if($linearray) {
        $self->{_linearray} = $linearray;
    }
    return $self->{_linearray};
}

sub get_new_line {
    my $self = shift @_;

    return shift @{$self->linearray()};
}

sub slice {
    my ($self, $slice) = @_;

    if($slice) {
        $self->{_slice} = $slice;
    }
    return $self->{_slice};
}

sub parse_next_line {
    my $self = shift @_;

    my $line = $self->get_new_line();

    if(!defined($line)) {
        return;
    } elsif($line=~s{^\s*<}{}) { # and get rid of the prefix if matched
        if($line=~m{^/(\w+)>\s*$}) { # closing tag
            return ('c', $1);
        } elsif($line=~s{^(\w+)>}{}) { # opening tag and ...
            my $tag = $1;
            if($line=~m{^\s*$}) { # just opening tag
                return ('o', $tag);
            } elsif($line=~m{^([^<]*)</$tag>\s*$}) { # tagpair
                my $data = $1;
                $data=~s/&gt;/>/g;
                $data=~s/&lt;/</g;

                return ('p', $tag, $data);
            }
        }
    }
    die "Restricted XML violation in '$line'";
}

sub build_Author {
    my $self = shift @_;

    my $author = Bio::Otter::Author->new();

    while( my($kind,$tag,$data) = $self->parse_next_line() ) {
        if(($kind eq 'c') && ($tag eq 'author')) {
            last;
        } elsif($kind eq 'p') {
            if($tag eq 'name') {
                $author->name($data);
            } elsif($tag eq 'email') {
                $author->email($data);
            }
        }
    }
    return $author;
}

sub build_Evidence {
    my $self = shift @_;

    my $evidence = Bio::Otter::Evidence->new();
    $evidence->type('UNKNOWN');

    while( my($kind,$tag,$data) = $self->parse_next_line() ) {
        if(($kind eq 'c') && ($tag eq 'evidence')) {
            last;
        } elsif($kind eq 'p') {
            if($tag eq 'name') {
                $evidence->name($data);
            } elsif($tag eq 'type') {
                $evidence->type($data);
            }
        }
    }
    return $evidence;
}

sub build_TranscriptInfo {
    my $self = shift @_;

    my $tinfo = Bio::Otter::TranscriptInfo->new();

    while( my($kind,$tag,$data) = $self->parse_next_line() ) {
        if(($kind eq 'c') && ($tag eq 'transcript_info')) {
            last;
        } elsif($kind eq 'p') {
            if($tag eq 'name') {
                $tinfo->name($data);
            } elsif($tag eq 'transcript_class') {
                $tinfo->class(Bio::Otter::TranscriptClass->new(-name=>$data));
            } elsif($tag eq 'remark') {
                $tinfo->remark(Bio::Otter::TranscriptRemark->new(-remark=>$data));
            } elsif($tag eq 'mRNA_start_not_found') {
                $tinfo->mRNA_start_not_found($data);
            } elsif($tag eq 'mRNA_end_not_found') {
                $tinfo->mRNA_end_not_found($data);
            } elsif($tag eq 'cds_start_not_found') {
                $tinfo->cds_start_not_found($data);
            } elsif($tag eq 'cds_end_not_found') {
                $tinfo->cds_end_not_found($data);
            }
        } elsif($kind eq 'o') {
            if($tag eq 'author') {
                $tinfo->author($self->build_Author());
            } elsif($tag eq 'evidence') {
                $tinfo->add_Evidence($self->build_Evidence());
            }
        }
    }
    return $tinfo;
}

sub build_Exon {
    my $self = shift @_;

    my $exon = Bio::EnsEMBL::Exon->new();
    my $slice = $self->slice();
    $exon->contig($slice);
    my $coord_offset = $slice->chr_start()-1;

    # my $time_now = time;

    while( my($kind,$tag,$data) = $self->parse_next_line() ) {
        if(($kind eq 'c') && ($tag eq 'exon')) {
            last;
        } elsif($kind eq 'p') {
            if($tag eq 'stable_id') {
                $exon->stable_id($data);
                    # next 3 lines are copied from Converter.pm without understanding:
                # $exon->version(1);
                # $exon->created($time_now);
                # $exon->modified($time_now);
            } elsif($tag eq 'start') {
                $exon->start($data - $coord_offset);
            } elsif($tag eq 'end') {
                $exon->end($data - $coord_offset);
            } elsif($tag eq 'strand') {
                $exon->strand($data);
            } elsif($tag eq 'frame') {
                $exon->phase((3-$data)%3);
            }
        }
    }
    return $exon;
}

sub exon_pos {      # map translation onto the exons:
  my ($tran, $loc) = @_;
 
  foreach my $exon (@{ $tran->get_all_Exons }) {
 
    if ($loc <= $exon->end && $loc >= $exon->start) {
      if ($exon->strand == 1) {
        return ($exon, ($loc - $exon->start) + 1);
      } else {
        return ($exon, ($exon->end - $loc) + 1);
      }
    }
  }
  return (undef, undef);
}

sub build_Translation {
    my ($self, $transcript) = @_;

    my $translation = Bio::EnsEMBL::Translation->new();
    my $coord_offset = $self->slice()->chr_start()-1;

    my ($tl_start, $tl_end);

    while( my($kind,$tag,$data) = $self->parse_next_line() ) {
        if(($kind eq 'c') && ($tag eq 'translation')) {
            last;
        } elsif($kind eq 'p') {
            if($tag eq 'start') {
                $tl_start = $data - $coord_offset;      # store it temporarily
            } elsif($tag eq 'end') {
                $tl_end = $data - $coord_offset;        # store it temporarily
            } elsif($tag eq 'stable_id') {
                $translation->stable_id($data);
                    # next 1 line is copied from Converter.pm without understanding:
                # $translation->version(1);
            }
        }
    }

        # At end of transcript section need to position translation
        # if there is one. We need to do this after we have all the
        # exons
      if (defined($tl_start) && defined($tl_end)) {
                                                                                           
        my ($start_exon, $start_pos) = exon_pos($transcript, $tl_start);
        my ($end_exon,   $end_pos)   = exon_pos($transcript, $tl_end);
                                                                                           
        if (!defined($start_exon) || !defined($end_exon)) {
                                                                                           
          if (!defined($start_exon)) {warn "no start exon"};
          if (!defined($end_exon)) {warn "no end exon"};
                                                                                           
          print STDERR "ERROR: Failed mapping translation to transcript\n";
        } else {
          $translation->start_Exon($start_exon);
          $translation->start($start_pos);
                                                                                           
          if ($start_exon->strand == 1 && $start_exon->start != $tl_start) {
            #$start_exon->phase(-1);
            $start_exon->end_phase(($start_exon->length-$start_pos+1)%3);
          } elsif ($start_exon->strand == -1 && $start_exon->end != $tl_start) {
            #$start_exon->phase(-1);
            $start_exon->end_phase(($start_exon->length-$start_pos+1)%3);
          }
                                                                                           
          $translation->end_Exon($end_exon);
          $translation->end($end_pos);
                                                                                           
          if ($end_exon->length >= $end_pos) {
            $end_exon->end_phase(-1);
          }
        }
      } elsif (defined($tl_start) || defined($tl_end)) {
        print STDERR "ERROR: Either translation start or translation end undefined\n";
      }

    return $translation;
}

sub build_Transcript {
    my $self = shift @_;

    my $transcript = Bio::EnsEMBL::Transcript->new();

    while( my($kind,$tag,$data) = $self->parse_next_line() ) {
        if(($kind eq 'c') && ($tag eq 'transcript')) {
            last;
        } elsif($kind eq 'p') {
            if($tag eq 'stable_id') {
                $transcript->stable_id($data);
                    # next 1 line is copied from Converter.pm without understanding:
                # $transcript->version(1);
            }
        } elsif($kind eq 'o') {
            if($tag eq 'xref') {
                $transcript->add_DBEntry($self->build_DBEntry());
            } elsif($tag eq 'exon') {
                $transcript->add_Exon($self->build_Exon());
            } elsif($tag eq 'translation') {
                $transcript->translation($self->build_Translation($transcript));
            } elsif($tag eq 'transcript_info') {
                bless $transcript, 'Bio::Otter::AnnotatedTranscript';
                $transcript->transcript_info($self->build_TranscriptInfo());
            }
        }
    }
    return $transcript;
}

sub build_GeneInfo {
    my $self = shift @_;

    my $ginfo = Bio::Otter::GeneInfo->new();

    while( my($kind,$tag,$data) = $self->parse_next_line() ) {
        if(($kind eq 'c') && ($tag eq 'gene_info')) {
            last;
        } elsif($kind eq 'p') {
            if($tag eq 'name') {
                $ginfo->name(Bio::Otter::GeneName->new(-name=>$data));
            } elsif($tag eq 'truncated') {
                $ginfo->truncated_flag($data);
            } elsif($tag eq 'known') {
                $ginfo->known_flag($data);
            } elsif($tag eq 'remark') {
                $ginfo->remark(Bio::Otter::GeneRemark->new(-remark=>$data));
            } elsif($tag eq 'synonym') {
                $ginfo->synonym(Bio::Otter::GeneSynonym->new(-name=>$data));
            }
        } elsif($kind eq 'o') {
            if($tag eq 'author') {
                $ginfo->author($self->build_Author());
            }
        }
    }
    return $ginfo;
}

sub build_DBEntry {
    my $self = shift @_;

    my $dbentry = Bio::EnsEMBL::DBEntry->new();

    while( my($kind,$tag,$data) = $self->parse_next_line() ) {
        if(($kind eq 'c') && ($tag eq 'xref')) {
            last;
        } elsif($kind eq 'p') {
            if($tag eq 'primary_id') {
                $dbentry->primary_id($data);
            } elsif($tag eq 'display_id') {
                $dbentry->display_id($data);
            } elsif($tag eq 'version') {
                $dbentry->version($data);
            } elsif($tag eq 'release') {
                $dbentry->release($data);
            } elsif($tag eq 'dbname') {
                $dbentry->dbname($data);
            } elsif($tag eq 'description') {
                $dbentry->description($data);
            }
        }
    }
    return $dbentry;
}

sub build_Gene {
    my $self = shift @_;

    my $gene = Bio::EnsEMBL::Gene->new();
    # my $time_now = time;

    while( my($kind,$tag,$data) = $self->parse_next_line() ) {
        if(($kind eq 'c') && ($tag eq 'locus')) {
            last;
        } elsif($kind eq 'p') {
            if($tag eq 'stable_id') {
                $gene->stable_id($data);
                    # next 3 lines are copied from Converter.pm without understanding:
                # $gene->version(1);
                # $gene->created($time_now);
                # $gene->modified($time_now);
            } elsif($tag eq 'type') {
                $gene->type($data);
            } elsif($tag eq 'description') {
                $gene->description($data);
            }
        } elsif($kind eq 'o') {
            if($tag eq 'xref') {
                $gene->add_DBEntry($self->build_DBEntry());
            } elsif($tag eq 'gene_info') {
                bless $gene, 'Bio::Otter::AnnotatedGene';
                $gene->gene_info($self->build_GeneInfo());
            } elsif($tag eq 'transcript') {
                $gene->add_Transcript($self->build_Transcript());
            }
        }
    }
    return $gene;
}

sub build_Gene_array {
    my $self = shift @_;

    my @gene_array;

    while( my($kind,$tag,$data) = $self->parse_next_line() ) {
        if($kind eq 'o') {
            if($tag eq 'locus') {
                push @gene_array, $self->build_Gene();
            } else {
                confess "not expecting any other entries except loci";
            }
        } else {
            confess "not expecting any other types of entries except <locus>...</locus>*";
        }
    }

    return \@gene_array;
}

1;

__END__

