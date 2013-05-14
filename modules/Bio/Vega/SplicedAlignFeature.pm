
### Bio::Vega::SplicedAlignFeature

package Bio::Vega::SplicedAlignFeature;

use strict;
use warnings;

use feature 'switch';

use Log::Log4perl;

use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::Intron;

use Bio::EnsEMBL::Utils::Argument qw(rearrange);
use Bio::EnsEMBL::Utils::Exception qw(throw);

use Bio::Otter::GappedAlignment;
use Bio::Otter::Utils::Vulgar;

use base 'Bio::EnsEMBL::BaseAlignFeature';

sub new {
    my ($caller, @args) = @_;
    my $class = ref($caller) || $caller;

    my $self;

    my ($cigar_string, $vulgar_comps_string, $vulgar_string, $features) = rearrange(
     [qw(CIGAR_STRING   VULGAR_COMPS_STRING   VULGAR_STRING   FEATURES)], @args
        );

    my $count_args = 0;
    map { $count_args++ if $_ } ( $cigar_string, $vulgar_comps_string, $vulgar_string, $features );

    for ($count_args) {

        when ($_ < 1) {
            throw("One of CIGAR_STRING, VULGAR_COMPS_STRING, VULGAR_STRING or FEATURES argument is required");
        }

        when ($_ > 1) {
            throw("Only one of CIGAR_STRING, VULGAR_COMPS_STRING, VULGAR_STRING and FEATURES arguments is permitted.");
        }

        when ($_ == 1) {

            if ($features) {
                $self = $class->my_SUPER_new(@args);
                $self->_parse_features($features);
            }

            if ($cigar_string) {
                $self = $class->my_SUPER_new(@args);
                $self->cigar_string($cigar_string);
                delete $self->{cigar_string};
            }

            my %from_vulgar;
            if ($vulgar_string) {
                my $vulgar = Bio::Otter::Utils::Vulgar->new($vulgar_string);
                $vulgar_comps_string = $vulgar->align_comps_string;
                my ($t_start, $t_end, $t_strand) = $vulgar->target_ensembl_coords;
                my ($q_start, $q_end, $q_strand) = $vulgar->query_ensembl_coords;
                %from_vulgar = (
                    -seqname => $vulgar->target_id,
                    -start   => $t_start,
                    -end     => $t_end,
                    -strand  => $t_strand,
                    -hseqname => $vulgar->query_id,
                    -hstart   => $q_start,
                    -hend     => $q_end,
                    -hstrand  => $q_strand,
                    -score    => $vulgar->score,
                    );
                # drop through to process $vulgar_comps_string...
            }

            if ($vulgar_comps_string) {
                $self = $class->my_SUPER_new(@args, %from_vulgar, -cigar_string => 'M'); # dummy match, replaced by:
                $self->vulgar_comps_string($vulgar_comps_string);
                delete $self->{cigar_string};
            }

        }
    }

    return $self;
}

# Currently an alias for alignment_string
#
sub vulgar_comps_string {
    my ($self, @args) = @_;
    return $self->alignment_string(@args);
}

# Currently fixed as 'vulgar_exonerate_components'
#
sub alignment_type {
    return 'vulgar_exonerate_components';
}

sub alignment_string {
    my ($self, @args) = @_;
    ($self->{'alignment_string'}) = @args if @args;
    my $alignment_string = $self->{'alignment_string'};
    return $alignment_string;
}

# Currently read-only - any need for it to be read-write?
#
sub vulgar_string {
    my ($self) = @_;
    $self->_verify_attribs;
    my $gapped_alignment = $self->gapped_alignment;
    return $gapped_alignment->vulgar_string;
}

# Used by adaptors
#
sub check_fetch_alignment {
    my ($self) = @_;

    my $alignment_type = $self->alignment_type();
    unless ($alignment_type ) {
        throw( "SplicedAlignFeature does not define an alignment_type." );
    }
    if ( $alignment_type ne 'vulgar_exonerate_components' ) {
        throw( "alignment_type '$alignment_type' not supported." );
    }

    # This'll need to be pluggable if we support more than one alignment_type
    my $alignment_string = $self->alignment_string();
    unless ($alignment_string) {
        throw( "SplicedAlignFeature does not define an alignment_string." );
    }

    return ($alignment_type, $alignment_string);
}

sub cigar_string {
    my ($self, @args) = @_;
    my $cigar_string;
    if (@args) {
        ($cigar_string) = @args;
        my $vulgar_comps_string = $self->_cigar_to_vulgar_comps($cigar_string);
        $self->vulgar_comps_string($vulgar_comps_string);
    } else {
        $cigar_string = $self->_vulgar_comps_to_cigar;
    }
    return $cigar_string;
}

sub _parse_features {
    my ($self, $features) = @_;
    # FIXME: need to do more than this
    $self->SUPER::_parse_features($features);
    $self->cigar_string($self->{cigar_string});
    delete $self->{cigar_string};
    return $self;
}

