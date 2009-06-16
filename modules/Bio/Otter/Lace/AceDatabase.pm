
### Bio::Otter::Lace::AceDatabase

package Bio::Otter::Lace::AceDatabase;

use strict;
use warnings;
use Carp;
use File::Path 'rmtree';
use Fcntl qw{ O_WRONLY O_CREAT };

# use Bio::Otter::Converter;
use Bio::Vega::Converter;
use Bio::Vega::Transform::Otter;

use Bio::Otter::Lace::Slice;
use Bio::Otter::Lace::Defaults;
use Bio::Otter::Lace::PipelineDB;
use Bio::Otter::Lace::SatelliteDB;
use Bio::Otter::Lace::PersistentFile;
use Bio::Otter::Lace::Slice; # a new kind of Slice that knows how to get pipeline data
use Bio::Otter::Lace::Exonerate;


use Bio::EnsEMBL::Ace::DataFactory;

use Hum::Ace::LocalServer;
use Hum::Ace::MethodCollection;

my      $REGION_XML_FILE =      '.region.xml';
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
        $self->{'_write_access'} = $write_access ? 1 : 0;
    }
    return $self->{'_write_access'};
}

sub home {
    my( $self, $home ) = @_;
    
    if ($home) {
        $self->{'_home'} = $home;
    }
    return $self->{'_home'};
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
    my ($self) = @_;

    my $collect = $self->{'_MethodCollection'} ||= $self->get_default_MethodCollection;
    return $collect;
}

sub get_default_MethodCollection {
    my( $self ) = @_;

    my $collect = Hum::Ace::MethodCollection->new_from_string($self->Client->get_methods_ace);
    $collect->process_for_otterlace;
    return $collect;
}

