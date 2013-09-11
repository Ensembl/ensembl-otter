#!/usr/bin/env perl

use strict;
use warnings;
use 5.010;

package Bio::Otter::Script::ExtendTranscriptsToPolyA;
use parent 'Bio::Otter::Utils::Script';

use Readonly;
use Spreadsheet::ParseExcel::SaveParser;
use Sys::Hostname;
use Try::Tiny;

use Bio::Otter::ServerAction::Script::Region;

Readonly my $ADDITIONAL_COLUMNS_OFFSET => 4;

sub ottscript_opt_spec {
  return (
    [ "excel-file=s",      "Excel file containing transcript specs",      { required => 1 }       ],
    [ "excel-sheet=s",     "Excel worksheet containing transcript specs", { default => 'Sheet1' } ],
    [ "excel-save-file=s", "Excel file for output log",                                           ],
  );
}

sub ottscript_options {
    return (
        dataset_mode          => 'only_one',
        allow_modify_limit    => 1,
        );
}

sub ottscript_validate_args {
    my ($self, $opt, $args) = @_;
    my $excel_path = $opt->{excel_file};
    unless ( -r $excel_path ) {
        $self->usage_error("Cannot read Excel file path '$excel_path'");
    }
    $self->excel_path($excel_path);
    $self->excel_sheet($opt->{excel_sheet});
    $self->excel_save_path($opt->{excel_save_file});

    return;
}

sub process_dataset {
  my ($self, $dataset) = @_;

  my ($sheet, $workbook) = $self->open_parse_spreadsheet;
  my @transcripts = $self->read_worksheet( sheet => $sheet, debug => 1 );

  $self->add_sheet_headers($sheet);
  my $row = 1;

  my ($status, $polyA_3p_coord, $ts_3p_coord, $delta);
  foreach my $ts ( @transcripts ) {

      $polyA_3p_coord = $ts_3p_coord = $delta = undef;
      my $strand = $ts->{strand};

      $status = 'ts_not_found_in_db';
      my $vega_ts = $dataset->fetch_vega_transcript_by_stable_id($ts->{transcript});
      next unless $vega_ts;

      $status = 'error_fetching_region';
      my $region = $self->fetch_transcript_region($dataset, $vega_ts);
      next unless $region;

      $status = 'ts_not_found_in_region';
      my $region_ts = $self->find_transcript_in_region($region, $ts->{transcript});
      next unless $region_ts;

      $status = 'ts_strand_mismatch';
      next unless $region_ts->strand == $strand;
      $ts_3p_coord = $strand == 1 ? $region_ts->seq_region_end : $region_ts->seq_region_start;

      $status = 'polyA_not_found';
      my $polyA_feature = $self->find_polyA_feature($region, $region_ts, $ts->{end_coordinate});
      next unless $polyA_feature;
      $polyA_3p_coord = $strand == 1 ? $polyA_feature->seq_region_end : $polyA_feature->seq_region_start;

      # We now have a suitable transcript and feature, do a few final checks...

      $status = 'already_fixed';
      next if $ts_3p_coord == $polyA_3p_coord;

      $status = 'delta_out_of_range';
      $delta = ($polyA_3p_coord - $ts_3p_coord) * $strand;
      next if ($delta < 1 or $delta > 20);

      $status = 'ready_to_extend';

  } continue {
      say sprintf('%s [%s]: %s, ts3p: %s, pa3p: %s, delta: %s',
                  $ts->{transcript}, $ts->{chromosome}, $status,
                  $ts_3p_coord    ? $ts_3p_coord    : '-',
                  $polyA_3p_coord ? $polyA_3p_coord : '-',
                  $delta          ? $delta          : '-',
          );

      my $col = $ADDITIONAL_COLUMNS_OFFSET;
      $sheet->AddCell($row, $col+0, $ts_3p_coord) if $ts_3p_coord;
      $sheet->AddCell($row, $col+1, $delta)       if $delta;
      $sheet->AddCell($row, $col+2, $status);

      $row++;
  }

  $self->write_spreadsheet($workbook);
  return;
}

sub fetch_transcript_region {
    my ($self, $dataset, $ts) = @_;
    my ($start, $end) = ($ts->start, $ts->end);
    if ($ts->{strand} == 1) {
        $end += 100;
    } else {
        $start -= 100;
    }
    return $dataset->fetch_region_by_slice(
        start => $start,
        end   => $end,
        slice => $ts->slice,
        );
}

