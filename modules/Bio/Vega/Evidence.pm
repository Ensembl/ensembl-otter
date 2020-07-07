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

package Bio::Vega::Evidence;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use Bio::Vega::Evidence::Types qw( evidence_type_valid_all );
use base 'Bio::EnsEMBL::Storable';

sub new {
  my ($class, @args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($name,$type)  = rearrange([qw(
NAME
TYPE
)
                                ],@args);

  $self->name($name);
  $self->type($type);
  return $self;
}

sub name {
  my ($obj, $value) = @_;
  if( defined $value) {
      $obj->{'name'} = $value;
  }
  return $obj->{'name'};
}

sub type{
  my ($obj, $value) = @_;
  if( defined $value) {
      if (evidence_type_valid_all($value) or $value eq 'UNKNOWN') {
          $obj->{'type'} = $value;
      } else {
          my $valid = join(',', @Bio::Vega::Evidence::Types::ALL);
          $obj->throw("Invalid type [$value]. Must be one of $valid");
      }
  }
  return $obj->{'type'};
}


=head2 toString

 Title   : toString
 Usage   :
 Function:
 Example :
 Returns :
 Args    :


=cut

sub toString {
    my ($self) = @_;

    my $str = "";
    my $dbID   = "";
    my $infoid = "";

    if (defined($self->dbID)) {
        $dbID = $self->dbID;
    }
    if (defined($self->transcript_info_id)) {
        $infoid = $self->transcript_info_id;
    }
    $str = $str . "DbID                : " . $dbID . "\n";
    $str = $str . "Name                : " . $self->name . "\n";
    $str = $str . "Transcript info id  : " . $infoid . "\n";
    $str = $str . "Type                : " . $self->type . "\n";
    return $str;

}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

