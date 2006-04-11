
### Bio::Otter::Lace::AceDatabase

package Bio::Otter::Lace::AceDatabase;

use strict;
use Carp;
use File::Path 'rmtree';
use Symbol 'gensym';
use Fcntl qw{ O_WRONLY O_CREAT };
use Ace;

use Bio::Otter::Lace::Defaults;
use Bio::Otter::Lace::PipelineDB;
use Bio::Otter::Lace::SatelliteDB;
use Bio::Otter::Lace::PersistentFile;
use Bio::Otter::Converter;

use Bio::EnsEMBL::Pipeline::Analysis;

use Bio::EnsEMBL::Ace::Filter::FPSimilarity;
use Bio::EnsEMBL::Ace::DataFactory;
use Bio::EnsEMBL::Ace::Filter::Gene;
use Bio::EnsEMBL::Ace::Filter::DNA;

use Hum::Ace::MethodCollection;

my $DATASET_HASH_FILE    = '.slice_dataset';
my $LOCK_REGION_XML_FILE = '.lock_region.xml';

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}
sub Client {
    my( $self, $client ) = @_;

    if ($client) {
        $self->{'_Client'} = $client;
    }
    return $self->{'_Client'};
}

sub home {
    my( $self, $home ) = @_;

    if ($home) {
        $self->{'_home'} = $home;
    }
    elsif (! $self->{'_home'}) {
	my $readonly_tag = $self->Client->write_access ? '' : $self->readonly_tag();
	# warn "readonly_tag '$readonly_tag'\n";
        $self->{'_home'} = "/var/tmp/lace.${$}${readonly_tag}";
    }
    return $self->{'_home'};
}
sub readonly_tag{
    my ($self) = @_;
    return '.ro';
}

sub title {
    my( $self, $title ) = @_;

    if ($title) {
        $self->{'_title'} = $title;
    }
    elsif (! $self->{'_title'}) {
        $self->{'_title'} = "lace.$$";
    }
    return $self->{'_title'};
}

sub tar_file {
    my( $self, $tar_file ) = @_;

    if ($tar_file) {
        $self->{'_tar_file'} = $tar_file;
    }
    elsif (! $self->{'_tar_file'}) {
        foreach my $root ($ENV{'OTTER_HOME'}, $ENV{'LACE_LOCAL'}, '/nfs/disk100/humpub/otter_production_main') {
            next unless $root;
            my $file = "$root/lace_acedb.tar";
            if (-e $file) {
                warn "FOUND '$file'\n";
                $self->{'_tar_file'} = $file;
                last;
            }
        }
    }
    return $self->{'_tar_file'};
}

sub tace {
    my( $self, $tace ) = @_;

    if ($tace) {
        $self->{'_tace'} = $tace;
    }
    return $self->{'_tace'} || 'tace';
}

sub error_flag {
    my( $self, $error_flag ) = @_;

    if (defined $error_flag) {
        $self->{'_error_flag'} = $error_flag;
    }
    return ($self->{'_error_flag'} ? 1 : 0);
}
sub add_acefile {
    my( $self, $ace ) = @_;

    my $af = $self->{'_acefile_list'} ||= [];
    push(@$af, $ace);
}

sub list_all_acefiles {
    my( $self ) = @_;

    if (my $af = $self->{'_acefile_list'}) {
        return @$af;
    } else {
        return;
    }
}

