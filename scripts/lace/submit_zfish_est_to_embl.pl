
#!/usr/local/ensembl/bin/perl -w

use strict;
use EST_DB::Utils::Clone_Library_directions qw(%library_clone_info);
use Sys::Hostname;

# Chao-Kung Chen


# submit_zfish_est_to_embl: wrapper to run various scripts of the est_db packages
#                           for submitting est to EMBL


#------------------------------
#      GLOBAL SETTINGS
#------------------------------

my $release    = "2006_08_10";
my $taxon_id   = 7955;
my $lib_name   = "ZF_mu";
my $lib_desc   = "Zebrafish MyoBlast cDNA library";

my $outfile_dir = "/nfs/disk100/humpub/est/zebrafish/$lib_name"."_$release";
my $embl        = "$outfile_dir/$lib_name"."_$release".".embl";

my $repository = "/nfs/repository/p700/ZF_mu_cDNA";
my $passfile   = "fn.ZF_mu_cDNA.Pass";
my @dirs       = `ls -d $repository/0*`;  # these subdirs contain all ESTs

my @contamination_confs = qw(WuBLASTN_contaminants WuBLASTN_vector WuBLASTN_pSPORT1_vec );

my $host = hostname();
my $base;

# run est loading on this machine
if ( $host =~ /hcs/ or $host eq "humsrv1" ){
  $base  = "/nfs/team71/analysis/ck1/SCRIPT_CVS/est_db_tigr";
}

# do Blast on ecs4 cluster
elsif ( $host =~ /ecs/ ){
  # estdb to work with Tigr tgicl clustering program
  $base = "/ecs4/work5/finished/ck1/est_db_tigr";
}

# run on ecs4 is due to many script having #! lines pointing to perl binary on ecs cluster
print STDERR "You are on $host\n";

my $conf       = "$base/conf/zfish_est_submit_DB.conf";
my $scripts    = "$base/scripts";

#------------------------------------------------------------------------------
#    First double check all primers used for EST directions
#    This is use in the hardcoded %EST_DB::Utils::Clone_Library_directions
#------------------------------------------------------------------------------

if ( $ARGV[0] == 0 ) {

  my $seen = {};

  foreach my $d ( @dirs ) {
	chomp $d;
	#my @passed = `cat $d/$passfile`;
	my @passed = `ls $d`;

	foreach ( @passed ) {
	  #print "$d/$_\n";
	  next if $_ !~ /SP6$|T7$/;
	  /.+\.(.+)$/;
	  $seen->{$1}++ unless $seen->{$1};
	}
  }

  my ($ori, $new);
  my $old = {};
  map {$ori = $_;
	   $ori =~ s/.+\.//;
	   $old->{$ori}++ unless $old->{$ori};
	 } keys %{$library_clone_info{'ZF_mu'}};

  foreach ( keys %$seen ) {
	unless ( $old->{$_} ){
	  $new++;
	  print "$_ is NEW => need to UPDATE %EST_DB::Utils::Clone_Library_directions::library_clone_info\n";
	}
  }
  print "%library_clone_info is up-to-date\n" unless $new;
}


#----------------------------------------
#      WORKING ON SUBMISSION STEPS
#----------------------------------------

#	1.    CREATE DATABASE TABLES

if ( $ARGV[0] == 1 ){

  print STDOUT "1.    CREATE DATABASE TABLES\n\n";
warn $conf;
  my $s = system("perl $scripts/create_est_tables -conf $conf");
  check_status($s);
}


#   2.    MAKE EST LIBRARIES

if ( $ARGV[0] == 2 ){

  print STDOUT "2.    MAKE EST LIBRARIES\n\n";
  my $s = system("perl $scripts/make_EST_DB_library -db_conf $conf -library_name $lib_name -library_description $lib_desc");
  check_status($s);
}

#   3.    LOAD SEQUENCED ESTs FROM REPOSITORY (run from genesis cluster)

if ( $ARGV[0] == 3 ) { #and $host =~ /hcs/){

  print STDOUT "3.    LOAD SEQUENCED ESTs FROM REPOSITORY\n\n";

  # extract seq from ESTs in each subdir and load only seq. length > 50 bp
  foreach my $dir ( @dirs ){

	chomp $dir;
	my $s = system("perl $base/submissions/load_EST_DB_from_repository -db_conf $conf -library_name $lib_name -internal_version 2 -repository_dir $dir -pass_file $passfile -min_length 50");
	die $! if $s != 0;
  }
  #  print STDOUT "Command successful\n\n";
}

