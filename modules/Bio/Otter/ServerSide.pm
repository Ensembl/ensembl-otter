package Bio::Otter::ServerSide;

use strict;
use Exporter;

our @ISA       = qw(Exporter);
our @EXPORT    = qw();
our @EXPORT_OK = qw(&error_exit);


sub error_exit {
  my ($q,$reason) = @_;

  print $q->header() if $q && UNIVERSAL::isa($q,'CGI');

  chomp($reason);

  print "<otter>\n";
  print "  <response>\n";
  print "    ERROR:\n$reason\n";
  print "  </response>\n";
  print "</otter>\n";

  print STDERR "ERROR: $reason";

  exit(1);
}
