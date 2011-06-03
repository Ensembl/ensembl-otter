#!/usr/local/bin/perl


$| = 1;

use strict;
use warnings;

use Getopt::Long;
use HTTP::Request;
use LWP;
use OtterDefs;

my $serverport   = $OTTER_SERVER_PORT;
my $serverhost   = $OTTER_SERVER;

my $niter = 10;

&GetOptions(
  'niter:n'      => \$niter,
  'serverhost:s' => \$serverhost,
  'serverport:n' => \$serverport,
);

my $server_url   = "http://" . $serverhost . ":" . $serverport;
print $server_url . "\n";

my $nfailed = 0;
for (my $i = 0 ; $i < $niter ; $i++) {
  print "\n*** Iteration $i/$niter ***\n";
  
  #Fetch it from the server
  my $ua = LWP::UserAgent->new;
    my $request_str = $server_url . "/perl/get_datasets";
  

  print "\nRequest URL : $request_str\n\n";

  my $request  = HTTP::Request->new(GET => $request_str);
  my $response = $ua->request($request);

  if ($response->content =~ /ERROR/s) {
    print "Failed request\n";
    print $response->content;
    next;
  } elsif (!($response->content =~ /Datasets/)) {
    print "Failed retrieving datasets\n";
    $nfailed++;
  }

  print $response->content;

}

print "Number of iterations = $niter. Number of failures = $nfailed\n";