sub find_transcript_in_region {
    my ($self, $region, $stable_id) = @_;
    foreach my $g ($region->genes) {
        foreach my $ts (@{$g->get_all_Transcripts}) {
            return $ts if $ts->stable_id eq $stable_id;
        }
    }
    return;
}

sub find_polyA_feature {
    my ($self, $region, $ts, $expected_end) = @_;
    foreach my $f ($region->seq_features) {
        next unless $f->display_label eq 'polyA_site';
        next unless $ts->strand == $f->strand;
        if ($f->strand == 1) {
            return $f if $f->seq_region_end == $expected_end;
        } else {
            return $f if $f->seq_region_start == $expected_end;
        }
    }
    return;
}

sub open_parse_spreadsheet {
    my ($self) = shift;

    my $excel_path  = $self->excel_path;
    my $excel_sheet = $self->excel_sheet;

    my $parser   = Spreadsheet::ParseExcel::SaveParser->new;
    my $workbook = $parser->Parse($excel_path);
    die "Parsing '$excel_path': ", $parser->error_code unless $workbook;

    my $sheet = $workbook->worksheet($excel_sheet);
    die "No sheet '$excel_sheet' in '$excel_path'" unless $sheet;

    return ($sheet, $workbook);
}

# This is fairly general-purpose (see ~mg13/Work/Investigations/Misc/RT296944/kill_polya.pl)
# so ought to go into a module if used again!
#
sub read_worksheet {
    my ($self, %options) = @_;

    my $sheet = $options{sheet};
    my $debug = $options{debug};

    my ($col_min, $col_max) = $sheet->col_range;
    my ($row_min, $row_max) = $sheet->row_range;
    warn "Range: $col_min-$col_max:$row_min-$row_max\n" if $debug;

    my %cols_by_name;
    my %cols_by_index;
    for my $j ( $col_min..$col_max ) {
        my $col_name = $sheet->get_cell($row_min, $j)->value;
        $col_name =~ s/\s+/_/g;
        $cols_by_name{$col_name} = $j;
        $cols_by_index{$j}       = $col_name;
    }
    warn "Have columns: ", join(', ', map { $cols_by_index{$_} } $col_min..$col_max), "\n" if $debug;

    my @results;
    for my $i ( ($row_min+1)..$row_max ) {
        my %details;
        for my $j ( $col_min..$col_max ) {
            $details{$cols_by_index{$j}} = $sheet->get_cell($i, $j)->value;
        }
        push @results, \%details;
    }
    warn "Got ", scalar(@results), " rows\n" if $debug;

    return @results;
}

sub add_sheet_headers {
    my ($self, $sheet) = @_;
    my $col = $ADDITIONAL_COLUMNS_OFFSET;
    foreach my $header (
        'ts end coordinate',
        'delta',
        'status',
        ) {
        $sheet->AddCell(0, $col++, $header);
    }
    return;
}

sub write_spreadsheet {
    my ($self, $workbook) = @_;

    my $save_path = $self->excel_save_path;
    return unless $save_path;

    $workbook->SaveAs($save_path);
    return;
}

sub transcript_adaptor {
    my ($self, @args) = @_;
    ($self->{'transcript_adaptor'}) = @args if @args;
    my $transcript_adaptor = $self->{'transcript_adaptor'} ||= $self->dataset->otter_dba->get_TranscriptAdaptor;
    return $transcript_adaptor;
}

sub excel_path {
    my ($self, @args) = @_;
    ($self->{'excel_path'}) = @args if @args;
    my $excel_path = $self->{'excel_path'};
    return $excel_path;
}

sub excel_sheet {
    my ($self, @args) = @_;
    ($self->{'excel_sheet'}) = @args if @args;
    my $excel_sheet = $self->{'excel_sheet'};
    return $excel_sheet;
}

sub excel_save_path {
    my ($self, @args) = @_;
    ($self->{'excel_save_path'}) = @args if @args;
    my $excel_save_path = $self->{'excel_save_path'};
    return $excel_save_path;
}

# End of module

package main;

$|++;                           # unbuffer stdout for sane interleaving with stderr
Bio::Otter::Script::ExtendTranscriptsToPolyA->import->run;

exit;

# EOF