sub _cigar_to_vulgar_comps {
    my ($self, $cigar_string) = @_;

    # We could go via a GappedAlignment but that'd be slower, so:
    # Copied from Bio::EnsEMBL::BaseAlignFeature::_parse_cigar()

    my $query_unit = $self->_query_unit();
    my $hit_unit = $self->_hit_unit();

    my @vulgar_comps;

    my @pieces = ( $cigar_string =~ /(\d*[MDI])/g );
    foreach my $piece (@pieces) {

        my ($length) = ( $piece =~ /^(\d*)/ );
        if ($length eq "") { $length = 1 }
        my $mapped_length;

        # explicit if statements to avoid rounding problems
        # and make sure we have sane coordinate systems
        if ($query_unit == 1 && $hit_unit == 3) {
            $mapped_length = $length*3;
        } elsif ($query_unit == 3 && $hit_unit == 1) {
            $mapped_length = $length / 3;
        } elsif ($query_unit == 1 && $hit_unit == 1) {
            $mapped_length = $length;
        } else {
            throw("Internal error $query_unit $hit_unit, currently only " .
                  "allowing 1 or 3 ");
        }

        if (int($mapped_length) != $mapped_length and
            ($piece =~ /M$/ or $piece =~ /D$/)) {
            throw("Internal error with mismapped length of hit, query " .
                  "$query_unit, hit $hit_unit, length $length");
        }

        if (     $piece =~ /M$/) { # MATCH
            push @vulgar_comps, "M ${mapped_length} ${length}";
        } elsif ($piece =~ /I$/) { # INSERTION
            push @vulgar_comps, "G 0 ${length}";
        } elsif ($piece =~ /D$/) { # DELETION
            push @vulgar_comps, "G ${mapped_length} 0";
        } else {
            throw( "Illegal cigar line: '$cigar_string'" );
        }
    }

    return join(' ', @vulgar_comps);
}

sub _vulgar_comps_to_cigar {
    my ($self) = @_;

    my $gapped_alignment = $self->gapped_alignment;

    $self->logger->logcarp('Intron info will be lost in cigar string') if $gapped_alignment->has_introns;
    return $gapped_alignment->ensembl_cigar_string;
}

sub as_AlignFeature {
    my ($self) = @_;

    my $class = $self->_align_feature_class; # inheritance work-around again.
    my @extra_attribs = $self->_extra_fields;

    my @common_attribs = qw(
        slice
        start  end  strand  seqname  species
        hstart hend hstrand hseqname hspecies hcoverage
        percent_id score p_value
        analysis external_db_id extra_data
        cigar_string
      );

    my %args = map { '-' . $_ => $self->$_() } @common_attribs, @extra_attribs;
    my $align_feature = $class->new(%args);

    return $align_feature;
}

sub gapped_alignment {
    my ($self) = @_;

    # We could cache here, if we need to, but would have to invalidate assiduously.

    my $vulgar_comps = $self->vulgar_comps_string;
    my $gapped_alignment = Bio::Otter::GappedAlignment->from_vulgar_comps_string($vulgar_comps);

    my $start  = $self->start;
    my $end    = $self->end;
    my $strand = $self->strand // 1;
    $gapped_alignment->set_target_from_ensembl($start, $end, $strand);

    my $hstart  = $self->hstart;
    my $hend    = $self->hend;
    my $hstrand = $self->_hstrand_or_protein;
    $gapped_alignment->set_query_from_ensembl($hstart, $hend, $hstrand);

    $gapped_alignment->target_id($self->seqname);
    $gapped_alignment->query_id($self->hseqname);

    return $gapped_alignment;
}

sub _verify_attribs {
    my ($self) = @_;

    $self->start  // $self->logger->logcroak('start not set');
    $self->end    // $self->logger->logcroak('end not set');

    $self->hstart  // $self->logger->logcroak('hstart not set');
    $self->hend    // $self->logger->logcroak('hend not set');

    return;
}

sub get_all_exon_alignments {
    my ($self) = @_;

    $self->_verify_attribs;
    my $gapped_alignment = $self->gapped_alignment;
    my @egas = $gapped_alignment->exon_gapped_alignments;

    return map { $self->new( -vulgar_string => $_->vulgar_string, -slice => $self->slice ) } @egas;
}

sub get_all_exons {
    my ($self) = @_;
    my @exon_alignments = $self->get_all_exon_alignments;
    return map { $_->as_exon } @exon_alignments;
}

sub get_all_introns {
    my ($self) = @_;
    my @exons = $self->get_all_exons;

    my $n_exons = scalar(@exons);
    return if $n_exons < 2;

    my @introns;
    for my $i ( 0 .. ($n_exons - 2) ) {
        my $intron = Bio::EnsEMBL::Intron->new($exons[$i], $exons[$i+1]);
        push @introns, $intron;
    }

    return @introns;
}

sub as_exon {
    my ($self) = @_;
    my %args = map { '-' . $_ => $self->$_() } qw( slice start end strand seqname phase end_phase dbID );
    my $exon = Bio::EnsEMBL::Exon->new(%args);
    return $exon;
}

sub ungapped_features {
    my ($self) = @_;
    my @exon_alignments = $self->get_all_exon_alignments;
    my @ungapped_features = map { $_->as_AlignFeature->ungapped_features } @exon_alignments;
    return @ungapped_features;
}

# These two increase the pressure on caching gapped_alignment
#
sub phase {
    my ($self) = @_;
    my $gapped_alignment = $self->gapped_alignment;
    return $gapped_alignment->phase;
}

sub end_phase {
    my ($self) = @_;
    my $gapped_alignment = $self->gapped_alignment;
    return $gapped_alignment->end_phase;
}

sub logger {
    return Log::Log4perl->get_logger;
}

1;

__END__

=head1 NAME - Bio::Vega::SplicedAlignFeature

=head1 DESCRIPTION

Base class for Bio::Vega::SplicedAlignFeature::DNA and
Bio::Vega::SplicedAlignFeature::Protein.

Extends Bio::EnsEMBL::BaseAlignFeature.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

