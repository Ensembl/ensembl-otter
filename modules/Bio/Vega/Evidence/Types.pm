package Bio::Vega::Evidence::Types;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(new_evidence_type_valid evidence_type_valid_all);

use Readonly;

# Order is important - used for presentation in CanvasWindow::EvidencePaster
#
Readonly our @VALID => qw( Protein ncRNA cDNA EST );
Readonly our @ALL   => ( @VALID, 'Genomic');

sub new {
    my ($this) = @_;
    my $class = ref($this) || $this;
    return bless {}, $class;
}

sub list_valid {
    return @VALID;
}

sub list_all {
    return @ALL;
}

sub valid_for_new_evi {
    my ($self, $type) = @_;
    return $self->_in_list($type, \@VALID);
}

sub valid_all {
    my ($self, $type) = @_;
    return $self->_in_list($type, \@ALL);
}

sub _in_list {
    my ($self, $term, $listref) = @_;
    foreach my $item (@$listref) {
        return 1 if $term eq $item;
    }
    return;
}

# Non-member-function wrappers

{
    my $evi_type;

    sub new_evidence_type_valid {
        my ($type) = @_;
        $evi_type ||= __PACKAGE__->new;
        return $evi_type->valid_for_new_evi($type);
    }

    sub evidence_type_valid_all {
        my ($type) = @_;
        $evi_type ||= __PACKAGE__->new;
        return $evi_type->valid_all($type);
    }
}

1;

__END__

=head1 NAME - Bio::Vega::Evidence::Types

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
