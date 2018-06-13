=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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

package Bio::Otter::Utils::Script::MouseStrains;

use strict;
use warnings;

use Moo;
use Types::Standard qw( Str ArrayRef HashRef InstanceOf );

use Const::Fast;

const my @raw => (
    {
     'old_code'     => '129',
     'strain_name'  => '129S1/SvImJ',
     'grit_db_name' => 'kj2_mouse_129S1_SvImJ_R20150814',
    },
    {
     'old_code'     => 'AKR',
     'strain_name'  => 'AKR/J',
     'grit_db_name' => 'kj2_mouse_AKR_J_R20150814',
    },
    {
     'old_code'     => 'AJ',
     'strain_name'  => 'A/J',
     'grit_db_name' => 'kj2_mouse_A_J_R20150814',
    },
    {
     'old_code'     => 'BAL',
     'strain_name'  => 'BALB/cJ',
     'grit_db_name' => 'kj2_mouse_BALB_cJ_R20150812',
    },
    {
     'old_code'     => 'C3H',
     'strain_name'  => 'C3H/HeJ',
     'grit_db_name' => 'kj2_mouse_C3H_HeJ_R20150818',
    },
    {
     'old_code'     => 'C57',
     'new_code'     => 'NJ',
     'strain_name'  => 'C57BL/6NJ',
     'grit_db_name' => 'kj2_mouse_C57BL_6NJ_R20150818',
    },
    {
     'old_code'     => 'CBA',
     'strain_name'  => 'CBA/J',
     'grit_db_name' => 'kj2_mouse_CBA_J_R20150818',
    },
    {
     'old_code'     => 'DBA',
     'strain_name'  => 'DBA/2J',
     'grit_db_name' => 'kj2_mouse_DBA_J_R20150819',
    },
    {
     'old_code'     => 'FVB',
     'strain_name'  => 'FVB/NJ',
     'grit_db_name' => 'kj2_mouse_FVB_NJ_R20150819',
    },
    {
     'old_code'     => 'LPJ',
     'strain_name'  => 'LP/J',
     'grit_db_name' => 'kj2_mouse_LP_J_R20150819',
     'db_name_suffix' => 'mus_r_apj',
    },
    {
     'old_code'     => 'NOD',
     'strain_name'  => 'NOD/ShiLtJ',
     'grit_db_name' => 'kj2_mouse_NOD_ShiLtJ_R20150819',
    },
    {
     'old_code'     => 'NZO',
     'strain_name'  => 'NZO/HlLtJ',
     'grit_db_name' => 'kj2_mouse_NZO_HlLtJ_R20150819',
    },
    {
     'old_code'     => 'WSB',
     'strain_name'  => 'WSB/EiJ',
     'grit_db_name' => 'kj2_mouse_WSB_EiJ_R20150819',
    },
    {
     'old_code'     => 'CAS',
     'strain_name'  => 'CAST/EiJ',
     'grit_db_name' => 'kj2_mouse_CAST_EiJ_R20150909',
    },
    {
     'old_code'     => 'SPR',
     'strain_name'  => 'SPRET/EiJ',
     'grit_db_name' => 'kj2_mouse_SPRET_EiJ_R20150909',
    },
    {
     'old_code'     => 'PWK',
     'strain_name'  => 'PWK/PhJ',
     'grit_db_name' => 'kj2_mouse_PWK_PhJ_R20150826',
    },
    );

my $type_strain = InstanceOf["Bio::Otter::Utils::Script::MouseStrain"];

has all => ( is      => 'ro',
             isa     => ArrayRef[$type_strain],
             lazy    => 1,
             builder => sub { [ map { Bio::Otter::Utils::Script::MouseStrain->new($_) } @raw ] }
    );

has old_codes => ( is => 'ro', isa => ArrayRef[Str], lazy => 1,
                   builder => sub { [ map { $_->old_code } @{ shift->all } ] }   );

has new_codes => ( is => 'ro', isa => ArrayRef[Str], lazy => 1,
                   builder => sub { [ map { $_->new_code } @{ shift->all } ] }   );

has old_code_map => ( is => 'ro', isa => HashRef[$type_strain], lazy => 1,
                      builder => sub { +{ map { $_->old_code => $_ } @{ shift->all } } }   );

has new_code_map => ( is => 'ro', isa => HashRef[$type_strain], lazy => 1,
                      builder => sub { +{ map { $_->new_code => $_ } @{ shift->all } } }   );

sub by_old_code {
    my ($self, $old_code) = @_;
    return $self->old_code_map->{$old_code};
}

sub by_new_code {
    my ($self, $new_code) = @_;
    return $self->new_code_map->{$new_code};
}

sub by_code {
    my ($self, $code) = @_;
    return $self->by_old_code($code) || $self->by_new_code($code);
}


package Bio::Otter::Utils::Script::MouseStrain; ## no critic(Modules::ProhibitMultiplePackages)

use strict;
use warnings;

use Moo;
use Types::Standard qw( Str );

has old_code     => ( is => 'ro', isa => Str );
has new_code     => ( is => 'ro', isa => Str, lazy => 1, builder => sub { shift->old_code } );
has strain_name  => ( is => 'ro', isa => Str );
has grit_db_name => ( is => 'ro', isa => Str );

has db_name_suffix => ( is => 'lazy', isa => Str );

sub _build_db_name_suffix {    ## no critic(Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $oc = lc $self->old_code;
    return sprintf('mus_r_%s', $oc);
}

sub db_name {
    my ($self, $prefix) = @_;
    $prefix //= 'loutre';
    return sprintf('%s_%s', $prefix, $self->db_name_suffix);
}

sub dataset_name {
    my ($self) = @_;
    my $strain = $self->strain_name;
    $strain =~ s{/}{-}g;
    return "mouse-$strain";
}

sub old_dataset_name {
    my ($self) = @_;
    my $oc = uc $self->old_code;
    return "mus_$oc";
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
