use strict;
use warnings;

package InterimTranscript;

use Bio::EnsEMBL::Utils::Exception qw(warning);



sub new {
  my $class = shift;

  return bless {'exons' => [],
                'StatsMsgs' => []}, $class;
}


sub add_StatMsg {
  my $self = shift;
  my $statMsg = shift;
  push @{$self->{'StatMsgs'}}, $statMsg;
}

sub get_all_StatMsgs {
  my $self = shift;
  return @{$self->{'StatMsgs'}};
}

sub last_StatMsg {
  my $self = shift;

  my @msgs = @{$self->{'StatMsgs'}};
  return undef if(!@msgs);
  return $msgs[$#msgs];
}

sub add_ProteinFeatures {
    my ($self, @pf) = @_;
    push @{ $self->{'protein_features'} }, @pf;
}

sub get_all_ProteinFeatures {
    my $self = shift;
    $self->{'protein_features'} ||= [];
    return $self->{'protein_features'};
}

sub add_Exon {
  my $self = shift;
  my $exon = shift;

  push @{$self->{'exons'}}, $exon;
}

sub get_all_Exons {
  my $self = shift;

  return $self->{'exons'};
}

sub flush_Exons {
  my $self = shift;
  $self->{'exons'} = [];
}


sub stable_id {
  my $self = shift;
  $self->{'stable_id'} = shift if(@_);
  return $self->{'stable_id'};
}

sub version {
  my $self = shift;
  $self->{'version'} = shift if(@_);
  return $self->{'version'};
}

sub biotype {
  my $self = shift;
  $self->{'biotype'} = shift if(@_);
  return $self->{'biotype'};
}

sub confidence {
  my $self = shift;
  $self->{'confidence'} = shift if(@_);
  return $self->{'confidence'};
}

sub description {
  my $self = shift;
  $self->{'description'} = shift if(@_);
  return $self->{'description'};
}

sub created_date {
  my $self = shift;
  $self->{'created_date'} = shift if(@_);
  return $self->{'created_date'};
}

sub modified_date {
  my $self = shift;
  $self->{'modified_date'} = shift if(@_);
  return $self->{'modified_date'};
}

sub cdna_coding_start {
  my $self = shift;
  $self->{'cdna_coding_start'} = shift if(@_);
  return $self->{'cdna_coding_start'};
}

sub cdna_coding_end {
  my $self = shift;
  $self->{'cdna_coding_end'} = shift if(@_);
  return $self->{'cdna_coding_end'};
}


sub move_cdna_coding_start {
  my $self = shift;
  my $offset = shift;
  $self->{'cdna_coding_start'} += $offset;
}

sub move_cdna_coding_end {
  my $self = shift;
  my $offset = shift;
  $self->{'cdna_coding_end'} += $offset;
}


1;