sub add_acefile {
    my( $self, $acefile ) = @_;

    my $af = $self->{'_acefile_list'} ||= [];
    push(@$af, $acefile);
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

sub add_zmap_styles_acefile {
    my ($self) = @_;

    my $styles_file = $self->home . "/rawdata/zmap_styles.ace";
    confess "Missing Zmap_Styles file: '$styles_file'"
        unless -e $styles_file;
    $self->add_acefile($styles_file);
}

sub init_AceDatabase {
    my( $self ) = @_;

    $self->add_misc_acefile;

    my $xml_string = $self->smart_slice->get_region_xml;
    my $parser = Bio::Vega::Transform::Otter->new;
    $parser->parse($xml_string);
    $self->write_otter_acefile($parser);
    
    $self->write_region_xml_file($xml_string);
    
    $self->write_dna_data;

    $self->write_methods_acefile;
    $self->initialize_database;

    eval {
        my $cl = $self->Client;
        if ($cl->option_from_array([ 'local_exonerate', 'database' ])) {
            $self->write_local_exonerate;
        }
    };
    if ($@) {
        warn $@;
    }

}

sub write_local_exonerate {
    my ($self) = @_;

    # The Exonerate object gets all its configuration
    # information from Lace::Defaults
    ### Should be able to specify mulitple databases to search,
    ### the results of each go into separate columns.
    my $exon = Bio::Otter::Lace::Exonerate->new;
    $exon->AceDatabase($self);
    $exon->initialise or return;
    my $ace_text = $exon->run or return;

    my $ace_filename = $self->home . '/rawdata/local_exonerate_search.ace';
    open(my $ace_fh, "> $ace_filename") or die "Can't write to '$ace_filename' : $!";
    print $ace_fh $ace_text;
    close $ace_fh or confess "Error writing to '$ace_filename' : $!";

    # Need to add new method to collection if we don't have it already
    my $coll = $self->MethodCollection;
    my $method = $exon->ace_Method;
    unless ($coll->get_Method_by_name($method->name)) {
        $coll->add_Method($method);
        $self->ace_server->save_ace($coll->ace_string());
    }

	$self->ace_server->save_ace($ace_text);
}


sub get_region_xml {
    my ($self) = @_;
    
    # Getting XML from the Client
    my $client      = $self->Client
        or confess "No otter Client attached";
    my $smart_slice = $self->smart_slice
        or confess "No smart_slice attached";

    my $xml_string  = $smart_slice->get_region_xml();
    
    # my $save = "/var/tmp/slice.xml";
    # open my $tmp, "> $save" or die "Can't write to '$save'; $!";
    # print $tmp $xml_string;
    # close $tmp or die "Error writing to '$save'; $!";

    my $parser = Bio::Vega::Transform::Otter->new;
    $parser->parse($xml_string);
    return $parser;
}

sub write_otter_acefile {
    my( $self, $parser ) = @_;
        
    my $ace_str = Bio::Vega::Converter::make_ace($parser);

    # Storing ace_text in a file
    my $ace_filename = $self->home . '/rawdata/otter.ace';
    open my $ace_fh, "> $ace_filename" or die "Can't write to '$ace_filename'";
    print $ace_fh $ace_str;
    close $ace_fh or confess "Error writing to '$ace_filename' : $!";
    $self->add_acefile($ace_filename);
}

sub try_to_lock_the_block {
    my ($self) = @_;

    if (my $lock_xml = $self->smart_slice->lock_region_xml) {
        $self->write_file($LOCK_REGION_XML_FILE, $lock_xml);
    }
}

sub write_file {
    my ($self, $file_name, $content) = @_;
    
    my $full_file = join('/', $self->home, $file_name);
    open my $LF, "> $full_file" or die "Can't write to '$full_file'; $!";
    print $LF $content;
    close $LF or die "Error writing to '$full_file'; $!";
}

sub write_region_xml_file {
    my ($self, $xml) = @_;
    
    # Remove the locus and features to make file smaller
    $xml =~ s{<locus>.*</locus>}{}s;
    $xml =~ s{<feature_set>.*</feature_set>}{}s;    # Might not be valid otter XML
                                                    # without an (empty) featuerset?
    
    $self->write_file($REGION_XML_FILE, $xml);
}

sub recover_smart_slice_from_region_xml_file {
    my ($self) = @_;
    
    my $client = $self->Client or die "No Client attached";
    
    my $region_file = join('/', $self->home, $REGION_XML_FILE);
    
    my $parser = Bio::Vega::Transform::Otter->new;
    $parser->parsefile($region_file);
    
    my $slice = $parser->get_ChromosomeSlice;
    
    my $smart_slice = Bio::Otter::Lace::Slice->new(
        $client,
        $parser->species,
        $slice->seq_region_name,
        $slice->coord_system->name,
        $slice->coord_system->version,
        $parser->chromosome_name,
        $slice->start,
        $slice->end,
        );
    $self->smart_slice($smart_slice);
}


sub smart_slice {
    my( $self, $smart_slice ) = @_;
    
    if ($smart_slice) {
        $self->{'_smart_slice'} = $smart_slice;
    }
    return $self->{'_smart_slice'};
}

sub get_filter_loaded_states_from_pipeline {
    my $self = shift @_;
    
    warn "Fetching filters from acedb\n";

    my $ace_handle = $self->aceperl_db_handle;
    $ace_handle->raw_query('find Assembly *');
    my $ace_text = $ace_handle->AceText_from_tag('Filter');

    my %filter_loaded = map { ($_->[0] => 1) } $ace_text->get_values('Filter');

    return \%filter_loaded;
}

sub save_ace_to_otter {
    my( $self ) = @_;

    # # Make sure we don't have a stale database handle
    # $self->ace_server->kill_server;
    # $self->ace_server->start_server;

    my $ace    = $self->aceperl_db_handle;
    my $client = $self->Client or confess "No Client attached";

    my $smart_slice = $self->smart_slice();
    my $slice_name  = $smart_slice->name();
    my $dsname      = $smart_slice->dsname();

    # Get the Assembly object ...
    ### Need to change this query if we add lots of non-otter features to the assembly object.
    ### (Or change the layout of the data in acedb, so that non-otter features are in a
    ### different object.)
    $ace->raw_query(qq{find Assembly "$slice_name"});

    my $ace_txt = $ace->raw_query('show -a');
    my $editable = join '|', map $_->name,
        $self->MethodCollection->get_all_mutable_non_transcript_Methods;
    # Remove all Feature lines which aren't editable types
    $ace_txt =~ s/^Feature\s+"(?!($editable)).*\n//mg;

    # ... its SubSequences ...
    # I think we could switch to a positive filter on Predicted_gene instead
    # of the negative filter on CDS_predicted_by.  (And we could even use
    # a more sensible tag name than "Predicted_gene".)
    $ace->raw_query('query follow SubSequence where ! CDS_predicted_by');
    $ace_txt .= $ace->raw_query('show -a');

    # ... and all the Loci attached to the SubSequences.
    $ace->raw_query('Follow Locus');
    $ace_txt .= $ace->raw_query('show -a');

    # List of people for Authors
    $ace->raw_query(qq{find Person *});
    $ace_txt .= $ace->raw_query('show -a');

    # Then get the information for the TilePath
    $ace->raw_query('find Assembly *');
    $ace->raw_query('Follow AGP_Fragment');
    # Do show -a on a restricted list of tags
    foreach my $tag (qw{
        Otter
        DB_info
        Annotation
        Clone
        DNA
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
        my $debug_ace_fh = $debug_file->write_file_handle();
        print $debug_ace_fh $ace_txt;
        close $debug_ace_fh;
    }else{
        warn "Debug switch is false\n";
    }

    my $ace_file = Bio::Otter::Lace::TempFile->new;
    $ace_file->name('lace_edited.ace');
    my $write_fh = $ace_file->write_file_handle;
    print $write_fh $ace_txt;
    my $xml = Bio::Otter::Converter::ace_to_XML($ace_file->read_file_handle);
    close $write_fh;

    if($self->Client->debug){
        my $debug_file = Bio::Otter::Lace::PersistentFile->new();
        $debug_file->name("otter-debug.$$.save.xml");
        my $debug_xml_fh = $debug_file->write_file_handle();
        print $debug_xml_fh $xml;
        close $debug_xml_fh;
    }else{
        warn "Debug switch is false\n";
    }

    my $success = $client->save_otter_xml($xml, $dsname);

    return $self->update_with_stable_ids($success);
}


sub update_with_stable_ids {
    my ($self, $xml, $anything_else) = @_;

    return unless $xml;

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
    my ($genes, $old_schema_slice, $seqstr, $tiles) = Bio::Otter::Converter::XML_to_otter($read);

    ## this should only contain the CHANGED genes.
    unless (@$genes) {
        warn "No genes changed\n";
        return undef;
    }

    warn "Some genes changed\n";
    ## need to do genes, transcripts, translations and exons

    return Bio::Otter::Converter::ace_transcripts_locus_people($genes, $old_schema_slice);
}

sub unlock_otter_slice {
    my( $self ) = @_;

    my $smart_slice = $self->smart_slice();
    my $slice_name  = $smart_slice->name();
    my $dsname      = $smart_slice->dsname();

    my $client   = $self->Client or confess "No Client attached";

    my $xml_file = Bio::Otter::Lace::PersistentFile->new;
    $xml_file->root($self->home);

            # we may need this for compatibility with sessions recovered from prev.releases!
    $xml_file->name(".${slice_name}${dsname}${LOCK_REGION_XML_FILE}");
            # otherwise we could use the simplified name:
    #$xml_file->name($LOCK_REGION_XML_FILE);

    return unless -e $xml_file->full_name();
    my $xml_text = '';
    my $read = $xml_file->read_file_handle;
    while(<$read>){
        $xml_text .= $_;
    }
    return unless $xml_text;

    return $client->unlock_otter_xml($xml_text, $dsname);
}

sub ace_server_registered {
    my( $self ) = @_;

    return $self->{'_ace_server'};
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
    my $tar  = $self->Client->get_lace_acedb_tar
        or confess "Client did not return tar file for local acedb database directory structure";
    mkdir($home, 0777) or die "Can't mkdir('$home') : $!\n";

    my $tar_command = qq{| (cd "$home" ; tar xzf -)};
    eval {
        open my $expand, $tar_command or die "Can't open pipe '$tar_command'; $?";
        print $expand $tar;
        close $expand or die "Error running pipe '$tar_command'; $?";
    };
    if ($@) {
        $self->error_flag(1);
        confess $@;
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

    my $methods_file = $self->home . '/rawdata/methods.ace';
    my $collect = $self->MethodCollection;
    $collect->write_to_file($methods_file);
    $self->add_acefile($methods_file);
}

sub make_passwd_wrm {
    my( $self ) = @_;

    my $passWrm = $self->home . '/wspec/passwd.wrm';
    my ($prog) = $0 =~ m{([^/]+)$};
    my $real_name      = ( getpwuid($<) )[0];
    my $effective_name = ( getpwuid($>) )[0];

    sysopen(my $fh, $passWrm, O_CREAT | O_WRONLY, 0644)
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

    open my $disp_in, $displays or confess "Can't read '$displays' : $!";
    my @disp = <$disp_in>;
    close $disp_in;

    foreach (@disp) {
        next unless /^_DDtMain/;

        # Add our title onto the Main window
        s/\s-t\s*"[^"]+/ -t "$title/i;  # " sorry just to fix emacs syntax highlight
        last;
    }

    open my $disp_out, "> $displays" or confess "Can't write to '$displays' : $!";
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

    open my $pipe_fh, $pipe
        or die "Can't open pipe '$pipe' : $!";
    # Say "yes" to "initalize database?" question.
    print $pipe_fh "y\n" unless $self->db_initialized;
    foreach my $com (@parse_commands) {
        print $pipe_fh $com;
    }
    close $pipe_fh or die "Error initializing database exit($?)\n";

    open my $fh, $parse_log or die "Can't open '$parse_log' : $!";
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

sub write_dna_data {
    my( $self ) = @_;

    my $smart_slice = $self->smart_slice();

    require Bio::EnsEMBL::Ace::Otter_Filter::DNA;
    my $dna_filter = Bio::EnsEMBL::Ace::Otter_Filter::DNA->new;
    $dna_filter->method_tag('NonGolden');

    my $ace_filename = $self->home . '/rawdata/dna.ace';
    $self->add_acefile($ace_filename);
    open my $ace_fh, "> $ace_filename" or confess "Can't write to '$ace_filename' : $!";

    print $ace_fh $dna_filter->ace_data($smart_slice);

    close $ace_fh;
}

sub topup_pipeline_data_into_ace_server {
    my( $self ) = @_;

    my $factory     = $self->pipeline_DataFactory();

        # closure will probably work better:
    my $ace_server = $self->ace_server();

    $factory->ace_string_callback( sub{ $ace_server->save_ace(@_); } );
    my $filters_fetched_data = $factory->topup_pipeline();
    $factory->ace_string_callback( undef );

    return $filters_fetched_data;
}

sub pipeline_DataFactory {
    my( $self ) = @_;

    my $factory;

    if($factory = $self->{_pipeline_DataFactory}) {
        warn "\nTopping up the existing pipeline DataFactory.\n";
        return $factory;
    }

    my $client      = $self->Client();
    my $smart_slice = $self->smart_slice();

    my $ds_orig_name  = $smart_slice->dsname();
    my $ds_alias_name = $client->get_DataSet_by_name($ds_orig_name)->ALIAS();
    my @ds_list = $ds_alias_name ? ($ds_alias_name, $ds_orig_name) : ($ds_orig_name);
        # It is a means to create a 'species alias' to reuse the otter_config for one species without duplication.
        # For example, if you need a test_human database that would fetch all human analyses from the pipeline
        # it is the shortest way to go. However, by using test_human filters or module settings you'll override
        # the behaviour of the master database.
        #

    warn "\nCreating a pipeline DataFactory for ".join('->', map {"'$_'"} @ds_list)."\n";

    $factory = Bio::EnsEMBL::Ace::DataFactory->new($smart_slice);

    ##----------code to add all of the ace filters to data factory-----------------------------------

    my $debug = $client->debug();

    # my $filter_loaded = $self->ace_server_registered()
    #     ? $self->get_filter_loaded_states_from_pipeline()
    #     : {};
    my $filter_loaded = $self->get_filter_loaded_states_from_pipeline();

        # loading the filters in the priority order (latter overrides the former)
    my %use_filters    = ();
    my %filter_options = ();
    foreach my $ds_name (@ds_list) {
        %use_filters    = (%use_filters  ,  %{ $client->option_from_array([ $ds_name, 'use_filters' ]) } );
        %filter_options = (%filter_options, %{ $client->option_from_array([ $ds_name, 'filter' ]) } );
    }

    my $collect = $self->MethodCollection;

    while ( my($filter_name, $filter_wanted) = each %use_filters   ) {

        my $param_ref = $filter_options{$filter_name}
            or die "No parameters for '$filter_name'";

        # Take a copy of the parameters so that we can delete from it.
        my %param = %$param_ref;

        # class successfully required already.
        my $class = delete $param{'module'}
          or confess "Module class for '$filter_name' missing from config";

        # Load the filter module
        my $file = "$class.pm";
        $file =~ s{::}{/}g;
        eval { require $file };
        if ($@) {
            die "Error attempting to load filter module '$file'\n$@";
        }

            # we create all available filters and load all corresponding methods
            # irrespectively of whether they are 'wanted' or not,
            # so that we would be able to run them at a later time if needed
        my $pipe_filter = $class->new( $filter_wanted, $filter_loaded->{$filter_name} );

        # analysis_name MUST be set, whether it is defined in the config or not:
        $param{analysis_name} ||= $filter_name;

        # Options in the config file are methods on filter objects:
        while (my ($option, $value) = each %param) {
            if($pipe_filter->can($option)) {
                $pipe_filter->$option($value);
            } else {
                die "Wrong configuration for '$filter_name' analysis - check your '.otter_config' file. If it looks correct you might be running an outdated version of the client.\n";
            }
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
        $factory->add_filter($filter_name, $pipe_filter);
    }

        # cache it for future reference
    return $self->{_pipeline_DataFactory} = $factory;
}


sub DESTROY {
    my( $self ) = @_;

    #warn "Debug - leaving database intact"; return;

    my $home = $self->home;
    print STDERR "DESTROY has been called for AceDatabase.pm with home $home\n";
    if ($self->error_flag) {
        warn "Not cleaning up '$home' because error flag is set\n";
        return;
    }
    my $client = $self->Client;
    eval{
        if($client) {
            $self->unlock_otter_slice() if $self->write_access;
        }
    };
    if($@) {
        warn "Error in AceDatabase::DESTROY : $@";
    } else {
        # rmtree fails with:
        #     Can't fetch initial working directory
        # if the user's NFS mounted home directory has
        # been dropped and remounted while running otterlace.
        # /var/tmp is always local to the machine, so going
        # here first guarantees that we won't see this error.
        chdir("/var/tmp")
          or die "Can't chdir to /var/tmp : $!";
        rmtree($home)
          or die "Error removing lace database directory";
    }
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

