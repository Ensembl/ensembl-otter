#!/usr/bin/env perl

use strict;
use warnings;
use 5.010;

package Bio::Otter::Script::ExtendTranscriptsToPolyA;
use parent 'Bio::Otter::Utils::Script';

use Spreadsheet::ParseExcel;
use Sys::Hostname;
use Try::Tiny;

use Bio::Otter::ServerAction::Script::Region;

sub ottscript_opt_spec {
  return (
    [ "excel-file=s",  "Excel file containing transcript specs",      { required => 1 } ],
    [ "excel-sheet=s", "Excel worksheet containing transcript specs", { default => 'Sheet1' } ],
  );
}

sub ottscript_options {
    return (
        dataset_mode          => 'only_one',
        allow_iteration_limit => 1,
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
    return;
}

sub process_dataset {
  my ($self, $dataset) = @_;

  my @transcripts = $self->read_worksheet( debug => 1 );
  my $status;
  foreach my $ts ( @transcripts ) {

      $status = 'ts_not_found_in_db';
      my $vega_ts = $dataset->fetch_vega_transcript_by_stable_id($ts->{transcript});
      next unless $vega_ts;

      $status = 'error_fetching_region';
      my $region = $self->fetch_transcript_region($dataset, $vega_ts);
      next unless $region;

      $status = 'ts_not_found_in_region';
      my $region_ts = $self->find_transcript_in_region($region, $ts->{transcript});
      next unless $region_ts;

      $status = 'polyA_not_found';
      my $polyA_feature = $self->find_polyA_feature($region, $region_ts, $ts->{end_coordinate});
      next unless $polyA_feature;

      # We now have a suitable transcript and feature, do a few final checks...

      my ($low, $high, $report);
      if ($region_ts->strand == 1) {
          $low  = $region_ts->seq_region_end;
          $high = $polyA_feature->seq_region_end;
          $report = "strand +, ts $low, polyA $high";
      } else {
          $low = $polyA_feature->seq_region_start;
          $high = $region_ts->seq_region_start;
          $report = "strand -, ts $high, polyA $low";
      }

      $status = 'already_fixed';
      next if $low == $high;

      my $delta = $high - $low;
      if ($delta < 1 or $delta > 20) {
          $status = "delta_out_of_range: $report, delta $delta";
          next;
      }

      $status = 'ready_to_extend';

  } continue {
      say sprintf('%s [%s]: %s', $ts->{transcript}, $ts->{chromosome}, $status);
  }

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

# This is fairly general-purpose (see ~mg13/Work/Investigations/Misc/RT296944/kill_polya.pl)
# so ought to go into a module if used again!
#
sub read_worksheet {
    my ($self, %options) = @_;
    my $debug = $options{debug};

    my $excel_path  = $self->excel_path;
    my $excel_sheet = $self->excel_sheet;

    my $parser   = Spreadsheet::ParseExcel->new;
    my $workbook = $parser->parse($excel_path);
    die "Parsing '$excel_path': ", $parser->error_code unless $workbook;

    my $sheet = $workbook->worksheet($self->excel_sheet);
    die "No sheet '$excel_sheet' in '$excel_path'" unless $sheet;

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

# End of module

package main;

$|++;                           # unbuffer stdout for sane interleaving with stderr
Bio::Otter::Script::ExtendTranscriptsToPolyA->import->run;

exit;

# EOF
