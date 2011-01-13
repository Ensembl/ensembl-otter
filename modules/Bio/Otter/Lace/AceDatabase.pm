
### Bio::Otter::Lace::AceDatabase

package Bio::Otter::Lace::AceDatabase;

use strict;
use warnings;
use Carp;

use Fcntl qw{ O_WRONLY O_CREAT };
use Config::IniFiles;
use URI::Escape qw{ uri_escape };

use Bio::Vega::Transform::Otter::Ace;
use Bio::Vega::AceConverter;
use Bio::Vega::Transform::XML;

use Bio::Otter::Lace::AccessionTypeCache;
use Bio::Otter::Lace::PipelineDB;
use Bio::Otter::Lace::SatelliteDB;
use Bio::Otter::Lace::PersistentFile;
use Bio::Otter::Lace::Slice; # a new kind of Slice that knows how to get pipeline data

use Hum::Ace::LocalServer;
use Hum::Ace::MethodCollection;
use Hum::ZMapStyleCollection;

my      $REGION_XML_FILE =      '.region.xml';
my $LOCK_REGION_XML_FILE = '.lock_region.xml';

my $FILTERS_STATE_FILE = "filters_state.ini";
my @FILTER_STATES = qw(wanted done failed);

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

sub AccessionTypeCache {
    my ($self) = @_;
    
    my $cache = $self->{'_AccessionTypeCache'}
        ||= Bio::Otter::Lace::AccessionTypeCache->new;
    $cache->Client($self->Client);
    return $cache;
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

sub post_exit_callback {
    my( $self, $post_exit_callback ) = @_;
    
    if ($post_exit_callback) {
        $self->{'_post_exit_callback'} = $post_exit_callback;
    }
    return $self->{'_post_exit_callback'};
}

sub MethodCollection {
    my ($self) = @_;

    my $collect = $self->{'_MethodCollection'} ||= $self->get_default_MethodCollection;
    return $collect;
}

sub get_default_MethodCollection {
    my( $self ) = @_;
    
    my $styles_collection = Hum::ZMapStyleCollection->new_from_string($self->Client->get_otter_styles);
    my $collect = Hum::Ace::MethodCollection->new_from_string($self->Client->get_methods_ace, $styles_collection);
    $collect->process_for_otterlace;
    return $collect;
}

sub add_acefile {
    my( $self, $acefile ) = @_;

    my $af = $self->{'_acefile_list'} ||= [];
    push(@$af, $acefile);
    return;
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

    return;
}

sub init_AceDatabase {
    my( $self ) = @_;

    $self->add_misc_acefile;

    my $xml_string = $self->get_region_xml;
    $self->write_file('01_before.xml', $xml_string);

    my $parser = Bio::Vega::Transform::Otter::Ace->new;
    $parser->parse($xml_string);
    

    $self->write_otter_acefile($parser);
    $self->write_region_xml_file($xml_string);
    $self->write_dna_data;
    $self->write_methods_acefile;

    $self->initialize_database;

    return;
}


sub get_region_xml {
    my ($self) = @_;
    
    # Getting XML from the Client
    my $client      = $self->Client
        or confess "No otter Client attached";
    my $smart_slice = $self->smart_slice
        or confess "No smart_slice attached";

    return $smart_slice->get_region_xml;
    
    # my $save = "/var/tmp/slice.xml";
    # open my $tmp, '>', $save or die "Can't write to '$save'; $!";
    # print $tmp $xml_string;
    # close $tmp or die "Error writing to '$save'; $!";
}

sub write_otter_acefile {
    my( $self, $parser ) = @_;

    # Storing ace_text in a file
    my $ace_filename = $self->home . '/rawdata/otter.ace';
    open my $ace_fh, '>', $ace_filename or die "Can't write to '$ace_filename'";
    print $ace_fh $parser->make_ace;
    close $ace_fh or confess "Error writing to '$ace_filename' : $!";
    $self->add_acefile($ace_filename);

    return;
}

sub try_to_lock_the_block {
    my ($self) = @_;

    if (my $lock_xml = $self->smart_slice->lock_region_xml) {
        $self->write_file($LOCK_REGION_XML_FILE, $lock_xml);
    }

    return;
}

sub write_file {
    my ($self, $file_name, $content) = @_;
    
    my $full_file = join('/', $self->home, $file_name);
    open my $LF, '>', $full_file or die "Can't write to '$full_file'; $!";
    print $LF $content;
    close $LF or die "Error writing to '$full_file'; $!";

    return;
}

sub read_file {
    my ($self, $file_name) = @_;
    
    local $/ = undef;
    my $full_file = join('/', $self->home, $file_name);
    open my $RF, '<', $full_file or die "Can't read '$full_file'; $!";
    my $content = <$RF>;
    close $RF or die "Error reading '$full_file'; $!";
    return $content;
}

sub write_region_xml_file {
    my ($self, $xml) = @_;
    
    # Remove the locus and features to make file smaller
    $xml =~ s{<locus>.*</locus>}{}s;
    $xml =~ s{<feature_set>.*</feature_set>}{}s;    # Might not be valid otter XML
                                                    # without an (empty) featuerset?
    
    $self->write_file($REGION_XML_FILE, $xml);

    return;
}

sub recover_smart_slice_from_region_xml_file {
    my ($self) = @_;
    
    my $client = $self->Client or die "No Client attached";
    
    # We try the LOCK_REGION_XML_FILE too, since uninitialised
    # lace sessions sometimes have it becuase it is created
    # before the REGION_XML_FILE, and we want to recover the
    # session to remove the lock.
    
    my ($error, $parser);
    foreach my $f ($LOCK_REGION_XML_FILE, $REGION_XML_FILE) {
        my $region_file = join('/', $self->home, $f);
        $parser = Bio::Vega::Transform::Otter->new;
        eval { $parser->parsefile($region_file) };
        if ($error = $@) {
            warn $error;
            $parser = undef;
        } else {
            last;
        }
    }
    if ($error) {
        confess $error;
    }
    
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

    return;
}


sub smart_slice {
    my( $self, $smart_slice ) = @_;
    
    if ($smart_slice) {
        $self->{'_smart_slice'} = $smart_slice;
    }
    return $self->{'_smart_slice'};
}

sub save_ace_to_otter {
    my( $self ) = @_;

    my $client = $self->Client or confess "No Client attached";
    my $xml = $client->save_otter_xml($self->generate_XML_from_acedb, $self->smart_slice->dsname);

    return $self->update_with_stable_ids($xml);
}

sub generate_XML_from_acedb {
    my ($self) = @_;
    
    # Make Ensembl objects from the acedb database
    my $converter = Bio::Vega::AceConverter->new;
    $converter->AceDatabase($self);
    $converter->generate_vega_objects;
    
    # Pass the Ensembl objects to the XML formatter
    my $formatter = Bio::Vega::Transform::XML->new;
    $formatter->species($self->smart_slice->dsname);
    $formatter->slice(          $converter->slice           );
    $formatter->clone_seq_list( $converter->clone_seq_list  );
    $formatter->genes(          $converter->genes           );
    $formatter->seq_features(   $converter->seq_features    );
    
    return $formatter->generate_OtterXML;
}

sub update_with_stable_ids {
    my ($self, $xml) = @_;

    return unless $xml;
    
    my $parser = Bio::Vega::Transform::Otter::Ace->new;
    $parser->parse($xml);
    
    return $parser->make_ace_genes_transcripts;
}

sub unlock_otter_slice {
    my( $self ) = @_;

    my $smart_slice = $self->smart_slice();
    my $slice_name  = $smart_slice->name();
    my $dsname      = $smart_slice->dsname();
    
    warn "Unlocking $dsname:$slice_name\n";

    my $client   = $self->Client or confess "No Client attached";

    my $xml_text = $self->read_file($LOCK_REGION_XML_FILE);

    return $client->unlock_otter_xml($xml_text, $dsname);
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

sub ace_server_registered {
    my( $self ) = @_;

    return $self->{'_ace_server'};
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

    my $tar_command = "cd '$home' && tar xzf -";
    eval {
        open my $expand, '|-', $tar_command or die "Can't open pipe '$tar_command'; $?";
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

    return;
}

sub write_methods_acefile {
    my( $self ) = @_;

    my $methods_file = $self->home . '/rawdata/methods.ace';
    my $collect = $self->MethodCollection;
    $collect->write_to_file($methods_file);
    $self->add_acefile($methods_file);

    return;
}

sub make_passwd_wrm {
    my( $self ) = @_;

    my $passWrm = $self->home . '/wspec/passwd.wrm';
    my ($prog) = $0 =~ m{([^/]+)$};
    my $real_name      = ( getpwuid($<) )[0];
    my $effective_name = ( getpwuid($>) )[0];

    my $fh;
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

    return;
}

sub edit_displays_wrm {
    my( $self ) = @_;

    my $home  = $self->home;
    my $title = $self->title;

    my $displays = "$home/wspec/displays.wrm";

    open my $disp_in, '<', $displays or confess "Can't read '$displays' : $!";
    my @disp = <$disp_in>;
    close $disp_in;

    foreach (@disp) {
        next unless /^_DDtMain/;

        # Add our title onto the Main window
        s/\s-t\s*"[^"]+/ -t "$title/i;  # " sorry just to fix emacs syntax highlight
        last;
    }

    open my $disp_out, '>', $displays or confess "Can't write to '$displays' : $!";
    print $disp_out @disp;
    close $disp_out;

    return;
}

sub add_misc_acefile {
    my( $self ) = @_;
    my $file = $self->Client->config_value('misc_acefile');
    return unless $file;
    confess "No such file '$file'" unless -e $file;
    $self->add_acefile($file);
    return;
}

sub initialize_database {
    my( $self ) = @_;

    my $home = $self->home;
    my $tace = $self->tace;

    my $parse_log = "$home/init_parse.log";
    my $pipe = "'$tace' '$home' >> '$parse_log'";

    open my $pipe_fh, '|-', $pipe
        or die "Can't open pipe '$pipe' : $!";
    # Say "yes" to "initalize database?" question.
    print $pipe_fh "y\n" unless $self->db_initialized;
    foreach my $file ($self->list_all_acefiles) {
        print $pipe_fh "parse $file\n";
    }
    close $pipe_fh or die "Error initializing database exit($?)\n";

    open my $fh, '<', $parse_log or die "Can't open '$parse_log' : $!";
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
    return 1;
}


sub db_initialized {
    my( $self ) = @_;

    my $init_file = join('/', $self->home, 'database/ACEDB.wrm');
    return -e $init_file;
}

sub write_dna_data {
    my( $self ) = @_;

    my $slice = $self->smart_slice;
    my $dna_filter = $slice->DataSet->filter_by_name('otter');
    confess "otter filter (used to fetch DNA) missing from otter_config"
        unless $dna_filter;

    my $ace_filename = $self->home . '/rawdata/dna.ace';
    $self->add_acefile($ace_filename);
    open my $ace_fh, '>', $ace_filename
        or confess "Can't write to '$ace_filename' : $!";
    print $ace_fh $dna_filter->ace_data($slice);
    close $ace_fh;

    return;
}

sub reload_filter_state {
    my ($self) = @_;
    
    my $cfg = $self->_filter_state;
    my $filters = $self->filters;

    for my $filter_name ($cfg->Sections) {
        print "Reloading $filter_name\n";
        my $state_hash = $filters->{$filter_name}{state};
        for my $state (@FILTER_STATES) {
            my $setting = $cfg->val($filter_name, $state);
            $state_hash->{$state} = $setting if defined $setting;
        } 
    }

    return;
}

sub save_filter_state {
    my ($self) = @_;
    
    my $cfg = $self->_filter_state;

    while ( my ($name, $value) = each %{$self->filters} ) {
        my $state_hash = $value->{state};
        for my $state (@FILTER_STATES) {
            if (defined(my $setting = $state_hash->{$state})) {
                $cfg->AddSection($name) unless $cfg->SectionExists($name);
                $cfg->newval($name, $state, $setting);
            }
        }
    }
    
    $cfg->RewriteConfig;

    return;
}

sub _filter_state {
    my ($self) = @_;
    unless ($self->{_filter_state}) {
        my $file = $self->home.'/'.$FILTERS_STATE_FILE;
        my $cfg;
        
        # Config::IniFiles is fussy about being passed an empty file, so we have to  
        # do things differently if the file exists or not, we should probably fix this...
        
        unless (-e $file) {
            $cfg = Config::IniFiles->new;
            $cfg->SetFileName($file);
        }
        else {
            $cfg = Config::IniFiles->new( -file => $file );
        }
        
        die "Failed to create Config object from $file" unless $cfg;
        
        $self->{_filter_state} = $cfg;
    }
    
    return $self->{_filter_state};
}

sub filters {
    my ($self) = @_;
    return $self->{_filters} ||= {
        map {
            $_->name => {
                filter => $_,
                state => {
                    wanted => $_->wanted,
                    done   => 0,
                    failed => 0,
                },
            };
        } @{$self->smart_slice->DataSet->filters},
    };
}

sub script_dir {    
    my $script_dir = $ENV{'OTTER_HOME'} . '/ensembl-otter/scripts';
    unless (-d $script_dir) {
        $script_dir = undef;
        foreach my $otter (grep { m{ensembl-otter/} } @INC) {
            $otter =~ s{ensembl-otter/.+}{ensembl-otter/scripts};
            if (-d $otter) {
                $script_dir = $otter;
                last;
            }
        }
    }
    return $script_dir;
}

sub gff_http_script_name {
    return "gff_http.pl";
}

sub gff_http_script_arguments {
    my( $self, $filter ) = @_;

    my $slice_params = $self->smart_slice->toHash;

    my $params = {
        %{ $slice_params },
        %{ $filter->server_params },
        gff_seqname => $slice_params->{type},
        gff_source  => $filter->name,
        session_dir => $self->home,
        url_root    => $self->Client->url_root,
        cookie_jar  => $ENV{'OTTERLACE_COOKIE_JAR'},
    };

    my $arguments = [ ];
    while ( my ( $key, $value ) = each %{$params} ) {
        next unless defined $value;
        push @$arguments, join "=", $key, uri_escape($value);
    }

    return $arguments; 
}


sub DESTROY {
    my( $self ) = @_;

    #warn "Debug - leaving database intact"; return;

    my $home = $self->home;
    my $callback = $self->post_exit_callback;
    print STDERR "DESTROY has been called for AceDatabase.pm with home $home\n";
    if ($self->error_flag) {
        warn "Not cleaning up '$home' because error flag is set\n";
        return;
    }
    my $client = $self->Client;
    eval{
        if ($self->ace_server_registered) {
            $self->ace_server->kill_server;
        }
        if ($client) {
            $self->unlock_otter_slice() if $self->write_access;
        }
    };
    if ($@) {
        warn "Error in AceDatabase::DESTROY : $@";
    } else {
        rename $home, "${home}.done"
            or die "Error renaming the session directory.";
    }
    
    if ($callback) {
        $callback->();
    }

    return;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

