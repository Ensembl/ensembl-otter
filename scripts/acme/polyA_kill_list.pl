#!/usr/bin/env perl
# Copyright [2018-2019] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;
use 5.010;

package Bio::Otter::Script::PolyAKillList;
use parent 'Bio::Otter::Utils::Script';

use Readonly;
use Spreadsheet::ParseExcel::SaveParser;

use Bio::EnsEMBL::Attribute;
use Bio::Otter::ServerAction::Script::Region;

Readonly my $ADDITIONAL_COLUMNS_OFFSET => 11;

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
  my @polya = $self->read_worksheet( sheet => $sheet, debug => 1 );

  $self->add_sheet_headers($sheet);
  my $row = 1;

  my ($status, $polyA_start);
  foreach my $pa ( @polya ) {

      if (my $action = $pa->{action}) {
          $status = "Skipping, action '$action'";
          next;
      }
      my ($region_start, $region_end);

      my $strand = $pa->{strand};
      if ($strand == 1) {
          $polyA_start = $pa->{start};
          $region_start = $polyA_start - 10;
          $region_end   = $pa->{end}   + 10;
      } else {
          $polyA_start = $pa->{end};
          $region_start = $polyA_start - 10;
          $region_end   = $pa->{start} + 10;
      }

      $status = 'error_fetching_region';
      my $region = $self->fetch_region($dataset, $pa->{chr}, $region_start, $region_end);
      next unless $region;

      $status = 'polyA_not_found';
      my $polyA_feature = $self->find_polyA_feature($region, $polyA_start, $strand);
      next unless $polyA_feature;

      # We now have a candidate polyA...
      if ($dataset->may_modify) {

          $status = 'ready_to_delete';
          my $sfa = $dataset->otter_dba->get_SimpleFeatureAdaptor;
          $sfa->remove($polyA_feature);

          $status = 'DELETED';
          $dataset->inc_modified_count;
      } else {
          $status = 'would_delete';
      }

  } continue {
      say sprintf('%s: %s, start: %s',
                  $pa->{chr}, $status,
                  $polyA_start    ? $polyA_start    : '-',
          );

      my $col = $ADDITIONAL_COLUMNS_OFFSET;
      $sheet->AddCell($row, $col+0, $polyA_start) if $polyA_start;
      $sheet->AddCell($row, $col+1, $status);

      $row++;
  }

  $self->write_spreadsheet($workbook);
  return;
}

sub fetch_region {
    my ($self, $dataset, $chr, $start, $end) = @_;
    my $slice = $dataset->otter_dba->get_SliceAdaptor->fetch_by_region('chromosome', $chr, $start, $end);
    return unless $slice;
    return $dataset->fetch_region_by_slice(
        start => $start,
        end   => $end,
        slice => $slice,
        );
}

sub find_polyA_feature {
    my ($self, $region, $start, $strand) = @_;
    foreach my $f ($region->seq_features) {
        next unless $f->display_label eq 'polyA_site';
        next unless $strand == $f->strand;
        next unless $start  == $f->seq_region_start;
        return $f;
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
            my $cell = $sheet->get_cell($i, $j);
            $details{$cols_by_index{$j}} = $cell->value if $cell;
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
Bio::Otter::Script::PolyAKillList->import->run;

exit;

# EOF
