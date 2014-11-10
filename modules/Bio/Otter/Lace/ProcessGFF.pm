
### Bio::Otter::Lace::ProcessGFF

package Bio::Otter::Lace::ProcessGFF;

use strict;
use warnings;
use Carp;

use Bio::Otter::Utils::AccessionInfo::Serialise qw(fasta_header_column_order unescape_fasta_description);
use Bio::Otter::Utils::TimeDiff qw( time_diff_for );

use Hum::Ace::SubSeq;
use Hum::Ace::Method;
use Hum::Ace::Locus;

use Try::Tiny;

use parent qw( Bio::Otter::Log::WithContextMixin );

{
    ### Should add this to otter_config
    ### or parse it from the ZMap styles
    my %evidence_type = (
        vertebrate_mRNA  => 'cDNA',
        vertebrate_ncRNA => 'ncRNA',
        BLASTX           => 'Protein',
        SwissProt        => 'Protein',
        TrEMBL           => 'Protein',
        OTF_ncRNA        => 'ncRNA',
        OTF_EST          => 'EST',
        OTF_mRNA         => 'cDNA',
        OTF_Protein      => 'Protein',
        SwissProt_old    => 'Protein', # tmp RT#370164 RT#359109
        TrEMBL_old       => 'Protein',
    );

    # Some GFFs have other fields (feat_type=protein_match,
    # DB_Name=TrEMBL, Class=Protein) which should be indicative.
    sub __source2type {
        my ($source) = @_;
        return 'EST' if substr($source, 0, 4) eq 'EST_';
        return $evidence_type{$source};
    }
}

sub new {
    my ($pkg, %args) = @_;

    my ($gff_path, $log_context, $column_name) = @args{qw( gff_path log_context column_name )};
    my $self = bless {}, $pkg;
    $self->log_context($log_context);
    $self->column_name($column_name);

    unless ($gff_path) {
        $self->logger->logconfess("Cannot create ProcessGFF without gff_path parameter");
    }
    $self->gff_path($gff_path);

    return $self;
}

sub gff_fh {
    my ($self) = @_;
    return $self->{'gff_fh'} if $self->{'gff_fh'};

    my $gff_path = $self->gff_path;
    $self->logger->debug("Opening '$gff_path'");
    open my $gff_fh, '<', $gff_path or $self->logger->logconfess("Can't read GFF file '$gff_path'; $!");

    return $self->{'gff_fh'} = $gff_fh;
}

sub close {
    my ($self) = @_;
    my $gff_fh   = $self->gff_fh;
    my $gff_path = $self->gff_path;

    $self->logger->debug("Closing '$gff_path'");
    my $ok = close $gff_fh;
    delete $self->{'gff_fh'};
    return $ok if $ok;

    $self->logger->error("Error closing GFF file '$gff_path'; $!");
    return;
}

sub store_hit_data_from_gff {
    my ($self, @args) = @_;
    return time_diff_for(
        sub { return $self->_store_hit_data_from_gff(@args); },
        sub { return $self->_time_diff_log(@_);              },
        sprintf('store_hit_data_from_gff [%s]', $self->column_name),
        );
}

sub _store_hit_data_from_gff {
    my ($self, $accession_type_cache) = @_;

    $accession_type_cache->begin_work;

    my %fail;
    my $gff_fh = $self->gff_fh;
    while (<$gff_fh>) {
        last if /^\s*##\bFASTA\b/;
        next if /^\s*#/;
        my ($seq_name, $source, $feat_type, $start, $end, $score, $strand, $frame, $attrib)
            = parse_gff_line($_);
        next unless $attrib->{'Name'};
        my $evi_type = __source2type($source);
        if (!$evi_type) {
            $fail{$source} ||= "Cannot convert source=$source to an evidence type:$.:$_";
            next;
        }
        $accession_type_cache->save_accession_info( {
            acc_sv          => $attrib->{'Name'},
            taxon_id        => $attrib->{'taxon_id'},
            evi_type        => $evi_type,
            description     => $attrib->{'description'},
            source          => $attrib->{'db_name'},
            sequence_length => $attrib->{'length'},
            } );
    }

    foreach my $prob (sort values %fail) {
        $self->logger->warn($prob); # warn because it is only a cache save fail
    }

    # Now we are at the start of the FASTA data (or EOF if there is
    # none).

    my ($header, $sequence, $taxon_id_hash);
    $taxon_id_hash = { };
    my $save_sub = sub {
        if (defined $header) {
            my @value_list = split /\|/, $header;
            my %acc_info;
            @acc_info{fasta_header_column_order()} = @value_list;
            $acc_info{description} = unescape_fasta_description($acc_info{description});
            $acc_info{sequence} = $sequence;
            $accession_type_cache->save_accession_info(\%acc_info);
            my $taxon_id = $acc_info{taxon_id};
            $taxon_id_hash->{$taxon_id}++;
        }
    };

    $sequence = '';
    while (<$gff_fh>) {
        chomp;
        if (/^>/) { # FASTA header
            $save_sub->();
            ($header) = /^>(.*)$/;
            $sequence = '';
        }
        else { # sequence
            $sequence .= $_;
        }
    }
    $save_sub->();

    $accession_type_cache->commit;
    $accession_type_cache->populate_taxonomy([keys %{$taxon_id_hash}]);

    return;
}


sub make_ace_transcripts_from_gff {
    my ($self, @args) = @_;
    return time_diff_for(
        sub { return ( $self->_make_ace_transcripts_from_gff(@args) ); },
        sub { return $self->_time_diff_log(@_);                        },
        sprintf('make_ace_transcripts_from_gff [%s]', $self->column_name),
        );
}

