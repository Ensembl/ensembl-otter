package OtterUtils;

use Exporter;
use vars qw(@ISA @EXPORT);
use strict;

@ISA=qw(Exporter);

@EXPORT=qw(get_tmp_file dump_config get_otter_config);

sub dump_config {
  my $info = shift;

  foreach my $sect (keys %$info) {
    print "Section = $sect\n";
    foreach my $key (keys %{$info->{$sect}}) {
      print "$key " . $info->{$sect}->{$key} . "\n";
    }
  }
}

sub get_otter_config {
  my ($filename) = @_;

  my %info = ();
  if (open(INFO, $filename)) {

    #print "Reading info\n";

    my $cursect = undef;
    my %defhash;
    my $curhash;

    while (<INFO>) {
      next if /^\#/;
      next unless /\w+/;
      chomp;
      if (/\[(.*)\]/) {
        if (!defined($cursect) && $1 ne "defaults") {
          die "ERROR: First section in otter.inf should be defaults\n";
        } elsif ($1 eq "defaults") {
          #print "Got default section\n";
          $curhash = \%defhash;
        } else {
          $curhash = {};
          foreach my $key (keys %defhash) {
            $curhash->{$key} = $defhash{$key};
          }
        }
        $cursect = $1;

        $info{$cursect} = $curhash;
      } elsif (/(\w+)\s+(\w+)/) {
        #print "Reading entry $1 $2\n";
        $curhash->{$1} = $2;
      }
    }
    return (\%info);
  } else {
    print STDERR "Warning: no otter configuration available from $filename\n";
    return (undef);
  }
}

#From pipeline code
sub get_tmp_file {
  my ($dir,$stub,$ext) = @_;


  if ($dir !~ /\/$/) {
    $dir = $dir . "/";
  }

  # This is not good

  my $num = int(rand(10000));
  my $file = $dir . $stub . "." . $num . "." . $ext;

  while (-e $file) {
    $num = int(rand(10000));
    $file = $stub . "." . $num . "." . $ext;
  }

  return $file;
}

1;
