package Bio::Otter::Lace::Slice;

use strict;
use warnings;

use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::CoordSystem;

sub new {
    my ($pkg, 
        $Client, # object
        $dsname, # e.g. 'human'
        $ssname, # e.g. 'chr20-03'

        $csname, # e.g. 'chromosome'
        $csver,  # e.g. 'Otter'
        $seqname,# e.g. '20'
        $start,  # in the given coordinate system
        $end,    # in the given coordinate system
    ) = @_;

    # chromosome:Otter:chr6-17:2666323:2834369:1


    my $self = {
        '_Client'   => $Client,
        '_dsname'   => $dsname,
        '_ssname'   => $ssname,

        '_csname'   => $csname,
        '_csver'    => $csver,
        '_seqname'  => $seqname,
        '_start'    => $start,
        '_end'      => $end,
    };

    return bless $self, $pkg;
}

sub new_from_region {
    my ($pkg, $client, $region) = @_;

    my $chr_slice = $region->slice;
    return Bio::Otter::Lace::Slice->new(
        $client,
        $region->species,
        $chr_slice->seq_region_name,
        $chr_slice->coord_system->name,
        $chr_slice->coord_system->version,
        $region->chromosome_name,
        $chr_slice->start,
        $chr_slice->end,
        );
}

sub clone_near { # new from old, different coords
    my ($old, $start, $end) = @_;
    my $new =
      { %$old,
        _start => $start,
        _end => $end,
      };
    return bless $new, ref($old);
}


sub Client {
    my ($self, $Client) = @_;
    
    if ($Client) {
        $self->{'_Client'} = $Client;
    }
    return $self->{'_Client'};
}

sub dsname {
    my ($self, $dsname) = @_;
    
    if ($dsname) {
        $self->{'_dsname'} = $dsname;
    }
    return $self->{'_dsname'};
}

sub ssname {
    my ($self, $ssname) = @_;
    
    if ($ssname) {
        $self->{'_ssname'} = $ssname;
    }
    return $self->{'_ssname'};
}

sub csname {
    my ($self, $csname) = @_;
    
    if ($csname) {
        $self->{'_csname'} = $csname;
    }
    return $self->{'_csname'} || 'chromosome';
}

sub csver {
    my ($self, $csver) = @_;
    
    if ($csver) {
        $self->{'_csver'} = $csver;
    }
    return $self->{'_csver'} || __PACKAGE__.' '.__LINE__;
}

sub seqname {
    my ($self, $seqname) = @_;
    
    if ($seqname) {
        $self->{'_seqname'} = $seqname;
    }
    return $self->{'_seqname'};
}

sub start {
    my ($self, $start) = @_;
    
    if (defined $start) {
        $self->{'_start'} = $start;
    }
    return $self->{'_start'};
}

sub end {
    my ($self, $end) = @_;
    
    if (defined $end) {
        $self->{'_end'} = $end;
    }
    return $self->{'_end'};
}

sub length {
    my ($self) = @_;

    return $self->end() - $self->start() + 1;
}

sub name {
    my ($self) = @_;

    return sprintf "%s_%d-%d",
        $self->ssname,
        $self->start,
        $self->end;
}

sub zmap_config_stanza {
    my ($self) = @_;

    my $hash = {
        'dataset'  => $self->dsname,
        'sequence' => $self->ssname,
        'csname'   => $self->csname,
        'csver'    => $self->csver,
        'chr'      => $self->ssname,
        'start'    => $self->start,
        'end'      => $self->end,
    };

    return $hash;
}

sub ensembl_slice {
    my ($self) = @_;

    my $ensembl_slice = Bio::EnsEMBL::Slice->new(
        -seq_region_name    => $self->ssname,
        -start              => $self->start,
        -end                => $self->end,
        # FIXME - this should be from a factory
        -coord_system   => Bio::EnsEMBL::CoordSystem->new(
            -name           => $self->csname,
            -version        => $self->csver,
            -rank           => 2,
            -sequence_level => 0,
            -default        => 1,
        ),
    );

    return $ensembl_slice;
}

1;

__END__


=head1 NAME - Bio::Otter::Lace::Slice

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