sub _make_ace_transcripts_from_gff {
    my ($self, $start, $end) = @_;

    my %tsct;
    $self->make_ace_transcripts_from_gff_fh($start, $end, \%tsct);

    my (@ok_tsct);
    while (my ($name, $sub) = each %tsct) {
        try {
            $sub->validate; # raises an error if invalid
            push(@ok_tsct, $sub);
        }
        catch {
            # special case for a common error - trim off stack trace - RT#273390
            s{^(Translation coord '\d+' does not lie within any Exon\n) at .*}{$1}s;
            $self->logger->warn("Skipped SubSeq '$name'.  Error:\n$_");
        };
    }
    return @ok_tsct;
}

sub make_ace_transcripts_from_gff_fh {
    my ($self, $seq_region_start, $seq_region_end, $tsct) = @_;

    my $seq_region_offset = $seq_region_start - 1;
    my $seq_region_length = $seq_region_end - $seq_region_offset;

    my (%locus_by_name, $gene_method, $coding_gene_method);

    my $gff_fh = $self->gff_fh;
    while (<$gff_fh>) {
        last if /^\s*##\bFASTA\b/;
        next if /^\s*#/;

        my ($seq_name, $source, $feat_type, $start, $end, $score, $strand, $frame, $attrib)
            = parse_gff_line($_);
        $start -= $seq_region_offset;
        $end   -= $seq_region_offset;
        my $name = $attrib->{'Name'};
        next unless $name;
        my ($sub);
        unless ($sub = $tsct->{$name}) {
            $sub = Hum::Ace::SubSeq->new;
            unless ($gene_method) {
                $gene_method = Hum::Ace::Method->new;
                $gene_method->name($source);
                $coding_gene_method = Hum::Ace::Method->new;
                $coding_gene_method->name($source);
                $coding_gene_method->coding(1);
            }
            $sub->name($name);
            $sub->GeneMethod($gene_method);
            $tsct->{$name} = $sub;
        }

        if ($feat_type eq 'transcript') {
            $sub->strand($strand eq '-' ? -1 : 1);
            if (my $stable = $attrib->{'stable_id'}) {
                $sub->otter_id($stable);
            }
            if (my $loc_name = $attrib->{'locus'}) {
                my $locus = $locus_by_name{$loc_name};
                unless ($locus) {
                    $locus = $locus_by_name{$loc_name}
                        = Hum::Ace::Locus->new;
                    $locus->name($loc_name);
                    if (my $stable = $attrib->{'locus_stable_id'}) {
                        $locus->otter_id($stable);
                    }
                }
                $sub->Locus($locus);
            }
            if ($start < 1 || $end > $seq_region_length) {
                # any part of the transcript protrudes beyond our region.  RT#403236
                $sub->truncated_from([ $start, $end ]);
            }
        }
        ### HACK: Should truncate to Slice on server
        # (but whatever it does, the start/end we send to ZMap via
        # Zircon must match the start/end in the GFF we feed it)
        elsif ($feat_type eq 'exon') {
            # Truncate exons to slice
            next if $end < 1;
            next if $start > $seq_region_length;
            $start = 1 if $start < 1;
            $end = $seq_region_length if $end > $seq_region_length;

            my $exon = $sub->new_Exon;
            $exon->start($start);
            $exon->end($end);
            if (my $stable = $attrib->{'stable_id'}) {
                $exon->otter_id($stable);
            }
        }
        elsif ($feat_type eq 'CDS') {            
            # Don't attempt truncated CDS
            next if $start < 1;
            next if $end > $seq_region_length;

            $sub->translation_region($start, $end);
            $sub->GeneMethod($coding_gene_method);
            if (my $stable = $attrib->{'stable_id'}) {
                $sub->translation_otter_id($stable);
            }
        }
    }

    return;
}

# Not a method
sub parse_gff_line {
    my ($line) = @_;

    chomp($line);
    my ($seq_name, $source, $feat_type, $start, $end, $score, $strand, $frame, $group)
        = split(/\t/, $line, 9);
    my $attrib =
        defined $group
        ? ( +{ map { _parse_tag_value() } split(/;/, $group) } )
        : { };
    return ($seq_name, $source, $feat_type, $start, $end, $score, $strand, $frame, $attrib);
}

# Not a method
sub _parse_tag_value {
    return map { _gff3_unescape() } split(/=/, $_, 2);
}

# Not a method
sub _gff3_unescape {
    s/%([[:xdigit:]]{2})/chr(hex($1))/eg;
    return $_;
}

# $gff->{seqname}, $gff->{source}, $gff->{feature}, $gff->{start},
# $gff->{end},     $gff->{score},  $gff->{strand},  $gff->{frame},


sub gff_path {
    my ($self, @args) = @_;
    ($self->{'gff_path'}) = @args if @args;
    my $gff_path = $self->{'gff_path'};
    return $gff_path;
}

sub column_name {
    my ($self, @args) = @_;
    ($self->{'column_name'}) = @args if @args;
    my $column_name = $self->{'column_name'};
    return $column_name || 'NOT-SET';
}

# Required by Bio::Otter::Log::WithContextMixin
sub default_log_context {
    return '-B-O-L-ProcessGFF unnamed-';
}

sub _time_diff_log {
    my ($self, $event, $data, $cb_data) = @_;
    if ($event eq 'elapsed') {
        $self->logger->debug("${cb_data}: ${event}: $data");
    } else {
        $self->logger->debug("${cb_data}: ${event}");
    }
    return;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::ProcessGFF

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

