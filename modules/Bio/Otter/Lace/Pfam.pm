
=pod

=head1 NAME - Bio::Otter::Lace::Pfam

=head1 DESCRIPTION

    This module offer functionalities to use the Pfam website to run sequence searches through the RESTful services

=cut

package Bio::Otter::Lace::Pfam;
use strict;
use warnings;
use LWP;
use LWP::UserAgent;
use HTTP::Request;
use XML::LibXML;
use XML::LibXML::XPathContext;
my $SEARCH_URL = 'http://pfam.sanger.ac.uk/search/sequence';
my $HMM_URL    = 'http://pfam.sanger.ac.uk/family/hmm';
my $SEED_URL   = 'http://pfam.sanger.ac.uk/family/alignment/download/format';

sub new {
	my ($self) = @_;
	return bless {}, $self;
}

sub result_url {
	my ( $self, $r ) = @_;
	if ($r) {
		$self->{_result} = $r;
	}
	return $self->{_result};
}

# submits the sequence search and returns the XML that comes back from the
# server
sub submit_search {
	my ( $self, $seq ) = @_;

	# create a user agent
	my $ua = LWP::UserAgent->new;
	$ua->env_proxy;

	# set up the request
	my $req = HTTP::Request->new( POST => $SEARCH_URL );
	$req->content_type('application/x-www-form-urlencoded');

	# build the query parameters. Use URI to format them nicely for LWP...
	my $uri = URI->new;
	my %param = (
				  seqOpts => 'both',    # search both models and merge results
				  ga      => 0,         # use the gathering threshold
				  seq     => $seq,      # sequence to search
				  output  => 'xml'
	);
	$uri->query_form( %param );
	$req->content( $uri->query );

	# submit the request
	my $res = $ua->request($req);

	# see if it was successful
	warn( 'submission failed: ' . $res->status_line )
	  unless $res->is_success;
	return $res->content;
}

# parses the submission XML and returns the URL for retrieving results and the
# estimated job runtime
sub check_submission {
	my ( $self, $xml ) = @_;

	# parse the XML that came back from the server when we submitted the search
	my $parser = XML::LibXML->new();
	my $dom;
	eval { $dom = $parser->parse_string($xml); };
	if ($@) {
		warn("couldn't parse XML response for submission: $@");
		return;
	}

	# the root element is "jobs"
	my $root = $dom->documentElement();

	# set up to use XPaths
	my $xc = XML::LibXML::XPathContext->new($root);
	$xc->registerNs( 'p', 'http://pfam.sanger.ac.uk/' );

	# we're only running a single Pfam-A search, so there will be only one "job"
	# tag, so we know that these XPaths will each give us only a single node
	my $result_url     = $xc->findvalue('/p:jobs/p:job/p:result_url');
	my $estimated_time = $xc->findvalue('/p:jobs/p:job/p:estimated_time');
	$result_url     =~ s/\s//g;
	$estimated_time =~ s/\s//g;
	$self->result_url($result_url);
	return ( $result_url, $estimated_time );
}

# polls the result URL as often as necessary (up to a hard limit) and returns
# the results XML
sub poll_results {
	my ( $self, $result_url ) = @_;

	# this is the request that we'll submit repeatedly
	my $req = HTTP::Request->new( GET => $result_url );

	# create a user agent
	my $ua = LWP::UserAgent->new;
	$ua->env_proxy;

	# submit the request...
	my $res = $ua->request($req);
	return $res->content;
}

# parses the results XML and return a hash containing the hits and locations
sub parse_results {
	my ( $self, $results_xml ) = @_;
	my $log = Log::Log4perl->get_logger;
	print STDOUT "parsing XML search results\n";
	my $parser = XML::LibXML->new();
	my $dom;
	eval { $dom = $parser->parse_string($results_xml); };
	if ($@) {
		warn("couldn't parse XML response for results: $@");
		return;
	}

	# set up the XPath stuff for this document
	my $root = $dom->documentElement();
	my $xc   = XML::LibXML::XPathContext->new($root);
	$xc->registerNs( 'p', 'http://pfam.sanger.ac.uk/' );

	# get all of the matches, that is the list of Pfam-A families that are found
	# on the sequence
	my @matches =
	  $xc->findnodes(
'/p:pfam/p:results/p:matches/p:protein/p:database/p:match[@type="Pfam-A"]' );
	print 'found ' . scalar @matches . " hit(s)\n";
	my $results = {};
	foreach my $match_node (@matches) {
		print STDOUT (   'looking for locations for Pfam-A '
					   . $match_node->getAttribute('class') . ' '
					   . $match_node->getAttribute('id') . ' ('
					   . $match_node->getAttribute('accession')
					   . ')' );
		my @locations =
		  $xc->findnodes( 'p:location[@significant=1]', $match_node );
		print '  found '
		  . scalar @locations
		  . ' location(s) for '
		  . $match_node->getAttribute('accession') . "\n";
		foreach my $location_node (@locations) {
			my $location = {
							 start => $location_node->getAttribute('start'),
							 end   => $location_node->getAttribute('end')
			};
			push @{ $results->{ $match_node->getAttribute('accession') }
				  ->{locations} }, $location;
		}
	}
	print "done parsing search results\n";
	return { hits => $results };
}
1;
__END__

=head1 AUTHOR

Anacode B<email> anacode@sanger.ac.uk

