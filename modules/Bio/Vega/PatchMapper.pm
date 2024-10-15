=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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

package Bio::Vega::PatchMapper;

use strict;
use warnings;

use Carp;
use List::Util qw(min max);

use Bio::Vega::PatchMapper::Patch;

=head1 NAME

Bio::Vega::PatchMapper

=head1 DESCRIPTION

=cut

sub new {
    my ($class, $seq_region_slice) = @_;

    confess "Slice argument required" unless $seq_region_slice and $seq_region_slice->isa('Bio::EnsEMBL::Slice');

    my $self = bless { seq_region_slice => $seq_region_slice }, $class;
    return $self;
}

sub seq_region_slice {
    my ($self) = @_;
    return $self->{'seq_region_slice'};
}

sub patch_names {
    my ($self) = @_;

    my @patches = $self->patches;
    return map { $_->name } @patches;
}

sub patches {
    my ($self) = @_;

    # Filtered to overlapping start -> end

    my @patches = $self->_all_patches;
    my $start   = $self->seq_region_slice->start;
    my $end     = $self->seq_region_slice->end;

    return grep { $start <= $_->chr_end and $end >= $_->chr_start } @patches;
}

sub all_features {
    my ($self) = @_;
    my @patches = $self->patches;
    my @features;
    foreach my $patch ( @patches ) {
        my $fpc = $patch->feature_per_contig;
        push @features, values %$fpc;
    }
    return [ sort { $a->seq_region_start <=> $b->seq_region_start } @features ];
}

sub patches_by_contig {
    my ($self) = @_;
    my @patches = $self->patches;
    my $by_contig = {};
    foreach my $patch ( @patches ) {
        my $fpc = $patch->feature_per_contig;
        foreach my $contig ( keys %$fpc ) {
            my $contig_list = $by_contig->{$contig} ||= [];
            push @$contig_list, $patch;
        }
    }
    return $by_contig;
}

sub _all_patches {
    my ($self) = @_;
    my $_all_patches = $self->{'_all_patches'};
    return @$_all_patches if $_all_patches;

    $_all_patches = $self->_build_patches;
    $self->{'_all_patches'} = $_all_patches;
    return @$_all_patches;
}

sub _build_patches {
    my ($self) = @_;

    my $slice = $self->seq_region_slice;
    my $adaptor = $slice->adaptor;
    my $dbc = $adaptor->dbc;

    my $sth = $dbc->prepare(q{
      SELECT
          dest_sr.seq_region_id                  AS seq_region_id,
          dest_sr.name                           AS name,
          MIN(dest_asm.asm_start)                AS start,
          MAX(dest_asm.asm_end)                  AS end,
          COUNT(DISTINCT dest_cmp.seq_region_id) AS n_cmps         -- May not be required

      FROM seq_region   this_sr
      JOIN assembly     map_dest    ON (this_sr.seq_region_id    = map_dest.asm_seq_region_id)
      JOIN seq_region   dest_sr     ON (dest_sr.seq_region_id    = map_dest.cmp_seq_region_id)
      JOIN assembly     dest_asm    ON (dest_sr.seq_region_id    = dest_asm.asm_seq_region_id)
      JOIN seq_region   dest_cmp    ON (dest_cmp.seq_region_id   = dest_asm.cmp_seq_region_id)
      JOIN coord_system dest_cmp_cs ON (dest_cmp.coord_system_id = dest_cmp_cs.coord_system_id)

      WHERE
            this_sr.coord_system_id = dest_sr.coord_system_id
        AND dest_cmp_cs.name        = 'contig'
        AND this_sr.seq_region_id   = ?

      GROUP BY this_sr.seq_region_id, dest_sr.seq_region_id, dest_cmp.coord_system_id;
        });

    $sth->execute($adaptor->get_seq_region_id($slice));
    my $raw_patches = $sth->fetchall_arrayref({});

    my @patches;
    foreach my $raw_patch (@$raw_patches) {
        my $patch = Bio::Vega::PatchMapper::Patch->new( %$raw_patch, _mapper => $self );
        push @patches, $patch;
    }
    my $mapped_patches = $self->_map_patches(@patches);
    return $mapped_patches;
}

sub _map_patches {
    my ($self, @patches) = @_;

    my $e_slice = $self->_equiv_slice;
    return [] unless $e_slice;

    my @mapped_patches;
    foreach my $patch (@patches) {

        my $adaptor = $self->seq_region_slice->adaptor;
        my $p_slice = $adaptor->fetch_by_region('chromosome', @{$patch}{qw(name start end)});

        # Straightforward mappings will not work, as the EnsEMBL mapper will not map between
        # objects which are on the same coordinate system (chromosome:Otter).
        #
        # Fortunately, for patches, we have loaded a mapping from the patch back to GRCh37, which is
        # identical with Otter for human. We load that above as $e_slice.

        my $equiv_proj = $p_slice->project_to_slice($e_slice);
        $patch->n_map_segs(scalar(@$equiv_proj)); # may not need to store this

        unless (@$equiv_proj) {
            my $chr_name = $self->seq_region_slice->name;
            my $p_name   = $patch->name;
            warn "no projection found back to $chr_name for $p_name\n";
            next;
        }

        my ($p_min, $p_max);

        # It's probably not strictly essential to search for the ends of the projection, as although
        # it may be out of order (it's returned in source - patch - order), the flanking clones at start
        # and end of the patch map to start and end of the main chromosome. So we could do:
        #   $p_min = $equiv_proj->[0]->to_Slice->start;
        #   $p_max = $equiv_proj->[-1]->to_Slice->end;
        # and be done with it. However, to be safe:

        $p_min = $equiv_proj->[0]->to_Slice->start;
        $p_max = $equiv_proj->[0]->to_Slice->end;
        for my $i ( 1 .. $#{$equiv_proj} ) {
            $p_min = min( $p_min, $equiv_proj->[$i]->to_Slice->start );
            $p_max = max( $p_max, $equiv_proj->[$i]->to_Slice->end );
        }
        $patch->chr_start($p_min);
        $patch->chr_end(  $p_max);

        push @mapped_patches, $patch;
    }
    return \@mapped_patches;
}

sub _equiv_slice {
    my ($self) = @_;

    my $_equiv_slice = $self->{'_equiv_slice'};
    return $_equiv_slice if $_equiv_slice;

    my $sr_slice = $self->seq_region_slice;

    my $equiv_asm  = _get_slice_attribute($sr_slice, 'equiv_asm');
    my $equiv_name = _get_slice_attribute($sr_slice, 'ensembl_name');
    return unless ($equiv_asm and $equiv_name);

    $_equiv_slice = $sr_slice->adaptor->fetch_by_region('chromosome', $equiv_name, undef, undef, 1, $equiv_asm);
    unless ($_equiv_slice) {
        my $name = $sr_slice->name;
        warn "no equivalent slice found for '$name' using ['$equiv_name', '$equiv_asm']\n";
        return;
    }

    $self->{'_equiv_slice'} = $_equiv_slice;
    return $_equiv_slice;
}

# NOT a method
sub _get_slice_attribute {
    my ($slice, $key) = @_;
    my $name = $slice->name;

    my $attrs = $slice->get_all_Attributes($key);
    unless ($attrs and @$attrs) {
        warn "no '$key' attribute for '$name'\n";
        return;
    }
    return $attrs->[0]->value;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
