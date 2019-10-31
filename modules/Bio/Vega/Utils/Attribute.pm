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

package Bio::Vega::Utils::Attribute;

use strict;
use warnings;

use Carp;

our @EXPORT_OK;
use parent qw( Exporter );
BEGIN {
    @EXPORT_OK = qw(
        add_EnsEMBL_Attributes
        make_EnsEMBL_Attribute
        get_first_Attribute_value
        get_name_Attribute_value
        add_selenocystein_Attr_from_Remark
    );
}

use Bio::EnsEMBL::Attribute;
use Bio::EnsEMBL::Utils::Exception qw( throw );
=head1 NAME

Bio::Vega::Utils::Attribute

=head1 DESCRIPTION

Provides shared functions (NOT methods) for creating
Bio::EnsEMBL::Attribute objects and for adding them to
other EnsEMBL or Vega objects.

=head2 FUNCTIONS

=over 4

=item add_EnsEMBL_Attributes($e_obj, @keypairs)

Create attributes from @keypairs and add them to EnsEMBL object
$e_obj, which must provide the add_Attributes method.

@keypairs should be an array of <code>, <value> pairs. It is not a
hash, to allow repeated attribute codes:

  add_EnsEMBL_Attributes($transcript,
                        'remark' => 'remark one',
                        'remark' => 'remark two' );

=cut

sub add_EnsEMBL_Attributes {
    my ($e_obj, @keypairs) = @_;

    unless ((@keypairs % 2) == 0) {
        throw("Odd number of keypairs; expecting <code> => <value>, <code> => <value>, ...");
    }

    my @attributes;
    while (my ($code, $value) = splice(@keypairs, 0, 2)) {
        push @attributes, make_EnsEMBL_Attribute($code, $value);
    }
    return $e_obj->add_Attributes(@attributes);
}

=item add_selenocystein_Attr_from_Remark($e_obj, @remarks)

Search C<@remarks>. for selenocystin pattern and adds a L<Bio::EnsEMBL::Attribute>
at the given C<$e_obj>
=cut

sub add_selenocystein_Attr_from_Remark {
  my ($e_obj, @remarks) = @_;
  my @translation_attributes;
   foreach my $value (@remarks) {
     if ($value =~ /^selenocystein\w+\s+\d+/) {
       while($value =~ / (\d+)/gc) {
        add_EnsEMBL_Attributes($e_obj, '_selenocysteine' => $1);

      }
    }

  }

}

=item make_EnsEMBL_Attribute($code, $value)

Create a L<Bio::EnsEMBL::Attribute> with the given C<$code> and C<$value>.
=cut

sub make_EnsEMBL_Attribute {
    my ($code, $value) = @_;
    return
        Bio::EnsEMBL::Attribute->new(
            -CODE   => $code,
            -VALUE  => $value,
        );
}

=item get_first_Attribute_value($feature, $code, [confess_if_multiple => 1])

Return the value of the feature's first Attribute with the given C<$code>, or C<undef> if no such Attribute exists.

When C<confess_if_multiple> is set, C<get_first_Attribute_value> will die with stack trace if there are more
than one Attributes with the given C<$code>.
=cut

sub get_first_Attribute_value {
    my ($feature, $code, %options) = @_;

    my $attrs = $feature->get_all_Attributes($code);

    if ($options{confess_if_multiple} and @$attrs > 1) {
        confess sprintf("Got %d '%s' Attributes on %s", scalar(@$attrs), $code, ref($feature));
    }

    my $value = $attrs->[0] ? $attrs->[0]->value : undef;
    return $value;
}

=item get_name_Attribute_value($feature, [confess_if_multiple => 1])

Return the value of the feature's first 'name' Attribute, or C<undef> if no such Attribute exists.

When C<confess_if_multiple> is set, C<get_name_Attribute_value> will die with stack trace if there are more
than one 'name' Attributes.
=cut

sub get_name_Attribute_value {
    my ($feature, @options) = @_;
    return get_first_Attribute_value($feature, 'name', @options);
}

1;

__END__

=back

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
