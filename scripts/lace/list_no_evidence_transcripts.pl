#!/usr/bin/env perl

use warnings;


### example_script

use strict;
use Bio::Otter::Lace::Defaults;

{
    my $dataset_name = undef;
    my $total = 0;
    my $quiet = 0;

    my $usage = sub { exec('perldoc', $0) };
    # This do_getopt() call is needed to parse the otter config files
    # even if you aren't giving any arguments on the command line.
    Bio::Otter::Lace::Defaults::do_getopt(
        'h|help!'       => $usage,
        'dataset=s'     => \$dataset_name,
	'quiet!'        => \$quiet,
	'total!'        => \$total,
        ) or $usage->();
    $usage->() unless $dataset_name;

    if ($quiet and not $total) {
	warn "Using -quiet but not -total - no output will be produced!";
    }

    # Client communicates with otter HTTP server
    my $cl = Bio::Otter::Lace::Defaults::make_Client();
    
    # DataSet interacts directly with an otter database
    my $ds = $cl->get_DataSet_by_name($dataset_name);
    my $otter_dba = $ds->get_cached_DBAdaptor;
    
    my $list_transcripts = $otter_dba->prepare(q{
	SELECT
		t.transcript_id, 
		e.name,
		e.type,
		t.biotype
	FROM
		transcript t
	   JOIN gene g USING (gene_id)
	   LEFT JOIN evidence e ON t.transcript_id = e.transcript_id
	WHERE
		t.is_current = 1
	    AND g.source = 'havana'
	    AND e.type IS NULL
        ORDER BY t.transcript_id
    });
    $list_transcripts->execute;

    my $count = 0;
    while (my ($tid, $e_name, $e_type, $biotype) = $list_transcripts->fetchrow()) {
	++$count;
	printf( "%10d: %s/%s\t[%s]\n", 
		$tid, 
		defined($e_name) ? $e_name : 'U', 
		defined($e_type) ? $e_type : 'U', 
		$biotype
	    ) unless $quiet;
    }
    printf "Total: %d\n", $count if $total;

}



__END__

=head1 NAME - list_no_evidence_transcripts

=head1 SYNOPSIS

list_no_evidence_transcripts -dataset <DATASET NAME>

=head1 DESCRIPTION

Checks for current havana transcripts having no entries in the evidence table.

=head1 AUTHOR

Michael Gray B<email> mg13@sanger.ac.uk

