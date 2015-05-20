package Bio::Vega::Utils::Attribute;

use strict;
use warnings;

our @EXPORT_OK;
use parent qw( Exporter );
BEGIN { @EXPORT_OK = qw( add_EnsEMBL_Attributes make_EnsEMBL_Attribute ); }

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

1;

__END__

=back

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
