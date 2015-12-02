package Bio::Otter::Utils::Script::MouseStrains;

use strict;
use warnings;

use Moo;
use Types::Standard qw( Str ArrayRef HashRef );

use Const::Fast;

const my @raw => (
    {
     'old_code'     => '129',
     'new_code'     => 'XAR',
     'strain_name'  => '129S1/SvImJ',
     'grit_db_name' => 'kj2_mouse_129S1_SvImJ_R20150814',
    },
    {
     'old_code'     => 'AKR',
     'new_code'     => 'XAM',
     'strain_name'  => 'AKR/J',
     'grit_db_name' => 'kj2_mouse_AKR_J_R20150814',
    },
    {
     'old_code'     => 'AJ',
     'new_code'     => 'XAP',
     'strain_name'  => 'A/J',
     'grit_db_name' => 'kj2_mouse_A_J_R20150814',
    },
    {
     'old_code'     => 'BAL',
     'new_code'     => 'XAN',
     'strain_name'  => 'BALB/cJ',
     'grit_db_name' => 'kj2_mouse_BALB_cJ_R20150812',
    },
    {
     'old_code'     => 'C3H',
     'new_code'     => 'XAL',
     'strain_name'  => 'C3H/HeJ',
     'grit_db_name' => 'kj2_mouse_C3H_HeJ_R20150818',
    },
    {
     'old_code'     => 'C57',
     'new_code'     => 'XAF',
     'strain_name'  => 'C57BL/6NJ',
     'grit_db_name' => 'kj2_mouse_C57BL_6NJ_R20150818',
    },
    {
     'old_code'     => 'CBA',
     'new_code'     => 'XAK',
     'strain_name'  => 'CBA/J',
     'grit_db_name' => 'kj2_mouse_CBA_J_R20150818',
    },
    {
     'old_code'     => 'DBA',
     'new_code'     => 'XAJ',
     'strain_name'  => 'DBA/2J',
     'grit_db_name' => 'kj2_mouse_DBA_J_R20150819',
    },
    {
     'old_code'     => 'FVB',
     'new_code'     => 'XAH',
     'strain_name'  => 'FVB/NJ',
     'grit_db_name' => 'kj2_mouse_FVB_NJ_R20150819',
    },
    {
     'old_code'     => 'LPJ',
     'new_code'     => 'XAQ',
     'strain_name'  => 'LP/J',
     'grit_db_name' => 'kj2_mouse_LP_J_R20150819',
    },
    {
     'old_code'     => 'NOD',
     'new_code'     => 'XAG',
     'strain_name'  => 'NOD/ShiLtJ',
     'grit_db_name' => 'kj2_mouse_NOD_ShiLtJ_R20150819',
    },
    {
     'old_code'     => 'NZO',
     'new_code'     => 'XAE',
     'strain_name'  => 'NZO/HlLtJ',
     'grit_db_name' => 'kj2_mouse_NZO_HlLtJ_R20150819',
    },
    {
     'old_code'     => 'WSB',
     'new_code'     => 'XAD',
     'strain_name'  => 'WSB/EiJ',
     'grit_db_name' => 'kj2_mouse_WSB_EiJ_R20150819',
    },
    {
     'old_code'     => 'CAS',
     'new_code'     => 'XAC',
     'strain_name'  => 'CAST/EiJ',
     'grit_db_name' => 'kj2_mouse_CAST_EiJ_R20150909',
    },
    {
     'old_code'     => 'SPR',
     'new_code'     => 'XAA',
     'strain_name'  => 'SPRET/EiJ',
     'grit_db_name' => 'kj2_mouse_SPRET_EiJ_R20150909',
    },
    {
     'old_code'     => 'PWK',
     'new_code'     => 'XAB',
     'strain_name'  => 'PWK/PhJ',
     'grit_db_name' => 'kj2_mouse_PWK_PhJ_R20150826',
    },
    );

has old_codes => ( is => 'ro', isa => ArrayRef[Str], lazy => 1,
                   builder => sub { +[ map { $_->{old_code} } @raw ] }   );

has new_codes => ( is => 'ro', isa => ArrayRef[Str], lazy => 1,
                   builder => sub { +[ map { $_->{new_code} } @raw ] }   );

has old_code_map => ( is => 'ro', isa => HashRef[HashRef], lazy => 1,
                      builder => sub { +{ map { $_->{old_code} => $_ } @raw } }   );

has new_code_map => ( is => 'ro', isa => HashRef[HashRef], lazy => 1,
                      builder => sub { +{ map { $_->{new_code} => $_ } @raw } }   );

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

sub dataset_name_by_code {
    my ($self, $code) = @_;
    my $strain = $self->by_code($code)->{strain_name};
    $strain =~ s{/}{-}g;
    return "mouse-$strain";
}

sub old_dataset_name_by_code {
    my ($self, $code) = @_;
    my $oc = uc $self->by_code($code)->{old_code};
    return "mus_$oc";
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
