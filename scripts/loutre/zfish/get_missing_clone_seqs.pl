#!/usr/bin/env perl
# Copyright [2018-2023] EMBL-European Bioinformatics Institute
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

#use Bio::SeqIO;
#use Bio::Seq;
#use Getopt::Long;
#use Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor;
#use Bio::EnsEMBL::DBSQL::DBAdaptor;
#use Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch;
#use LWP::UserAgent;
#use Hum::SequenceInfo;
use Hum::Pfetch 'get_Sequences';
use Hum::SequenceInfo;
use Hum::FastaFileIO;


#automatically creates fa sequence files for clones not in the db
#te3 27.03.07

my @agp_files = <*.agp>;

foreach my $agp_file (@agp_files) {

  print "\n(get_missing_clone_seqs.pl) Processing $agp_file....\n";
  open(my $fh, "$agp_file") or die "Can't read '$agp_file' : $!";
  while (<$fh>) {
    next if $_ =~ /^\#/; #skip comments
    my @data = split('\t', $_);
    if ($data[4] eq 'F') {

      my $out = &check_for_seq($data[5]);
      if ($out) {
        if ($out == 1) {
          #print "$agp_file: $data[5] already in database\n";
        } elsif ($out == 2) {
          print "  $agp_file: $data[5] seq file already in current directory\n";
        } elsif ($out == 3) {
          print "  $agp_file: $data[5] generated seq file in current directory\n";
        }
      } else {
        warn "$agp_file: Couldnt get sequence for clone $data[5]\n";
      }
    }
  }
  print ".....$agp_file done.\n\n";
}



sub check_for_seq {
  my ($acc_ver) = @_;
  my $seq_file = "$acc_ver.seq";

  my $seq = get_Sequences($acc_ver);

##  my $pfetch ||= Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch->new;
##  my $seq = $pfetch->get_Seq_by_acc($acc_ver);

  if ($seq) {
    # Sequence is available online via pfetch
    return 1;
  } else {

    print "Attempting to read fasta file <$acc_ver.seq> in current dir.\n";
##    my $in;
##    eval { $in = Bio::SeqIO->new(
##           -file   => $seq_file,
##           -format => 'FASTA',
##           );
##        };
##    if ($in) {
##      return(2);

    if (-e $seq_file) {
      $seq = Hum::FastaFileIO->new_DNA_IO($seq_file)->read_one_sequence;
    }

    if ($seq and $seq->name eq $acc_ver) {
      return 2;

    } else {
      # There is no file stored in the current directory, so we try to
      # fetch the current sequence from the Sanger submission system.
      ### my $acc = $acc_ver;
      ### $acc =~ s/^(\S+)\.(\d+)$/$1/;
      my ($acc, $sv) = ($acc_ver =~ /^(\S+)\.(\d+)$/);

      # this should be the only thing necessary now
      my $inf = Hum::SequenceInfo->sanger_sequence_get($acc);
      unless ($inf->sequence_version == $sv) {
        printf STDERR "Current Sanger version of '%s' is '%d' not '%d'\n",
                    $acc, $inf->sequence_version, $sv;
        return;
      }
      $seq = $inf->Sequence;
      Hum::FastaFileIO->new_DNA_IO("> $seq_file")->write_sequences($seq);

      return 3;
    }



##      # this should be the only thing necessary now
##      my $inf  = Hum::SequenceInfo->fetch_by_accession_sv($acc, $ver);
##      my $embl = $inf->get_EMBL_entry;
####      my $seq    = $embl->hum_sequence;
##      my $seq    = $embl->bio_seq;
####      my $header = $acc_ver;
##
##      my $outFile = Bio::SeqIO->new(-file => ">$seq_file" , '-format' => 'FASTA');
##
####      print $outFile $seq_obj;
####    while ( my $seq = $in->next_seq() ) {
##      my $success = $outFile->write_seq($seq);
####    }
##
##      return(3, $success)
##
##    }
  }
}
