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

### Bio::Vega::Utils::GFF::Format

package Bio::Vega::Utils::GFF::Format;

use strict;
use warnings;

use Carp;
use Scalar::Util qw(looks_like_number);

sub new {
    my ($pkg, $hash) = @_;
    bless $hash, $pkg;
    return $hash;
}

my $strand_hash = {
     1 => '+',
    -1 => '-',
};

sub _gff_escape_seqid {
    # escapes everything except a restricted set of characters
    s/([^-a-zA-Z0-9.:^*\$\@!+_?|])/sprintf "%%%02X", ord($1)/eg;
    return;
}

sub _gff_escape_source {
    # escapes everything except a restricted set of characters
    s/([^-a-zA-Z0-9.:^*\$\@!+_? ])/sprintf "%%%02X", ord($1)/eg;
    return;
}

sub _gff_escape_field {
    # escapes a minimal set of characters
    s/([\t\r\n[:cntrl:];=%&])/sprintf "%%%02X", ord($1)/eg;
    return;
}

sub _gff_escape_attribute {
    # like gff_escape, but escapes commas too
    s/([\t\r\n[:cntrl:];=%&,])/sprintf "%%%02X", ord($1)/eg;
    return;
}

sub _gff_escape_target_attribute {
    # like gff_escape, but escapes commas and spaces too
    s/([\t\r\n[:cntrl:];=%&, ])/sprintf "%%%02X", ord($1)/eg;
    return;
}

my @attribute_quotable = qw(
    Name Description Class Target Gaps Gap Note
    Stable_ID Locus Locus_Stable_ID DB_Name URL
    cigar_ensembl cigar_exonerate cigar_bam
    );
my $attribute_quotable = { map { $_ => 1 } @attribute_quotable };

sub gff_line { ## no critic( Subroutines::ProhibitManyArgs )
    my ($self,
        $seqid,
        $source,
        $type,
        $start,
        $end,
        $score,
        $strand,
        $phase,
        $attribute_hash,
        ) = @_;

    _gff_escape_seqid for $seqid;
    _gff_escape_source for $source;

    my @field_list =
        (
         $type,
         (sprintf "%d", $start),
         (sprintf "%d", $end),
         ((defined $score and looks_like_number $score) ? (sprintf "%f", $score) : '.'),
         $strand_hash->{$strand} || $strand || '.',
         defined $phase ? $phase : '.',
        );
    _gff_escape_field for @field_list;

    my $attribute_escape = $self->attribute_escape;
    my $attribute_format = $self->attribute_format;

    my @attribute_strings = ();
    for my $key (sort keys %{$attribute_hash}) {
        my $value = $attribute_hash->{$key};
        defined $value or next;

        if ($key eq "Target") {
            my ($target_id, $target_start, $target_end, $target_strand) = @{$value};
            if ($attribute_escape) {
                _gff_escape_target_attribute for $target_id;
            }
            my @target_field_list = ( $target_id, $target_start, $target_end );
            push @target_field_list
                , $strand_hash->{$target_strand} || $target_strand
                if $target_strand;
            $value = join ' ', @target_field_list;
        }

        if ($attribute_escape) {
            unless ($key eq 'Target') { # the Target tag is already escaped
                _gff_escape_attribute for $value;
            }
            _gff_escape_attribute for $key;
        }
        elsif ($attribute_quotable->{$key}) {
            $value = qq{"$value"};
        }

        push @attribute_strings, sprintf $attribute_format, $key, $value;
    }
    my $attribute_string = join ";", @attribute_strings;

    my $gff_line =
        sprintf "%s\n", join "\t"
        , $seqid, $source, @field_list, $attribute_string;

    return $gff_line;
}

# attributes

sub attribute_format {
    my ($self) = @_;
    my $attribute_format = $self->{'attribute_format'};
    return $attribute_format;
}

sub attribute_escape {
    my ($self) = @_;
    my $attribute_escape = $self->{'attribute_escape'};
    return $attribute_escape;
}

1;

__END__

=head1 NAME - Bio::Vega::Utils::GFF::Format

=head1 SYNOPSIS

Class for formatting GFF lines.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

