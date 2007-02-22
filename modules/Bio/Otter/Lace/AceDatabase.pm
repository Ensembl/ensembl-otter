
### Bio::Otter::Lace::AceDatabase

package Bio::Otter::Lace::AceDatabase;

use strict;
use Carp;
use File::Path 'rmtree';
use Symbol 'gensym';
use Fcntl qw{ O_WRONLY O_CREAT };

use Bio::Otter::Converter;
use Bio::Otter::Lace::Defaults;
use Bio::Otter::Lace::PipelineDB;
use Bio::Otter::Lace::SatelliteDB;
use Bio::Otter::Lace::PersistentFile;
use Bio::Otter::Lace::Blast;
use Bio::Otter::Lace::Slice; # a new kind of Slice that knows how to get pipeline data

use Bio::EnsEMBL::Ace::DataFactory;

use Hum::Ace::LocalServer;
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

sub write_access {
    my( $self, $write_access ) = @_;

    if(defined($write_access)) {
        $self->{'_write_access'} = $write_access;
    }
    return $self->{'_write_access'};
}

sub home {
    my( $self, $home, $write_flag ) = @_;

    if ($home) {
        $self->{'_home'} = $home;
    } elsif (! $self->{'_home'}) {
        if(!defined($write_flag)) { # if it's defined, follow it, ignore the client
            $write_flag = $self->Client->write_access();
        }
        my $readonly_tag = $write_flag ? '' : $self->readonly_tag();
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
        my $file = "$ENV{OTTER_HOME}/lace_acedb.tar";
        if (-e $file) {
            warn "FOUND '$file'\n";
            $self->{'_tar_file'} = $file;
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

sub MethodCollection {
    my ($self, $coll) = @_;
    
    if ($coll) {
        $self->{'_MethodCollection'} = $coll;
    }
    return $self->{'_MethodCollection'};
}

sub get_default_MethodCollection {
    my( $self ) = @_;

    # This file should be the default:
    my $method_file = $ENV{'OTTER_HOME'} . "/methods.ace";

    return Hum::Ace::MethodCollection->new_from_file($method_file);
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

sub empty_acefile_list {
    my( $self ) = @_;

    $self->{'_acefile_list'} = undef;
}

sub init_AceDatabase {
    my( $self, $ss ) = @_;
    
    $self->MethodCollection($self->get_default_MethodCollection);

    $self->add_misc_acefile;
    $self->write_otter_acefile($ss);
    $self->write_pipeline_data($ss);
    $self->write_methods_acefile;
    $self->initialize_database;
    if ($self->write_local_blast($ss)) {
        # Must parse in new acefile
        $self->initialize_database;

        # Need to restart the read-only sgifaceserver
        # or it will not see any data added by blast.
        $self->ace_server->restart_server;
    }
}

sub write_local_blast {
    my ($self, $ss) = @_;
    
    # The Blast object gets all its configuration
    # information from Lace::Defaults
    ### Should be able to specify mulitple databases to search,
    ### the results of each go into separate columns.
    my $blast = Bio::Otter::Lace::Blast->new;
    $blast->AceDatabase($self);
    $blast->initialise or return;
    my $ace = $blast->run or return;
    my $dir = $self->home;
    my $blast_ace = "$dir/rawdata/local_blast_search.ace";
    open(my $fh, "> $blast_ace") or die "Can't write to '$blast_ace' : $!";
    print $fh $ace;
    close $fh or confess "Error writing to '$blast_ace' : $!";

    # Need to add new method to collection if we don't have it already
    my $coll = $self->MethodCollection;
    my $method = $blast->ace_Method;
    unless ($coll->get_Method_by_name($method->name)) {
        $coll->add_Method($method);
        $self->write_methods_acefile;
    }

    $self->add_acefile($blast_ace);
}

sub write_otter_acefile {
    my( $self, $ss ) = @_;

    my $dsname   = $ss->dataset_name();
    my $ssname   = $ss->name();
    my $ctg_list = $ss->selected_CloneSequences_as_contig_list
        or confess "No CloneSequences selected";

    my $dir = $self->home;
    my $otter_ace = "$dir/rawdata/otter.ace";
    my $fh = gensym();
    open $fh, "> $otter_ace" or die "Can't write to '$otter_ace'";
    print $fh $self->ace_from_dsname_ssname_contig_list($dsname, $ssname, $ctg_list);
    close $fh or confess "Error writing to '$otter_ace' : $!";
    $self->add_acefile($otter_ace);
    $self->save_slice_dataset_hash;
}

# this now just gets the ace via http/xml -> xml_to_otter -> otter_to_ace

sub ace_from_dsname_ssname_contig_list {
    my( $self, $dsname, $ssname, $ctg_list) = @_;

    my $client = $self->Client or confess "No otter Client attached";
    my $ace = '';

    foreach my $ctg (@$ctg_list) {
        my $xml        = Bio::Otter::Lace::TempFile->new;
        $xml->name('lace.xml');
        my $write      = $xml->write_file_handle;

        my($chr_name, $chr_start, $chr_end) = $self->region_coordinates($ctg);
        my $xml_string = $client->get_xml_region($dsname, $ssname, $chr_name, $chr_start, $chr_end);

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
#        $self->save_slice_dataset($slice->display_id, $dsname) unless $write_access;
    }

    return $ace;
}

sub try_and_lock_the_block {
    my ($self, $ss) = @_;

    my $client = $self->Client or confess "No otter Client attached";
    my $dsname = $ss->dataset_name;
    my $ssname = $ss->name;

    my $ctg_list = $ss->selected_CloneSequences_as_contig_list()
            or confess "No CloneSequences selected";
    foreach my $ctg (@$ctg_list){
        my ($chr_name, $chr_start, $chr_end) = $self->region_coordinates($ctg);

        my $lock_xml = $client->lock_region($dsname, $ssname, $chr_name, $chr_start, $chr_end);
        $self->write_lock_xml($lock_xml, $dsname);
    }
}

sub write_lock_xml{
    my ($self, $xml, $dsname) = @_;

    if($xml && $dsname){
        my $lock_xml = Bio::Otter::Lace::PersistentFile->new();
        $lock_xml->root($self->home);
        $lock_xml->name($LOCK_REGION_XML_FILE);
        my $write = $lock_xml->write_file_handle();

        print $write $xml;

        my $read = $lock_xml->read_file_handle();
        my ($genes,$slice,$seqstr,$tiles) = Bio::Otter::Converter::XML_to_otter($read);
        my $slice_name = $slice->display_id();
        $self->save_slice_dataset($slice_name, $dsname);
        $lock_xml->mv(".${slice_name}${dsname}${LOCK_REGION_XML_FILE}");
    }
}

sub save_slice_dataset {
    my( $self, $slice_name, $dsname ) = @_;

    if ($slice_name and $dsname) {
        print STDERR "Saving '$slice_name' in '$dsname'\n";
        $self->{'_slice_name_dataset'}->{$dsname} ||= [];
        push(@{$self->{'_slice_name_dataset'}->{$dsname}}, $slice_name);
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

    while (my ($dsname, $slices) = each %$h) {
        $dsname =~ s/\t/\\t/g;      # Escape tab characterts in dataset name (likely ?)
        map { s/\t/\\t/g } @$slices; # Escape tab characterts in slice   name (v. unlikely)
        print $write "$dsname\t@$slices\n";
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
        my ($dsname, @slices) = split(/\t/, $_);
        $dsname =~ s/\\t/\t/g;     # Unscape tab characterts in dataset name (v. unlikely)
        map { s/\\t/\t/g } @slices; # Unscape tab characterts in slice   name (v. unlikely)
        $h->{$dsname} = \@slices;
    }
}


sub save_all_slices {
    my( $self ) = @_;

    #warn "SAVING ALL SLICES";

    # Make sure we don't have a stale database handle
    $self->ace_server->kill_server;
    $self->ace_server->start_server;

    my $sd_h = $self->slice_dataset_hash;
    #warn "HASH = '$sd_h' has ", scalar(keys %$sd_h), " elements";
    ### This call to each was failing to return anything
    ### the second time it was called, proabably because
    ### we were exiting each the first with an exception
    ### so the iterator didn't get reset.
    #while (my ($name, $ds) = each %$sd_h) {
    my $ace = '';
    foreach my $dsname (keys %$sd_h) {
        my $slices = $sd_h->{$dsname};
        foreach my $slice(@$slices){
            warn "SAVING SLICE '$slice' WITH DATASET '$dsname' to the Otter Server\n";
            $ace .= $self->save_otter_slice($slice, $dsname);
        }
    }

    return \$ace;
}

sub save_otter_slice {
    my( $self, $name, $dsname ) = @_;

    confess "Missing slice name argument"   unless $name;
    confess "Missing DatsSet argument"      unless $dsname;

    my $ace    = $self->aceperl_db_handle;
    my $client = $self->Client or confess "No Client attached";

    # Get the Assembly object ...
    ### Need to change this query if we add lots of non-otter features to the assembly object.
    ### (Or change the layout of the data in acedb, so that non- otter features are in a
    ### different object.)
    $ace->raw_query(qq{find Assembly "$name"});
    my $ace_txt = $ace->raw_query('show -a');
    $ace_txt =~ s/^Feature\s+"phastCons".*\n//mg;

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

    my $success = $client->save_otter_xml($xml, $dsname);

    return $self->update_with_stable_ids($success);
}


sub update_with_stable_ids{
    my ($self, $xml, $anything_else) = @_;
    return unless $xml;

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

    return $ace_txt;
}

sub unlock_all_slices {
    my( $self ) = @_;

    my $sd_h = $self->slice_dataset_hash;

    # if the unlock otter slice goes wrong half way through
    # the recover will try to unlock the clones again.
    foreach my $dsname (keys %$sd_h) {
        my $slices = $sd_h->{$dsname};
        foreach my $slice(splice(@$slices)){
            $self->unlock_otter_slice($slice, $dsname);
        }
    }
}

sub unlock_otter_slice{
    my( $self, $slice_name, $dsname ) = @_;

    confess "Missing slice name argument"   unless $slice_name;
    confess "Missing DatsSet name argument" unless $dsname;

    my $client   = $self->Client or confess "No Client attached";

    my $xml_file = Bio::Otter::Lace::PersistentFile->new;
    $xml_file->root($self->home);
    $xml_file->name(".${slice_name}${dsname}${LOCK_REGION_XML_FILE}");
    return unless -e $xml_file->full_name();
    my $xml = '';
    my $read = $xml_file->read_file_handle;
    while(<$read>){
        $xml .= $_;
    }
    return unless $xml;

    return $client->unlock_otter_xml($xml, $dsname);
}

sub ace_server {
    my( $self ) = @_;
    
    my $sgif;
    unless ($sgif = $self->{'_ace_server'}) {
        $sgif = Hum::Ace::LocalServer->new($self->home);
        $sgif->server_executable('sgifaceserver');
        $sgif->start_server() or return 0; # this only check the fork was successful
        $sgif->ace_handle(1)  or return 0; # this checks it can connect
        $self->{'_ace_server'} = $sgif;
    }
    return $sgif;
}

sub aceperl_db_handle {
    my( $self ) = @_;

    return $self->ace_server->ace_handle;
}

sub make_database_directory {
    my( $self ) = @_;

    my $home = $self->home;
    my $tar  = $self->tar_file or confess "tar_file not set";
    mkdir($home, 0777) or die "Can't mkdir('$home') : $!\n";

    my $tar_command = qq{cd "$home" ; tar xf "$tar"};
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
    my $collect = $self->MethodCollection;
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
    my $pipe = "| $tace $home >> $parse_log";

    my $pipe_fh = gensym();
    open $pipe_fh, $pipe
        or die "Can't open pipe '$pipe' : $!";
    # Say "yes" to "initalize database?" question.
    print $pipe_fh "y\n" unless $self->db_initialized;
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
    $self->empty_acefile_list;
    $self->db_initialized(1);
    return 1;
}


sub db_initialized {
    my( $self, $db_initialized ) = @_;
    
    if (defined $db_initialized) {
        $self->{'_db_initialized'} = $db_initialized ? 1 : 0;
    }
    return $self->{'_db_initialized'};
}

sub region_coordinates {
    my( $self, $ctg ) = @_;

    my $chr_name  = $ctg->[0]->chromosome;
    my $chr_start = $ctg->[0]->chr_start;
    my $chr_end   = $ctg->[$#$ctg]->chr_end;
    return($chr_name, $chr_start, $chr_end);
}

sub write_pipeline_data {
    my( $self, $ss, $ace_file ) = @_;

    my $client  = $self->Client();
    my $dsname  = $ss->dataset_name();
    my $ssname  = $ss->name();

    my $factory = $self->{'_pipeline_data_factory'} ||= $self->make_otterpipe_DataFactory($dsname, $ssname);

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

    # note: the next line returns a 2 dimensional array (not a one dimensional array)
    # each subarray contains a list of clones that are together on the golden path
    my $sel = $ss->selected_CloneSequences_as_contig_list;
    foreach my $ctg (@$sel) {
        my( $chr_name, $chr_start, $chr_end ) = $self->region_coordinates($ctg);

        my $smart_slice = Bio::Otter::Lace::Slice->new($client, $dsname, $ssname,
            'chromosome', 'Otter', $chr_name, $chr_start, $chr_end);

        $factory->ace_data_from_slice($smart_slice);
    }
    $factory->drop_file_handle;
    close $fh;

    if($self->{_pipe_db}) {
        Bio::Otter::Lace::SatelliteDB::disconnect_DBAdaptor($self->{_pipe_db});
    }
}

sub make_otterpipe_DataFactory {
    my( $self, $dsname, $ssname ) = @_;

    my $client = $self->Client();
    warn "This dataset is '$dsname'\n";

    # create new datafactory object - contains all ace filters and produces the data from these
    my $factory = Bio::EnsEMBL::Ace::DataFactory->new($client, $dsname);

    ##----------code to add all of the ace filters to data factory-----------------------------------

    my $fetch_pipe = Bio::Otter::Lace::Defaults::fetch_pipeline_switch();
    my $debug = $client->debug();
    
    my $logic_to_load  = $client->option_from_array([ $dsname, 'use_filters' ]);
    my $module_options = $client->option_from_array([ $dsname, 'filter' ]);

    my @analysis_names;
    if ($fetch_pipe) {
        @analysis_names = grep $logic_to_load->{$_}, keys %$logic_to_load;
    }
    push @analysis_names, 'otter';

    my $collect = $self->MethodCollection;

    foreach my $logic_name (@analysis_names) {

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

        my $pipe_filter = $class->new;

        if (! $pipe_filter->isa('Bio::EnsEMBL::Ace::Otter_Filter')) { # we might need a direct mysql connection

            if(! $self->{_pipe_db} ) { # looks like we need to initialize it
                my $dataset = $client->get_DataSet_by_name($dsname);
                my $otter_db = $dataset->get_cached_DBAdaptor();
                $self->{_pipe_db} = Bio::Otter::Lace::PipelineDB::get_DBAdaptor($otter_db);
                $self->{_pipe_db}->assembly_type($ssname);
            }

            $pipe_filter->dba( $self->{_pipe_db} );
        }

            # analysis_name MUST be set, whether it is defined in the config or not:
        $param{analysis_name} ||= $logic_name;

        # Options in the config file are methods on filter objects:
        while (my ($option, $value) = each %param) {
            #warn "setting '$option' to '$value'\n";
            $pipe_filter->$option($value);
        }

        # does the filter need a method?
        my $req = $pipe_filter->required_ace_method_names;
        foreach my $tag (@$req) {
            #print STDERR "Trying to get a method Object with tag '$tag' ... filter '$class' ... ";
            my $methObj = $collect->get_Method_by_name($tag);
            #print STDERR $methObj ? "found one\n" : "find failed\n";
            $pipe_filter->add_method_object($methObj);    # or some other place
        }

        # add the filter to the factory
        $factory->add_AceFilter($pipe_filter);
    }

    return $factory;
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

