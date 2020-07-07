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

package OtterTest::Loader;

use strict;
use warnings;

use parent 'Test::Class::Load';

sub is_test_class {
    my ( $class, $file, $dir ) = @_;

    # return unless it's a .pm (the default)
    return unless $class->SUPER::is_test_class( $file, $dir );

    # and only allow classes starting with 'Test/Bio'
    return $file =~ m{^${dir}/Test/Bio};
}

1;
