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


### Bio::Otter::Lace::ProcessGFF

package Bio::Otter::Lace::ProcessGFF;

use strict;
use warnings;
use Carp;
use Readonly;

use Bio::Otter::Utils::AccessionInfo::Serialise qw(fasta_header_column_order unescape_fasta_description);
use Bio::Otter::Utils::TimeDiff qw( time_diff_for );

use Hum::Ace::SubSeq;
use Hum::Ace::Method;
use Hum::Ace::Locus;

use Try::Tiny;

use parent qw( Bio::Otter::Log::WithContextMixin );

Readonly my $BATCH_SIZE => 500;

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

    # $accession_type_cache->begin_work;

    my %batch;
    my $count = 0;
    my %fail;
    my $gff_fh = $self->gff_fh;
    while (<$gff_fh>) {
        last if /^\s*##\bFASTA\b/;
        next if /^\s*#/;
        my ($seq_name, $source, $feat_type, $start, $end, $score, $strand, $frame, $attrib)
            = parse_gff_line($_);
        next unless $attrib->{'Name'};
        $batch{$attrib->{'Name'}} = {
            acc_sv          => $attrib->{'Name'},
            taxon_id        => $attrib->{'taxon_id'},
            description     => $attrib->{'description'},
            source          => $attrib->{'db_name'},
            sequence_length => $attrib->{'length'},
        };
        if (++$count >= $BATCH_SIZE) {
            _save_accession_info($accession_type_cache, \%batch, 'gff features');
            %batch = ();
            $count = 0;
        }
    }
    _save_accession_info($accession_type_cache, \%batch, 'gff features');

    foreach my $prob (sort values %fail) {
        $self->logger->warn($prob); # warn because it is only a cache save fail
    }

    # Now we are at the start of the FASTA data (or EOF if there is
    # none).

    my ($header, $sequence, $taxon_id_hash);
    %batch = ();
    $count = 0;
    $taxon_id_hash = { };
    my $save_sub = sub {
        if (defined $header) {
            my @value_list = split /\|/, $header;
            my %acc_info;
            @acc_info{fasta_header_column_order()} = @value_list;
            $acc_info{description} = unescape_fasta_description($acc_info{description});
            $acc_info{sequence} = $sequence;
            $batch{$acc_info{acc_sv}} = \%acc_info;
            if (++$count >= $BATCH_SIZE) {
                _save_accession_info($accession_type_cache, \%batch, 'gff fasta');
                %batch = ();
                $count = 0;
            }
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
    _save_accession_info($accession_type_cache, \%batch, 'gff fasta');

    # $accession_type_cache->commit;
    $accession_type_cache->populate_taxonomy([keys %{$taxon_id_hash}]);

    return;
}

sub _save_accession_info {
    my ($accession_type_cache, $entries, $debug_context) = @_;

    my $saved;
    $accession_type_cache->begin_work;
    try {
        foreach my $entry (values %$entries) {
            $accession_type_cache->save_accession_info($entry);
        }
        $saved = 1;
        $accession_type_cache->commit;
    }
    catch {
        my $error = $_;
        $accession_type_cache->rollback;
        my $where = $saved ? "commiting accession_info" : "in save_accession_info";
        warn "Error ${where} [${debug_context}]: ${error}\n";
    };
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