#   4.    SETUP EST BLAST to check for contaminants in EST sequences (run on ecs4 cluster)

if ( $ARGV[0] == 4 and $host =~ /ecs/ ){

  # first populate conf table for blasting
  #my @contamination_confs = qw(WuBLASTN_contaminants );
  my @contamination_confs = qw(WuBLASTN_pSPORT1_vec WuBLASTN_vector);
  foreach my $contamination ( @contamination_confs ){

	print STDOUT "4.     SETUP EST BLAST to check for contaminants in EST sequences\n\n";

	#my $s = system("$scripts/setup_EST_DB_BLAST --db_conf=$conf --library_name=$lib_name --search_conf_name=$contamination --incremental");
	my $s = system("$scripts/setup_EST_DB_BLAST --db_conf=$conf --library_name=$lib_name --search_conf_name=$contamination");
	check_status($s);
  }
}

#   5.    SUBMIT EST BLAST JOBS
#         Make sure that  $parse_fasta_despatcher in EST_DB::Utils.pm has the key name the same as db_name col of the external_db table
#         The  sequence_source of the external_db table, when using OBDA, should be pointing to the name of the subdir of OBDAIndex
#         named as the dbname col

if ( $ARGV[0] == 5 and $host =~ /ecs/ ){

  my @contamination_confs = qw( WuBLASTN_pSPORT1_vec );
  foreach my $contamination ( @contamination_confs ){

	print STDOUT "5.     SUBMIT EST BLAST JOBS for $contamination\n\n";

	print "Using  $scripts/submit_EST_DB_jobs\n";
	my $s = system("perl $scripts/submit_EST_DB_jobs --db_conf=$conf --library_name=$lib_name --search_conf_name=$contamination --host_type=bc_hosts --lsf_output_dir='/ecs4/scratch4/ck1/est_out' ");
	check_status($s);
  }
}


#   6.    UPDATE EST CLONES

if ( $ARGV[0] == 6 and $host =~ /ecs/ ){

  print STDOUT "6.     UPDATE EST CLONES\n";

  my $srch = join(" ", @contamination_confs);
  warn $srch;
  my $s = system("$scripts/update_clone_status --db_conf=$conf --library_name=$lib_name --search_conf_name=\"$srch\"");
}

#   7.    UPDATE CURRENT ESTS
#         NOTE: the current_read col of older version ESTs should be changed from 'yes' to 'no'

if ( $ARGV[0] == 7 and $host =~ /ecs/ ){

  print STDOUT "7.     UPDATE CURRENT ESTS\n";
  my $s = system("$base/submissions/update_est_is_current --db_conf=$conf --library_name=$lib_name --min_internal_version=2");

  # double check the result by
  #select e.current_read, count(*) from est e, est_clone ec where e.est_clone_id = ec.est_clone_id and ec.library_id = 1 group by e.current_read;
}

#   BACKUP DATABASE now to /nfs/disk100/humpub/est/txt_db_dump/dbname_yyy_mm_dd.sql

#   8.    SUBMIT AND WITHDRAW ESTs: generates a file of ACs for withdraws to email to EBI

if ( $ARGV[0] == 8 and $host =~ /ecs/ ){

  print STDOUT "8.     SUBMIT AND WITHDRAW ESTs\n";

  my $s = system("mkdir $outfile_dir");
  if ( $s == 0 ){
	my $s = system("$base/submissions/submit_and_withdraw_ests --db_conf=$conf --library_name=$lib_name --outfile_dir=$outfile_dir --release_date=$release");
	check_status($s);
  }

  # double check result by
  # select submission_status, count(*) from est group by submission_status;
}


#   9.    CHECK_LIBRARY_CLONES_ESTS_STATUS

if ( $ARGV[0] == 9 and $host =~ /ecs/ ){

  print STDOUT "9.     CHECK_LIBRARY_CLONES_ESTS_STATUS\n";

  my $s = system("$base/utils/check_library_clones_ESTs_status --db_conf=$conf --library_name=$lib_name");
  check_status($s);
}

