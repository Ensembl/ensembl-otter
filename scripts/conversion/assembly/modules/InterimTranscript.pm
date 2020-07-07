=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

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

sub status {
  my $self = shift;
  $self->{'status'} = shift if(@_);
  return $self->{'status'};
}

sub analysis {
  my $self = shift;
  $self->{'analysis'} = shift if(@_);
  return $self->{'analysis'};
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

sub transcript_attribs {
  my $self = shift;
  my $attribs;
  if ( ($attribs) = @_) {
    my $new_attribs;
    foreach my $attrib (@{$attribs}) {
      #don't transfer ccds attribs since e! don't want them
      next if ($attrib->code eq 'ccds');
      push @{$new_attribs},$attrib;
    }
    $self->{'transcript_attribs'} = $new_attribs;
  }
  return $self->{'transcript_attribs'};
}

sub add_TranscriptSupportingFeature {
    my ($self, $sf) = @_;
    push @{ $self->{'transcript_supporting_features'} }, $sf;
}

sub get_all_TranscriptSupportingFeatures {
    my $self = shift;
    $self->{'transcript_supporting_features'} ||= [];
    return $self->{'transcript_supporting_features'};
}

#sub display_xref {
#    my $self = shift;
#    $self->{'display_xref'} = shift if (@_);
#    return $self->{'display_xref'};
#}



1;