sub write_local_blast{
    my ($self, $ss) = @_;

    require Bio::Otter::Lace::Blast;

    my $cl         = $self->Client();
    my $fasta_file = $cl->option_from_array(['local_blast', 'database'])     || return 0;
    my $homol_tag  = $cl->option_from_array(['local_blast', 'homol_tag'])    || 'DNA_homol';
    my $method_tag = $cl->option_from_array(['local_blast', 'method_tag'])   || substr("blast*$fasta_file*",0,39);
    my $color      = $cl->option_from_array(['local_blast', 'method_color']) || 'ORANGE';
    my $logic_name = $cl->option_from_array(['local_blast', 'logic_name'])   || "blast*$fasta_file*";
    my $indicate   = $cl->option_from_array(['local_blast', 'indicate'])     || 'indicate';
    my $parser     = $cl->option_from_array(['local_blast', 'indicate_parser']);
    my $pressdb    = $cl->option_from_array(['local_blast', 'blast_indexer']);
    my $right_pri  = $cl->option_from_array(['local_blast', 'right_priority']);

    return 0 unless -e $fasta_file;

    my $ds = $cl->get_DataSet_by_name($ss->dataset_name());

    my $ana_obj = Bio::EnsEMBL::Pipeline::Analysis->new(-LOGIC_NAME     => $logic_name,
                                                        -INPUT_ID_TYPE  => 'CONTIG',
                                                        -PARAMETERS     => 'cpus=1 E=1e-4 B=100000 Z=500000000 -hitdist=40 -wordmask=seg',
                                                        -PROGRAM        => 'wublastn',
                                                        -gff_source     => 'Est2Genome',
                                                        -gff_feature    => 'similarity',
                                                        -db_file        => $fasta_file,
                                                        );
    my $blast = Bio::Otter::Lace::Blast->new(-analysis        => $ana_obj,
                                             -indicate        => $indicate,
                                             -blast_idx_prog  => $pressdb,
                                             -indicate_parser => $parser);
    $blast->initialise();
    my $pipe_db = Bio::Otter::Lace::PipelineDB::get_DBAdaptor($ds->get_cached_DBAdaptor);
    $pipe_db->assembly_type($ss->name);
    eval{
        $blast->hide_error(0);
        $blast->run_on_selected_CloneSequences($ss, $pipe_db->get_SliceAdaptor);
        my $factory   = Bio::EnsEMBL::Ace::DataFactory->new($cl, $ds);

        my $filter    = Bio::EnsEMBL::Ace::Filter::FPSimilarity->new(-features => $blast->output());
        $filter->analysis_object($ana_obj);
        $filter->homol_tag($homol_tag);
        $filter->method_tag($method_tag);
        $filter->seqfetcher($blast->seqfetcher);
        $filter->needs_method(1);
        $filter->method_colour($color);
        $filter->right_priority($right_pri);
        
        $factory->add_AceFilter($filter);

        my $dir       = $self->home;
        my $blast_ace = "$dir/rawdata/local_blast_search.ace";
        open(my $fh, "> $blast_ace") or die "Can't write to '$blast_ace'";
        $factory->file_handle($fh);

        my $sel = $ss->selected_CloneSequences_as_contig_list();
        foreach my $cs(@$sel){
            my $first_ctg = $cs->[0];
            my $last_ctg = $cs->[$#$cs];

            my $chr = $first_ctg->chromosome->name;  
            my $chr_start = $first_ctg->chr_start;
            my $chr_end = $last_ctg->chr_end;

            warn "fetching slice $chr $chr_start $chr_end \n";
            my $slice = $pipe_db->get_SliceAdaptor->fetch_by_chr_start_end($chr, $chr_start, $chr_end);

            ## I think we shouldn't let AceDatabase see the tiling path (lg4)
            ## This is a kind of information that will be available to DataFactory.
            ##
            # Check we got a slice
            my $tp = $slice->get_tiling_path;
            if(@$tp){
                foreach my $tile(@$tp){
                    warn "Getting " . $tile->component_Seq->name() . "\n";
                }
             }else{
                 warn "Didn't get slice\n";
             }

            $factory->ace_data_from_slice($slice);
        }

        $factory->drop_file_handle;
        close $fh;
        $self->add_acefile($blast_ace);

    };
    Bio::Otter::Lace::SatelliteDB::disconnect_DBAdaptor($pipe_db) if $pipe_db;
    if($@){
        warn "Blast failed!\n$@\n";
    }else{
        warn "Blast completed succesfully\n";
    }

}

sub write_otter_acefile {
    my( $self, $ss ) = @_;

    my $dir = $self->home;
    my $otter_ace = "$dir/rawdata/otter.ace";
    my $fh = gensym();
    open $fh, "> $otter_ace" or die "Can't write to '$otter_ace'";
    if ($ss) {
        print $fh $self->fetch_otter_ace_for_SequenceSet($ss);
    } else {
        print $fh $self->fetch_otter_ace;
    }
    close $fh or confess "Error writing to '$otter_ace' : $!";
    $self->add_acefile($otter_ace);
    $self->save_slice_dataset_hash;
}

sub fetch_otter_ace {
    my( $self ) = @_;

    my $client = $self->Client or confess "No otter Client attached";

    my $ace = '';
    my $selected_count = 0;
    foreach my $dsObj ($client->get_all_DataSets) {
	$dsObj->{'_Client'}=$self->Client;
        my $ss_list = $dsObj->get_all_SequenceSets;
        foreach my $ss (@$ss_list ) {
            if (my $ctg_list = $ss->selected_CloneSequences_as_contig_list) {
                $dsObj->selected_SequenceSet($ss);
                $ace .= $self->ace_from_contig_list($ctg_list, $dsObj);
                foreach my $ctg (@$ctg_list) {
                    warn "$ctg\n";
                    $selected_count += @$ctg;
                }
            }
        }
    }

    if ($selected_count) {
        return $ace;
    } else {
        return;
    }
}

sub fetch_otter_ace_for_SequenceSet {
    my( $self, $ss ) = @_;

    my $client = $self->Client
        or confess "No otter client attached";
    my $dsObj = $client->get_DataSet_by_name($ss->dataset_name);
    confess "Can't find DataSet that SequenceSet belongs to"
        unless $dsObj;

    $dsObj->selected_SequenceSet($ss);
    my $ctg_list = $ss->selected_CloneSequences_as_contig_list
        or confess "No CloneSequences selected";
    return $self->ace_from_contig_list($ctg_list, $dsObj);
}

# this now just gets the ace via http/xml -> xml_to_otter -> otter_to_ace

sub ace_from_contig_list {
    my( $self, $ctg_list, $dsObj ) = @_;

    my $client = $self->Client or confess "No otter Client attached";
    my $ace = '';

    foreach my $ctg (@$ctg_list) {
        my $xml        = Bio::Otter::Lace::TempFile->new;
        $xml->name('lace.xml');
        my $write      = $xml->write_file_handle;
        my $xml_string = $client->get_xml_for_contig_from_Dataset($ctg, $dsObj);

        print $write $xml_string ;
        # If we're here we now have all the locks!!!

        ### Nasty that genes and slice arguments are in
        ### different order in these two subroutines
        my ($genes, $slice, $sequence, $tiles, $feature_set, $assembly_tag_set) =
            Bio::Otter::Converter::XML_to_otter($xml->read_file_handle);

        $ace .= Bio::Otter::Converter::otter_to_ace($slice, $genes, $tiles, $sequence, $feature_set, $assembly_tag_set);
        # We need to record which dataset each slice came
        # from so that we know where to save it back to.
        # this gets done in the write_lock_xml so only need to do it here
        # if we haven't got write access.
#        $self->save_slice_dataset($slice->display_id, $dsObj->name) unless $write_access;
    }

    return $ace;
}

sub write_lock_xml{
    my ($self, $xml, $ds_name) = @_;

    if($xml && $ds_name){
        my $lock_xml = Bio::Otter::Lace::PersistentFile->new();
        $lock_xml->root($self->home);
        $lock_xml->name($LOCK_REGION_XML_FILE);
        my $write = $lock_xml->write_file_handle();

        print $write $xml;

        my $read = $lock_xml->read_file_handle();
        my ($genes,$slice,$seqstr,$tiles) = Bio::Otter::Converter::XML_to_otter($read);
        my $slice_name = $slice->display_id();
        $self->save_slice_dataset($slice_name, $ds_name);
        $lock_xml->mv(".${slice_name}${ds_name}${LOCK_REGION_XML_FILE}");
    }
}

sub save_slice_dataset {
    my( $self, $slice_name, $ds_name ) = @_;

    if ($slice_name and $ds_name) {
        print STDERR "Saving '$slice_name' in '$ds_name'\n";
        $self->{'_slice_name_dataset'}->{$ds_name} ||= [];
        push(@{$self->{'_slice_name_dataset'}->{$ds_name}}, $slice_name);
    }
}

sub slice_dataset_hash {
    my $self = shift;
    confess "slice_dataset_hash method is read-only" if @_;

    my $h = $self->{'_slice_name_dataset'};
    unless ($h) {
        #warn "Creating empty hash";
        $h = $self->{'_slice_name_dataset'} = {};
    }
    return $h;
}

# Makes hash persistent for "lace -recover"
# (Could store in Dataset_name tag in database?)
sub save_slice_dataset_hash {
    my( $self ) = @_;

    my $h    = $self->slice_dataset_hash;

    my $hash_file = Bio::Otter::Lace::PersistentFile->new;
    $hash_file->root($self->home);
    $hash_file->name($DATASET_HASH_FILE);
    my $write = $hash_file->write_file_handle;

    while (my ($ds_name, $slices) = each %$h) {
        $ds_name =~ s/\t/\\t/g;      # Escape tab characterts in dataset name (likely ?)
        map { s/\t/\\t/g } @$slices; # Escape tab characterts in slice   name (v. unlikely)
        print $write "$ds_name\t@$slices\n";
    }
}

sub recover_slice_dataset_hash {
    my( $self ) = @_;

    my $cl   = $self->Client or confess "No Otter Client attached";
    my $h    = $self->slice_dataset_hash;

    my $hash_file = Bio::Otter::Lace::PersistentFile->new;
    $hash_file->root($self->home);
    $hash_file->name($DATASET_HASH_FILE);
    my $read = $hash_file->read_file_handle;

    while (<$read>) {
        chomp;
        my ($ds_name, @slices) = split(/\t/, $_);
        $ds_name =~ s/\\t/\t/g;     # Unscape tab characterts in dataset name (v. unlikely)
        map { s/\\t/\t/g } @slices; # Unscape tab characterts in slice   name (v. unlikely)
        $h->{$ds_name} = \@slices;
    }
}


sub save_all_slices {
    my( $self ) = @_;

    #warn "SAVING ALL SLICES";
    $self->error_flag(1);

    # Make sure we don't have a stale database handle
    $self->drop_aceperl_db_handle;

    my $sd_h = $self->slice_dataset_hash;
    #warn "HASH = '$sd_h' has ", scalar(keys %$sd_h), " elements";
    ### This call to each was failing to return anything
    ### the second time it was called, proabably because
    ### we were exiting each the first with an exception
    ### so the iterator didn't get reset.
    #while (my ($name, $ds) = each %$sd_h) {
    my $ace = '';
    foreach my $ds_name (keys %$sd_h) {
        my $slices = $sd_h->{$ds_name};
        foreach my $slice(@$slices){
            warn "SAVING SLICE '$slice' WITH DATASET '$ds_name' to the Otter Server\n";
            $ace .= $self->save_otter_slice($slice, $ds_name);
        }
    }
    $self->error_flag(0);

    return \$ace;
}

sub save_otter_slice {
    my( $self, $name, $dataset_name ) = @_;

    $self->error_flag(1);
    confess "Missing slice name argument"   unless $name;
    confess "Missing DatsSet argument"      unless $dataset_name;

    my $ace    = $self->aceperl_db_handle;
    my $client = $self->Client or confess "No Client attached";

    # Get the Assembly object ...
    $ace->raw_query(qq{find Assembly "$name"});
    my $ace_txt = $ace->raw_query('show -a');

    # ... its SubSequences ...
    $ace->raw_query('query follow SubSequence where ! CDS_predicted_by');
    $ace_txt .= $ace->raw_query('show -a');

    # ... and all the Loci attached to the SubSequences.
    $ace->raw_query('Follow Locus');
    $ace_txt .= $ace->raw_query('show -a');

    # List of people for Authors
    $ace->raw_query(qq{find Person *});
    $ace_txt .= $ace->raw_query('show -a');

    # Then get the information for the TilePath
    $ace->raw_query(qq{find Assembly "$name"});
    $ace->raw_query('Follow AGP_Fragment');
    # Do show -a on a restricted list of tags
    foreach my $tag (qw{
        Otter
        DB_info
        Annotation
        })
    {
        $ace_txt .= $ace->raw_query("show -a $tag");
    }

    # Cleanup text
    $ace_txt =~ s/\0//g;            # Remove nulls
    $ace_txt =~ s{^\s*//.+}{\n}mg;  # Strip comments

    if($self->Client->debug){
        my $debug_file = Bio::Otter::Lace::PersistentFile->new();
        $debug_file->name("otter-debug.$$.save.ace");
        my $fh = $debug_file->write_file_handle();
        print $fh $ace_txt;
        close $fh;
    }else{
        warn "Debug switch is false\n";
    }
    
    my $ace_file = Bio::Otter::Lace::TempFile->new;
    $ace_file->name('lace_edited.ace');
    my $write = $ace_file->write_file_handle;
    print $write $ace_txt;
    my $xml = Bio::Otter::Converter::ace_to_XML($ace_file->read_file_handle);
    close $write;

    if($self->Client->debug){
        my $debug_file = Bio::Otter::Lace::PersistentFile->new();
        $debug_file->name("otter-debug.$$.save.xml");
        my $fh = $debug_file->write_file_handle();
        print $fh $xml;
        close $fh;
    }else{
        warn "Debug switch is false\n";
    }

    my $success = $client->save_otter_xml($xml, $dataset_name);

    $self->error_flag($success ? 0 : 1); # not sure this is correct (check out).

    return $self->update_with_stable_ids($success);
}


sub update_with_stable_ids{
    my ($self, $xml, $anything_else) = @_;
    return unless $xml;

    $self->error_flag(1);
    ## get an aceperl handle
    my $ace = $self->aceperl_db_handle();

    ## write the temp/persisent file
    my $fileObj;
    if($self->Client->debug){
        $fileObj = Bio::Otter::Lace::PersistentFile->new();
        $fileObj->name("otter_response_$$.xml");
        $fileObj->rm();
    }else{
        $fileObj = Bio::Otter::Lace::TempFile->new;
    }

    my $write = $fileObj->write_file_handle();
    print $write (ref($xml) eq 'SCALAR' ? ${$xml} : $xml);

    my $read  = $fileObj->read_file_handle();

    ## convert the xml returned from the server into otter stuff
    my ($genes, $slice, $seqstr, $tiles) = Bio::Otter::Converter::XML_to_otter($read);

    ## this should only contain the CHANGED genes.

    ### Should this test @$genes?
    unless($genes){
        warn "No genes changed\n";
        return undef;
    }

    warn "Some genes changed\n";
    ## need to do genes, transcripts, translations and exons

    my $ace_txt = Bio::Otter::Converter::ace_transcripts_locus_people($genes, $slice);

    ## everything went ok so error_flag = 0;
    $self->error_flag(0);

    return $ace_txt;
}

sub unlock_all_slices {
    my( $self ) = @_;

    my $sd_h = $self->slice_dataset_hash;

    # if the unlock otter slice goes wrong half way through
    # the recover will try to unlock the clones again.
    foreach my $ds_name (keys %$sd_h) {
        my $slices = $sd_h->{$ds_name};
        foreach my $slice(splice(@$slices)){
            $self->unlock_otter_slice($slice, $ds_name);
        }
    }
}

sub unlock_otter_slice{
    my( $self, $slice_name, $dataset_name ) = @_;

    confess "Missing slice name argument"   unless $slice_name;
    confess "Missing DatsSet name argument" unless $dataset_name;

    my $client   = $self->Client or confess "No Client attached";

    my $xml_file = Bio::Otter::Lace::PersistentFile->new;
    $xml_file->root($self->home);
    $xml_file->name(".${slice_name}${dataset_name}${LOCK_REGION_XML_FILE}");
    return unless -e $xml_file->full_name();
    my $xml = '';
    my $read = $xml_file->read_file_handle;
    while(<$read>){
        $xml .= $_;
    }
    return unless $xml;

    return $client->unlock_otter_xml($xml, $dataset_name);
}

sub aceperl_db_handle {
    my( $self ) = @_;

    my( $dbh );
    unless ($dbh = $self->{'_aceperl_db_handle'}) {
        my $home = $self->home;
        my $tace = $self->tace;

        # Check for ACEDB.wrm, or tace will hang waiting for
        # an answer to the "initialize database?" question.
        my $init_file = "$home/database/ACEDB.wrm";
        unless (-e $init_file) {
            confess "The file '$init_file' is missing - database has not been initialized";
        }

        $dbh = $self->{'_aceperl_db_handle'}
            = Ace->connect(-PATH => $home, -PROGRAM => $tace)
                or confess "Can't connect to database in '$home': ", Ace->error;
    }

    return $dbh;
}

sub drop_aceperl_db_handle {
    my( $self ) = @_;

    $self->{'_aceperl_db_handle'} = undef;
}

sub make_database_directory {
    my( $self ) = @_;

    my $home = $self->home;
    my $tar  = $self->tar_file or confess "tar_file not set";
    mkdir($home, 0777) or die "Can't mkdir('$home') : $!\n";

    my $tar_command = "cd $home ; tar xf $tar";
    if (system($tar_command) != 0) {
        $self->error_flag(1);
        confess "Error running '$tar_command' exit($?)";
    }

    # rawdata used to be in tar file, but no longer because
    # it doesn't (yet) contain any files.
    my $rawdata = "$home/rawdata";
    mkdir($rawdata, 0777);
    die "Can't mkdir('$rawdata') : $!\n" unless -d $rawdata;

    $self->make_passwd_wrm;
    $self->edit_displays_wrm;
}

sub write_methods_acefile {
    my( $self ) = @_;
    
    my $home = $self->home;
    my $methods_file = "$home/rawdata/methods.ace";
    my $collect = $self->get_default_MethodCollection;
    $collect->process_for_otterlace;
    $collect->write_to_file($methods_file);
    $self->add_acefile($methods_file);
}

sub make_passwd_wrm {
    my( $self ) = @_;

    my $passWrm = $self->home . '/wspec/passwd.wrm';
    my ($prog) = $0 =~ m{([^/]+)$};
    my $real_name      = ( getpwuid($<) )[0];
    my $effective_name = ( getpwuid($>) )[0];

    my $fh = gensym();
    sysopen($fh, $passWrm, O_CREAT | O_WRONLY, 0644)
        or confess "Can't write to '$passWrm' : $!";
    print $fh "// PASSWD.wrm generated by $prog\n\n";

    # acedb looks at the real user ID, but some
    # versions of the code seem to behave differently
    if ( $real_name ne $effective_name ) {
        print $fh "root\n\n$real_name\n\n$effective_name\n\n";
    }
    else {
        print $fh "root\n\n$real_name\n\n";
    }

    close $fh;    # Must close to ensure buffer is flushed into file
}

sub edit_displays_wrm {
    my( $self ) = @_;

    my $home  = $self->home;
    my $title = $self->title;

    my $displays = "$home/wspec/displays.wrm";

    my $disp_in = gensym();
    open $disp_in, $displays or confess "Can't read '$displays' : $!";
    my @disp = <$disp_in>;
    close $disp_in;

    foreach (@disp) {
        next unless /^_DDtMain/;

        # Add our title onto the Main window
        s/\s-t\s*"[^"]+/ -t "$title/i;  # " sorry just to fix emacs syntax highlight
        last;
    }

    my $disp_out = gensym();
    open $disp_out, "> $displays" or confess "Can't write to '$displays' : $!";
    print $disp_out @disp;
    close $disp_out;
}

sub add_misc_acefile {
    my( $self ) = @_;
    
    return unless my $file = Bio::Otter::Lace::Defaults::misc_acefile();
    
    confess "No such file '$file'" unless -e $file;
    $self->add_acefile($file);
}

sub initialize_database {
    my( $self ) = @_;

    my $home = $self->home;
    my $tace = $self->tace;
    my @parse_commands = map "parse $_\n",
        $self->list_all_acefiles;

    my $parse_log = "$home/init_parse.log";
    my $pipe = "| $tace $home > $parse_log";

    my $pipe_fh = gensym();
    open $pipe_fh, $pipe
        or die "Can't open pipe '$pipe' : $!";
    # Say "yes" to "initalize database?" question.
    print $pipe_fh "y\n";
    foreach my $com (@parse_commands) {
        print $pipe_fh $com;
    }
    close $pipe_fh or die "Error initializing database exit($?)\n";

    my $fh = gensym();
    open $fh, $parse_log or die "Can't open '$parse_log' : $!";
    my $file_log = '';
    my $in_parse = 0;
    my $errors = 0;
    while (<$fh>) {
        if (/parsing/i) {
            $file_log = "  $_";
            $in_parse = 1;
        }

        if (/(\d+) (errors|parse failed)/i) {
            if ($1) {
                warn "\nParse error detected:\n$file_log  $_\n";
                $errors++;
            }
        }
        elsif (/Sorry/) {
            warn "Apology detected:\n$file_log  $_\n";
            $errors++;
        }
        elsif ($in_parse) {
            $file_log .= "  $_";
        }
    }
    close $fh;

    confess "Error initializing database\n" if $errors;
    return 1;
}

sub write_pipeline_data {
    my( $self, $ss, $ace_file ) = @_;

    my $dataset = $self->Client->get_DataSet_by_name($ss->dataset_name);
    $dataset->selected_SequenceSet($ss);    # Not necessary?
    my $ens_db = $dataset->get_cached_DBAdaptor();
    my $fetch_pipe = Bio::Otter::Lace::Defaults::fetch_pipeline_switch();
    my $pipehead = Bio::Otter::Lace::Defaults::pipehead();
    if ($fetch_pipe and ! $pipehead) {
	    my $pipe_db = Bio::Otter::Lace::PipelineDB::get_DBAdaptor($ens_db);
	    $ens_db = $pipe_db;
        #$pipe_db->dnadb($ens_db->dnadb);
    }

    $ens_db->assembly_type($ss->name);
    my $factory = $self->{'_pipeline_data_factory'} ||= $self->make_AceDataFactory($ens_db, $dataset);

    # create file for output and add it to the acedb object
    $ace_file ||= $self->home . "/rawdata/pipeline.ace";
    my $fh;
    if(ref($ace_file) eq 'GLOB'){
        $fh = $ace_file;
    }else{ 
        $fh = gensym();
        $self->add_acefile($ace_file);
        open $fh, "> $ace_file" or confess "Can't write to '$ace_file' : $!";
    }
    $factory->file_handle($fh);

    my $slice_adaptor = $ens_db->get_SliceAdaptor();

    # note: the next line returns a 2 dimensional array (not a one dimensional array)
    # each subarray contains a list of clones that are together on the golden path
    my $sel = $ss->selected_CloneSequences_as_contig_list ;
    foreach my $cs (@$sel) {
        my( $chr, $chr_start, $chr_end ) = $self->Client->chr_start_end_from_contig($cs);
        my $slice = $slice_adaptor->fetch_by_chr_start_end($chr, $chr_start, $chr_end);

        ## I think we shouldn't let AceDatabase see the tiling path (lg4)
        ## This is a kind of information that will be available to DataFactory.
        ##
        # Check we got a slice
        my $tp = $slice->get_tiling_path;
        my $type = $slice->assembly_type;
        #warn "assembly type = $type";
        if (@$tp) {
            foreach my $tile (@$tp) {
                print STDERR "contig: ", $tile->component_Seq->name, "\n";
            }
        } else {
            warn "No components in tiling path";
        }

        $factory->ace_data_from_slice($slice);
    }
    $factory->drop_file_handle;
    close $fh;

    if ($fetch_pipe and ! $pipehead) {
        Bio::Otter::Lace::SatelliteDB::disconnect_DBAdaptor($ens_db);
    }
}

sub make_AceDataFactory {
    my( $self, $ens_db, $dataset ) = @_;

    my $species = $dataset->name();
    warn "This species is '$species'\n";

    # create new datafactory object - contains all ace filters and produces the data from these
    my $factory = Bio::EnsEMBL::Ace::DataFactory->new($self->Client(), $dataset);
    # $factory->add_all_Filters($ensdb);

    ##----------code to add all of the ace filters to data factory-----------------------------------

    my $fetch_pipe = Bio::Otter::Lace::Defaults::fetch_pipeline_switch();
    my $debug = $self->Client->debug();
    
    my $logic_to_load =
      $self->Client->option_from_array([ $species, 'use_filters' ]);
    my $module_options =
      $self->Client->option_from_array([ $species, 'filter' ]);

    my @analysis_names;
    if ($fetch_pipe) {
        @analysis_names = grep $logic_to_load->{$_}, keys %$logic_to_load;
        push @analysis_names, 'submitcontig';
    } else {
        push @analysis_names, 'otter'; # or shall we drop this distinction at all?
    }

    ### This is kind of silly because we don't acutally
    ### need the analysis object for the DNA filter.
    #if ($ana_adaptor->fetch_by_logic_name('submitcontig')) {
    #    push(@analysis_names, 'submitcontig');
    #} else {
    #    push(@analysis_names, 'otter');
    #}

    my $collect = $self->get_default_MethodCollection;

    foreach my $logic_name (@analysis_names) {

        my $ana_adaptor; # maybe we won't need it after all

        my $param_ref = $module_options->{$logic_name}
            or die "No parameters for '$logic_name'";

        # Take a copy of the parameters so that we can delete from it.
        my %param = %$param_ref;

        # class successfully required already.
        my $class = delete $param{'module'}
          or confess "Module class for '$logic_name' missing from config";

        # Load the filter module
        my $file = "$class.pm";
        $file =~ s{::}{/}g;
        eval { require $file };
        if ($@) {
            die "Error attempting to load filter module '$file'\n$@";
        }

        my $filt = $class->new;

        # check there is an analysis
        if ($filt->isa('Bio::EnsEMBL::Ace::Otter_Filter')) {
            # Otter_Filters do not need the analysis_object anymore
            $filt->analysis_name($logic_name);
        } else {
            $ana_adaptor ||= $ens_db->get_AnalysisAdaptor; # still, some old filters do need it
            my $ana = $ana_adaptor->fetch_by_logic_name($logic_name)
                or confess "No analysis object for '$logic_name' in database needed for '$filt'";
            $filt->analysis_object($ana);
        }

        # Options in the config file are methods on filter objects:
        while (my ($option, $value) = each %param) {
            #warn "setting '$option' to '$value'\n";
            $filt->$option($value);
        }

        # does the filter need a method?
        my $req = $filt->required_ace_method_names;
        foreach my $tag (@$req) {
            #print STDERR "Trying to get a method Object with tag '$tag' ... filter '$class' ... ";
            my $methObj = $collect->get_Method_by_name($tag);
            #print STDERR $methObj ? "found one\n" : "find failed\n";
            $filt->add_method_object($methObj);    # or some other place
        }

        # add the filter to the factory
        $factory->add_AceFilter($filt);
    }

    return $factory;
}


#  creates a data factory and adds all the appropriate filters to
#  it. It then produces a slice from the ensembl db (using the
#  $dataset coords) and produces output based on that slice in
#  ensembl.ace
sub write_ensembl_data {
    my ($self, $ss) = @_;

    my $dataset         = $self->Client->get_DataSet_by_name($ss->dataset_name);
    my $species         = $dataset->species();
    my $ensembl_sources =
      $self->Client->option_from_array([ $species, 'ensembl_sources' ]);

    # Analysis logic names are taken from a comma separated list in
    while (my ($key, $logic_string) = each %$ensembl_sources) {
        warn "Fetching genes from '$key' with analysis names ($logic_string)\n";
        $self->write_ensembl_data_for_key($ss, $key, $logic_string)
    }
}

sub make_ensembl_gene_DataFactory {
    my ($self, $dataset, $ens_db, $logic_string) = @_;

    my $ana_adaptor = $ens_db->get_AnalysisAdaptor;
    my @analysis_objects;
    foreach my $logic_name (split /,/, $logic_string) {
        if (my $ana_obj = $ana_adaptor->fetch_by_logic_name($logic_name)) {
            push(@analysis_objects, $ana_obj);
        }
    }
    
    return unless @analysis_objects;

    my $factory = Bio::EnsEMBL::Ace::DataFactory->new($self->Client, $dataset);
    # Add a filter to the factory for each type of gene that we have
    foreach my $ana (@analysis_objects) {
        my $ens_filter = Bio::EnsEMBL::Ace::Filter::Gene->new;
        $ens_filter->url_string(
'http\:\/\/www.ensembl.org\/Homo_sapiens\/contigview?highlight=%s&chr=%s&vc_start=%s&vc_end=%s'
        );
        $ens_filter->analysis_object($ana);
        $factory->add_AceFilter($ens_filter);
    }
    return $factory;
}

sub write_ensembl_data_for_key {
    my ($self, $ss, $key, $logic_string) = @_;

    my $debug_flag = 0;

    my $dataset = $self->Client->get_DataSet_by_name($ss->dataset_name);
    $dataset->selected_SequenceSet($ss);    # Not necessary?
    my $ens_db =
      Bio::Otter::Lace::SatelliteDB::get_DBAdaptor(
        $dataset->get_cached_DBAdaptor, $key)
      or return;

    # Get a factory, or return (which happens when there are no analyses
    # of the types listed in $logic_string).
    my $factory = $self->{'_ensembl_gene_data_factory'}{$logic_string} ||=
      $self->make_ensembl_gene_DataFactory($dataset, $ens_db, $logic_string)
      || return;

    # create file for output and add it to the acedb object
    my $ace_file = $self->home . "/rawdata/$key.ace";
    my $fh       = gensym();
    open $fh, "> $ace_file" or confess "Can't write to '$ace_file' : $!";
    $factory->file_handle($fh);
    $self->add_acefile($ace_file);

    my $type = $ens_db->assembly_type;

    # later on will have to get chromsome names...not proper way to do it
    my $ch = get_all_LaceChromosomes($ens_db);

    my $slice_adaptor = $ens_db->get_SliceAdaptor();

    my $sel = $ss->selected_CloneSequences_as_contig_list;

    # unlike sanger (pipeline) databases, where data is clone based,
    # in this case we need to deal with slice as a whole

    # Slightly smarter than rejecting entire slice if anything
    # different.  Is able to build a subslice if beginning or end
    # is incorrect, but can't build multiple subslices (all kinds
    # of duplicate partial gene problems could result in such
    # cases).

    # Since locally the agp could be correct, but globally wrong
    # has to deal with clone order walking in the wrong direction

    # Various patalogical cases are not dealt with optimally.  If
    # A matches; B doesn't but C, D, E and F match, will make a
    # subslice out of A.  Could be handelled, but would require a
    # double pass.

    foreach my $cs (@$sel) {

        my $otter_slice_name;
        {

            # need to get name of slice in otter space (fetch from ensembl
            # will be in a different coordinate space, but because of
            # checks they are guarenteed to be equivalent)

            my $first_ctg = $cs->[0];
            my $last_ctg  = $cs->[$#$cs];

            my $chr       = $first_ctg->chromosome->name;
            my $chr_start = $first_ctg->chr_start;
            my $chr_end   = $last_ctg->chr_end;
            $otter_slice_name = "$chr.$chr_start-$chr_end";
        }

        # check if agp of this DB is in sync for the selected clones
        # dump if in sync, else skip
        my $off   = 0;
        my $first = -1;
        my $first_dir;
        my $last;
        my $last_edge;
        my $slice_start;
        my $slice_end;
        my $fail;
        my $chr;

        for (my $i = 0 ; $i < @$cs ; $i++) {
            my $ctg = $cs->[$i];

            my $ens_ctg_set =
              get_LaceCloneSequence_by_sv($ens_db, $ch, $ctg->accession,
                $ctg->sv, $type, $debug_flag);
            my $pass = 0;

            # should get only one match (present, but not unfinished)
            if (scalar(@$ens_ctg_set) == 1) {
                my $ens_ctg = $ens_ctg_set->[0];

                # check if same part of contig is part of external agp
                if (   $ens_ctg->contig_start == $ctg->contig_start
                    && $ens_ctg->contig_end == $ctg->contig_end)
                {
                    print "DEBUG: same contig used\n" if $debug_flag;

                    # if first clone, save; else check order is still ok
                    if ($first > -1) {
                        $fail = 1;

                        # check sequential
                        if ($i = $last + 1) {

                            # check consistent direction
                            my $this_dir = -1;
                            if ($ens_ctg->contig_strand == $ctg->contig_strand)
                            {
                                $this_dir = 1;
                            }
                            if ($first_dir == $this_dir) {

                                # check agp consecutive
                                if (   $first_dir == 1
                                    && $ens_ctg->chr_start == $last_edge + 1)
                                {
                                    $last      = $i;
                                    $last_edge = $ens_ctg->chr_end;
                                    $slice_end = $ens_ctg->chr_end;
                                    $fail      = 0;
                                }
                                elsif ($first_dir == -1
                                    && $ens_ctg->chr_end == $last_edge - 1)
                                {

                                    # -ve direction not handled...so
                                    confess "ERR: should never get here!!";
                                }
                            }
                        }
                    }
                    else {
                        print "DEBUG: saved first $i\n" if $debug_flag;
                        $first = $i;
                        $last  = $i;
                        $chr   = $ens_ctg->chromosome->name;
                        if ($ens_ctg->contig_strand == $ctg->contig_strand) {

                            # same direction
                            $last_edge   = $ens_ctg->chr_end;
                            $slice_start = $ens_ctg->chr_start;
                            $slice_end   = $ens_ctg->chr_end;
                            $first_dir   = 1;
                        }
                        else {
                            $last_edge   = $ens_ctg->chr_start;
                            $slice_start = $ens_ctg->chr_end;
                            $slice_end   = $ens_ctg->chr_start;
                            $first_dir   = -1;

                            # reverse direction

                            # FIXME temporary:
                            print "WARN: agp is in reverse direction";
                            print " - not currently handled\n";
                            $first = -1;

                        }
                    }
                }
            }

            # right now, if $first not set for $i=0 can't continue
            if ($i == 0 && $first == -1) { $fail = 1; }

       # once started a slice with first, if fail then no point checking further
            last if $fail;
        }

        # if something was saved
        if ($first > -1) {
            print "DEBUG: Fetching slice $first:$slice_start-$last:$slice_end\n"
              if $debug_flag;
            my $slice =
              $slice_adaptor->fetch_by_chr_start_end($chr, $slice_start,
                $slice_end);
            $slice->name($otter_slice_name);
            $factory->ace_data_from_slice($slice);
        }
    }
    close $fh;

    # Disconnect Ensembl DBAdaptor
    Bio::Otter::Lace::SatelliteDB::disconnect_DBAdaptor($ens_db);
}


# look for contigs for this sv
sub get_LaceCloneSequence_by_sv {
    my ($dba, $ch, $acc, $sv, $type, $debug_flag) = @_;

    print "DEBUG: checking $acc,$sv,$type\n" if $debug_flag;

    my %id_chr = map { $_->chromosome_id, $_ } @$ch;
    my $sth = $dba->prepare(q{
        SELECT a.chromosome_id
          , a.chr_start
          , a.chr_end
          , a.contig_start
          , a.contig_end
          , a.contig_ori
        FROM assembly a
          , clone cl
          , contig c
        WHERE cl.embl_acc= ?
          AND cl.embl_version= ?
          AND cl.clone_id=c.clone_id
          AND c.contig_id=a.contig_id
          AND a.type = ?
        });
    $sth->execute($acc, $sv, $type);

    my ($chr_id, $chr_start, $chr_end,
        $contig_start, $contig_end, $strand);
    $sth->bind_columns(
        \$chr_id, \$chr_start, \$chr_end,
        \$contig_start, \$contig_end, \$strand);

    my $cs = [];
    while ($sth->fetch) {
        my $cl = Bio::Otter::Lace::CloneSequence->new;

        #$cl->accession($acc);
        #$cl->sv($sv);
        #$cl->length($ctg_length);
        $cl->chromosome($id_chr{$chr_id});
        $cl->chr_start($chr_start);
        $cl->chr_end($chr_end);
        $cl->contig_start($contig_start);
        $cl->contig_end($contig_end);
        $cl->contig_strand($strand);

        #$cl->contig_name($ctg_name);
        push(@$cs, $cl);
        print "DEBUG: $chr_start-$chr_end; $contig_start-$contig_end\n"
          if $debug_flag;
    }
    return $cs;
}


sub get_all_LaceChromosomes {
    my($dba)=@_;
    my($ch);
    my $sth = $dba->prepare(q{
	SELECT chromosome_id
	    , name
	    , length
	FROM chromosome
	});
    $sth->execute;
    my( $chr_id, $name, $length );
    $sth->bind_columns(\$chr_id, \$name, \$length);
        
    while ($sth->fetch) {
	my $chr = Bio::Otter::Lace::Chromosome->new;
	$chr->chromosome_id($chr_id);
	$chr->name($name);
	$chr->length($length);
	push(@$ch, $chr);
    }
    return($ch);
}

{
    my $default_collection = undef;
    
    sub get_default_MethodCollection {
        my( $self ) = @_;
        
        unless ($default_collection) {
            # This file should be the default:
            my $method_file = $ENV{'OTTER_HOME'} . "/methods.ace";

            $default_collection = Hum::Ace::MethodCollection->new_from_file($method_file);
        }
        return $default_collection;
    }
}

sub DESTROY {
    my( $self ) = @_;
    
    # warn "Debug - leaving database intact"; return;
    
    my $home = $self->home;
    print STDERR "DESTROY has been called for AceDatabase.pm with home $home\n";
    if ($self->error_flag) {
        warn "Not cleaning up '$home' because error flag is set\n";
        return;
    }
    my $client = $self->Client;
    eval{
        if($client){
            $self->unlock_all_slices();# if $client->write_access;
        }
    };
    rmtree($home) unless $@;
}



1;