#   10.    MAKE EMBL FLATFILE

if ( $ARGV[0] == 10 ){

  # species should match the species_name col in submissions db on otterlive

  print STDOUT "10.   MAKE EMBL FLATFILE\n";

  my $fasta_file = $outfile_dir."/".$lib_name."_$release"."_ESTs_to_submit.fasta";

  # filename to submit to EMBL, eg, ZF_mu_2006_08_10.embl

  warn "EMBL file output: $embl\n\n";

  my $s = system("$base/submissions/make_embl_flatfile_2 --taxon_id=$taxon_id --lib=$lib_name --species='Zebrafish' --db_conf=$conf --fasta=$fasta_file > $embl");

  check_status($s);
}

#   11.    SUBMIT TO EMBL: do this on humsrv1 (this host is allowed to go thru EBI firewall)

if ( $ARGV[0] == 11 and $host eq "humsrv1" ){

  my $PIPELINE = "/nfs/team71/analysis/ck1/SCRIPT_CVS/est_db_tigr";
  print STDOUT "11.   SUBMIT TO EMBL\n";
  my $s = system("$base/submissions/submit_zfish_ests $embl");
}

#------------------------------------
#          POST SUBMISSION 
#------------------------------------

#   12.    UPDATE EST STATUS IN EST DB (WAIT OVERNIGHT SO EBI ORACLE DB IS CONSISTENT)

if ( $ARGV[0] == 12 and $host eq "humsrv1" ){

  my $PIPELINE = "/nfs/team71/analysis/ck1/SCRIPT_CVS/est_db_tigr";
  print STDOUT "USING conf: $conf\n\n";
  print STDOUT "12.   UPDATE EST STATUS IN EST DB\n";

  my $errfile = "/nfs/disk100/humpub/est/zebrafish/update_EST_status.err";
  # NOTE: can use --test first w/o writing immediately to estdb
  my $s = system("$base/submissions/update_est_submission_status --db_conf=$conf --err_log_file=errfile --test");
  #my $s = system("$base/submissions/update_est_submission_status --db_conf=$conf --err_log_file=$errfile");
}

#   13.    DUMP ESTs AND UPDATE FTP SITE

