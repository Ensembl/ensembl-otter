#!/usr/local/bin/perl -w

use strict;

use Bio::SeqIO;
use Getopt::Long;
use Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch;
use LWP::UserAgent;


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
		}
		elsif ($out == 2) {
		    print "$agp_file: $data[5] seq file already in current directory\n";
		}
		elsif ($out == 3) {
		    print "$agp_file: $data[5] generated seq file in current directory\n";
		}
	    }
	    else {
		warn "$agp_file: Couldnt get sequence for clone $data[5]\n";
	    }
	}
    }
    print ".....$agp_file done.\n";
}



sub check_for_seq {
    my ($acc_ver) = @_;
    my $seq_file = "$acc_ver.seq";

    my $pfetch ||= Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch->new;
    my $seq = $pfetch->get_Seq_by_acc($acc_ver);
    
    if ($seq) {
	return(1);
    }
    else {

	warn "Attempting to read fasta file <$acc_ver.seq> in current dir.\n";
	my $in;
	eval {
	    $in = Bio::SeqIO->new(
				  -file   => $seq_file,
				  -format => 'FASTA',
				  );
	};
	
	if ($in) {
	    return(2);
	}
	else {
	    
	    #no file present- got to generate it
            my $acc = $acc_ver;
	    $acc =~ s/^(\S+)\.(\d+)$/$1/;
	    
	    #get the url of the fasta file
	    my $url = "http://intwebdev.sanger.ac.uk/cgi-bin/users/jgrg/submission_status?query_type=accession&query_name=$acc&Search=Search&.cgifields=query_type";
	    foreach (my $i = 1; $i < 14; $i++) { #keeps trying three times if it fails 

		my $ua = LWP::UserAgent->new;
		my $req = HTTP::Request->new(GET => $url);

		my $res = $ua->request($req);
		my $cont = $res->content;
		my $url2;

		my $myfile;
                if ($cont =~ m|.+Fasta file</th><td><a href=\"([^\"]+)|) {
		
                
                # from here onwards this has to be replaced because the webside is not accessible via web anymore (still is from cbi4)
                #    $url2 = "http://intwebdev.sanger.ac.uk/".$1;
		#}
		
		#get the fasta file
		#$ua = LWP::UserAgent->new;
		#$req = HTTP::Request->new(GET => $url2);
		#$res = $ua->request($req);
		#$cont = $res->content;
		
		#$cont =~ s/^>\S+/>$acc_ver/; #change the name to acc_ver
                    ($myfile) = ($cont =~ /(\/lustre\/cbi4\/work1\/humpub\/ftp_ghost\/zebrafish\/Chr_\d+\/\w+)/); 
                    warn "opening $myfile\n";
                    open(SEQ, $myfile) or die "Cannot open input file $myfile $1\n"; 
                    open(FILE, ">$seq_file") or die "Cannot open output file $seq_file $1\n";
                    while (<SEQ>) {
                        s/^>\S+/>$acc_ver/;
                        print FILE;
                    }       
                    close SEQ;
                    close FILE;
                    return(3)
                }



		#if ($cont =~ m/^>\S+\n[atgc\n]+$/) { #sequence is ok
		    #create the sequence file
		#    open (FILE,  ">$seq_file") or die "Can't open $seq_file\n";
		#    print FILE $cont;
		#    close FILE;
		#    return(4);
		#}
		else {
		    print "Failed to get sequence instead got $cont. Retrying....\n";
		}
	    }
	}
    }
}
