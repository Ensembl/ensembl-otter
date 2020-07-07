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

#
# Utility package with some functions that can be used to categorise lengths
#

package Length;

use StatMsg;
use Bio::EnsEMBL::Utils::Exception qw(throw);

use constant MEDIUM => 9;  # 8 or less is short
use constant LONG   => 49; # 9-48 is medium, >48 is long

#
# returns true if a given length is considered to be SHORT
#

sub is_short {
  my $length = shift;
  return $length < MEDIUM;
}

#
# returns true if a given length is considered to be MEDIUM
#
sub is_medium {
  my $length = shift;
  return ($length >= MEDIUM) && ($length < LONG);
}

#
# returns true if a given length is considered to be LONG
#
sub is_long {
  my $length = shift;
  return ($length >= LONG);
}

#
# converts a length to its status code SHORT, MEDIUM or LONG
#
sub length2code {
  my $length = shift;
  return StatMsg::SHORT  if(is_short($length));
  return StatMsg::MEDIUM if(is_medium($length));
  return StatMsg::LONG   if(is_long($length));

  throw("Could not resolve length code for length=$length");
}


1;