if ( $ARGV[0] == 13 ){

  print STDOUT "13.    DUMP ESTs AND UPDATE FTP SITE\n";

  # FTP: /nfs/disk69/ftp/pub/EST_data/Zebrafish/Current_ESTs

  my $estdump = "/nfs/disk100/humpub/est/txt_db_dump/zebrafish_est/Zebrafish_ZF_mu_ESTs_$release.fasta";
  my $s = system("$scripts/utils/dump_ESTs --db_conf=$conf --library_name=$lib_name --file_name=$estdump
                  --ftp_site_format --accepted");

  if ( $s == 0 ){
	print "Zipping $estdump\n\n";
	$s = system("gzip $estdump");
  }


}

#-------------------------------------------
#         PREPARING FOR CLUSTERING
#-------------------------------------------


#   14.    RepeatMasking ESTs


if ( $ARGV[0] == 14 ){

  print STDOUT "14.    RepeatMasking ESTs\n";

  my $s = system("$scripts/setup_EST_DB_RepeatMask --db_conf=$conf --library_name=$lib_name --conf_name=RepeatMask");
}

#   15.    Submit RepeatMasking JOBS

if ( $ARGV[0] == 15 ){

  print STDOUT "15.    Submit RepeatMasking JOBS\n";
  my $s = system("$scripts/submit_EST_DB_jobs --db_conf=$conf --library_name=$lib_name --search_conf_name=RepeatMask");
}


#   16.    DUMP RepeatMasked EST SEQUENCES


if ( $ARGV[0] == 16 ){

  print STDOUT "16.    DUMP RepeatMasked EST SEQUENCES\n";

 # my $estdump = "/nfs/disk100/humpub/est/txt_db_dump/zebrafish_est/Rmask_Zebrafish_ZF_mu_ESTs_$release.fasta";

 # my $s = system("$scripts/utils/dump_ESTs --db_conf=$conf --library_name=$lib_name --file_name=$estdump --ftp_site_format --repeatmasked");
  my $estdump = "/nfs/disk100/humpub/est/txt_db_dump/zebrafish_est/starting_Seq.fasta";
  my $s = system("$scripts/utils/dump_ESTs --db_conf=$conf --library_name=$lib_name --file_name=$estdump --ftp_site_format");

}
#   17.    DUMP RepeatMasked ACCEPTED EST SEQUENCES

#   prepares masked sequences for clustering using stackpack

if ( $ARGV[0] == 17 ){

  print STDOUT "17.    DUMP RepeatMasked ACCEPTED EST SEQUENCES\n";

  my $estdump = "/nfs/disk100/humpub/est/txt_db_dump/zebrafish_est/Rmask_accepted_Zebrafish_ZF_m
u_ESTs_$release.fasta";
  my $s = system("$scripts/utils/dump_ESTs --db_conf=$conf --library_name=$lib_name --file_name=$estdump --ftp_site_format --repeatmasked_accepted");
}


# STEPS TO DO AFTER STACKPACK CLUSTERING

#   18.    TRANSFER CLUSTERING RESULTS FROM STACKPACK DB TO AN EST DB

if ( $ARGV[0] == 18 ){

  print STDOUT "18.    TRANSFER CLUSTERING RESULTS FROM STACKPACK DB TO AN EST DB\n";
 # my $s = system("$scripts/load_stackPACK_to_EST_DB --db_conf=$conf --library_name=$lib_name --stack_db_conf=$stackdbconf");
  my $s = system("$scripts/load_stackPACK_to_EST_DB --db_conf=$conf --library_name=$lib_name");
}

#   19.    POPULATE consensus_est_count TABLE

if ( $ARGV[0] == 19 ){

  print STDOUT "19.    POPULATE consensus_est_count TABLE of stack est_db\n";
  my $s = system("$scripts/populate_consensus_est_count --db_conf=$conf --library_name=$lib_name");
}


#   20.    INTEGRITY CHECK FOR CLUSTERING RESULTS

if ( $ARGV[0] == 20 ){

  print STDOUT "20.    INTEGRITY CHECK FOR CLUSTERING RESULTS\n";
  my $s = system("$scripts/utils/production_EST_DB_integrity_check --db_conf=$conf --library_name=$lib_name");
}

#   21.    BUILD MISSING CLUSTERS AND CONSENSEI USING Dialign

# This is to repair clusters that StackPACK (Phrep) failed to assemble
# and write results to cluster, consensus, super tables of stack est_db

# (1) This looks for ids in CLUSTER table (these are superclusters)
#     that do not have entry in CONTIG table of the stack clustering db
#     (a supercluster can have > 1 entries in CONTIG table)
# (2) For each ids found in step (1), the dialign program tries to 
#     take all ESTs (in SEQUENCE table) that made up the supercluster (in CLUSTER table)
#     via  $stack_est_db->get_EST_ids_by_SuperCluster_id,
#     ie
#          SELECT id
#          FROM SEQUENCE
#          WHERE CLUSTER_id = 'supercluster_id'

# (3) and creates a single cluster in stack est_db.cluster ( these have stack_contig_id column
#     with the fake name "reconstructed"; the cluster_name looks like ZF_mu_C_34_1)
# (4) Consensus (eg, ZF_mu_34_1_1) are then built from these ESTs

if ( $ARGV[0] == 21 ){

  print STDOUT "21.    BUILD MISSING CLUSTERS AND CONSENSEI USING Dialign\n";
 # my $s = system("$scripts/build_missing_EST_DB_clusters --stack_db_conf=$stackdbconf --library_name=$lib_name --db_conf=$conf");
  my $s = system("$scripts/build_missing_EST_DB_clusters --library_name=$lib_name --db_conf=$conf");
}

#   22.    Run INTEGRITY CHECK FOR CLUSTERING RESULTS after Dialign

if ( $ARGV[0] == 22 ){

  print STDOUT "22.    Rerun INTEGRITY CHECK FOR CLUSTERING RESULTS after Dialign\n";
  my $s = system("$scripts/utils/production_EST_DB_integrity_check --db_conf=$conf --library_name=$lib_name");
}

#   SETUP BLAST SEARCHES

if ( $ARGV[0] == 23 ){

  print STDOUT "23.    SETUP BLAST SEARCHES - WuBLASTX consensei against UNIPROT\n";
  my $s = system("$scripts/setup_EST_DB_BLAST --db_conf=$conf --library_name=$lib_name --search_conf_name=WuBLASTX_uniprot --blast_db=uniprot --blast_type=wublastx --search_type=Consensus --search_description='Translated search of Consensus sequences vs. UNIPROT'");
}

if ( $ARGV[0] == 24 ){

  print STDOUT "24.    SETUP BLAST SEARCHES - WuBLASTN consensei against EMBL/EMBLNEW vertebrate mRNA\n";

  my @dbs = qw(embl_vertrna emnew_vertrna);
  my %desc = ('embl_vertrna'  => 'WuBLASTN searches of Consensus sequences against EMBL vertebrate mRNA',
			  'emnew_vertrna' => 'WuBLASTN searches of Consensus sequences against EMBLNEW vertebrate mRNA'
			 );
  my %conf = ('embl_vertrna'  => 'WuBLASTN_embl_vertrna',
			  'emnew_vertrna' => 'WuBLASTN_emnew_vertrna'
			 );

  foreach my $db ( @dbs ){
	my $sdesc = $desc{$db};
	my $sconf = $conf{$db};

	my $s = system("$scripts/setup_EST_DB_BLAST --db_conf=$conf --library_name=$lib_name --search_conf_name=$sconf --blast_db=$db --blast_type=wublastn --search_type=Consensus --blast_db_loc='/data/blastdb/Ensembl' --search_description=$sdesc");
  }
}

#   SUBMIT BLAST SEARCHES
if ( $ARGV[0] == 25 ){

  print STDOUT "25.    SUBMIT BLAST SEARCHES AGAINST uniprot\n";
print "$scripts";
#  my $s = system("$scripts/submit_EST_DB_jobs --db_conf=$conf --library_name=$lib_name --search_conf_name=WuBLASTX_uniprot --lsf_queue=normal");
 #my $s = system("$scripts/run_EST_DB_jobs --db_conf=$conf --library_name=$lib_name --search_conf_name='WuBLASTX_uniprot' --lsf_queue=normal");
  my $s = system("$scripts/submit_EST_DB_jobs --db_conf=$conf --library_name=$lib_name --search_conf_name=WuBLASTX_uniprot --lsf_queue=normal");
}

if ( $ARGV[0] == 26 ){

  print STDOUT "26.    SUBMIT BLAST SEARCHES AGAINST embl_vertrna\n";
  my $s = system("$scripts/submit_EST_DB_jobs --db_conf=$conf --library_name=$lib_name --search_conf_name=WuBLASTN_embl_vertrna");

}

if ( $ARGV[0] == 27 ){

  print STDOUT "27.    SUBMIT BLAST SEARCHES AGAINST emnew_vertrna\n";
  my $s = system("$scripts/submit_EST_DB_jobs --db_conf=$conf --library_name=$lib_name --search_conf_name='WuBLASTN_emnew_vertrna'");

}

#     POPULATE LIBRARY_SUMMARY TABLES
#     Calculates and stores clustering and general summary 
#     statistics for an EST_DB library, (or all libraries).

#     Tables populated: library_summary
#                       library_cluster_count
#                       cluster_library_cluster_count
#                       library_super_cluster_count
#                       super_cluster_library_super_cluster_count


if ( $ARGV[0] == 28 ){

  print STDOUT "28.    POPULATE LIBRARY SUMMARY TABLES\n";
  my $s = system("$scripts/populate_est_db_summary_tables --db_conf=$conf --library_name=$lib_name");
}


#     POPULATE consensus_protein TABLE

#     Calculates consensus proteins for a given EST_DB library (or all libraries)
#     using ESTScan, populating the consensus_protein table of the database.

#     Both proteins and reconstructed transcripts are stored for each EST, possibly
#     from both strands.

#     Only runs successfully on ecs headnodes, so checks hostname before commencement.


if ( $ARGV[0] == 29 ){

  print STDOUT "29.    POPULATE consensus_protein TABLE\n";
  my $s = system("$scripts/populate_consensus_protein --db_conf=$conf --library_name=$lib_name");
}


#---------------------------------

sub check_status {
  shift == 0 ? print STDOUT "Command successful\n\n" : print STDOUT "command failed\n\n";
}

__END__
