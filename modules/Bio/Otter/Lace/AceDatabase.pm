
### Bio::Otter::Lace::AceDatabase

package Bio::Otter::Lace::AceDatabase;

use strict;
use Carp;
use File::Path 'rmtree';
use Symbol 'gensym';
use Fcntl qw{ O_WRONLY O_CREAT };
use Ace;
use Bio::Otter::Lace::PipelineDB;

use Bio::EnsEMBL::Ace::DataFactory;

use Bio::EnsEMBL::Ace::Filter::Repeatmasker;
use Bio::EnsEMBL::Ace::Filter::CpG;
use Bio::EnsEMBL::Ace::Filter::DNA;
use Bio::EnsEMBL::Ace::Filter::TRF;
use Bio::EnsEMBL::Ace::Filter::Gene;
use Bio::EnsEMBL::Ace::Filter::Gene::Halfwise;
use Bio::EnsEMBL::Ace::Filter::Gene::Predicted;
use Bio::EnsEMBL::Ace::Filter::Similarity::DnaSimilarity;
use Bio::EnsEMBL::Ace::Filter::Similarity::ProteinSimilarity;
use Bio::EnsEMBL::Ace::Filter::SimpleFeature;

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
        $self->{'_home'} = "/var/tmp/lace.$$";
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

sub tar_file {
    my( $self, $tar_file ) = @_;
    
    if ($tar_file) {
        $self->{'_tar_file'} = $tar_file;
    }
    elsif (! $self->{'_tar_file'}) {
        my $root = $ENV{'LACE_LOCAL'} || '/nfs/humace2/hum/data';
        my $file = 'lace_acedb.tar';
        $self->{'_tar_file'} = "$root/$file";
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
    return $self->{'_error_flag'};
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

sub fetch_otter_ace_for_SequenceSet {
    my( $self, $ss ) = @_;
    
    my $client = $self->Client
        or confess "No otter client attached";
    my( $ds );
  SEARCH: foreach my $this_ds ($client->get_all_DataSets) {
        my $ss_list = $this_ds->get_all_SequenceSets;
        foreach my $this_ss (@$ss_list) {
            if ($this_ss == $ss) {
                $ds = $this_ds;
                last SEARCH;
            }
        }
    }
    confess "Can't find DataSet that SequenceSet belongs to"
        unless $ds;
    $ds->selected_SequenceSet($ss);
    my $ctg_list = $ss->selected_CloneSequences_as_contig_list
        or confess "No CloneSequences selected";
    return $self->ace_from_contig_list($ctg_list, $ds);
}

sub fetch_otter_ace {
    my( $self ) = @_;

    my $client = $self->Client or confess "No otter Client attached";
    
    my $ace = '';
    my $selected_count = 0;
    foreach my $ds ($client->get_all_DataSets) {
        my $ss_list = $ds->get_all_SequenceSets;
        foreach my $ss (@$ss_list) {
            if (my $ctg_list = $ss->selected_CloneSequences_as_contig_list) {
                $ds->selected_SequenceSet($ss);
                $ace .= $self->ace_from_contig_list($ctg_list, $ds);
                foreach my $ctg (@$ctg_list) {
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

sub ace_from_contig_list {
    my( $self, $ctg_list, $ds ) = @_;
    
    my $client = $self->Client or confess "No otter Client attached";
    
    my $ace = '';
    foreach my $ctg (@$ctg_list) {
        my $xml = Bio::Otter::Lace::TempFile->new;
        $xml->name('lace.xml');
        my $write = $xml->write_file_handle;
        print $write $client->get_xml_for_contig_from_Dataset($ctg, $ds);
        my ($genes, $slice, $sequence, $tiles) =
            Bio::Otter::Converter::XML_to_otter($xml->read_file_handle);
        $ace .= Bio::Otter::Converter::otter_to_ace($slice, $genes, $tiles, $sequence);

        # We need to record which dataset each slice came
        # from so that we can save it back.
        my $slice_name = $slice->display_id;
        $self->save_slice_dataset($slice_name, $ds);
    }
    return $ace;
}

sub save_slice_dataset {
    my( $self, $slice_name, $dataset ) = @_;
    
    $self->{'_slice_name_dataset'}{$slice_name} = $dataset;
}

sub slice_dataset_hash {
    my $self = shift;
    
    confess "slice_dataset_hash method is read-only" if @_;
    
    my $h = $self->{'_slice_name_dataset'} ||= {};
    return $h;
}

# Makes hash persistent for "lace -recover"
# (Could store in Dataset_name tag in database?)
sub save_slice_dataset_hash {
    my( $self ) = @_;
    
    my $h    = $self->slice_dataset_hash;
    my $file = $self->slice_dataset_hash_file;
    
    my $fh = gensym();
    open $fh, "> $file" or confess "Can't write to file '$file' : $!";
    while (my ($slice, $ds) = each %$h) {
        my $ds_name = $ds->name;
        $slice =~ s/\t/\\t/g;   # Escape tab characterts in slice name (v. unlikely)
        print $fh "$slice\t$ds_name\n";
    }
    close $fh;
}

sub recover_slice_dataset_hash {
    my( $self ) = @_;
    
    my $cl   = $self->Client or confess "No Otter Client attached";
    my $h    = $self->slice_dataset_hash;
    my $file = $self->slice_dataset_hash_file;
    
    my $fh = gensym();
    open $fh, $file or confess "Can't read file '$file' : $!";
    while (<$fh>) {
        chomp;
        my ($slice, $ds_name) = split /\t/, $_, 2;
        $slice =~ s/\\t/\t/g;   # Unscape tab characterts in slice name (v. unlikely)
        my $ds = $cl->get_DataSet_by_name($ds_name);
        $h->{$slice} = $ds;
    }
    close $fh;
}

sub slice_dataset_hash_file {
    my( $self ) = @_;
    
    return $self->home . '/.slice_dataset';
}

sub save_all_slices {
    my( $self ) = @_;
    
    # Make sure we don't have a stale database handle
    $self->drop_aceperl_db_handle;

    my $sd_h = $self->slice_dataset_hash;
    while (my ($name, $ds) = each %$sd_h) {
        $self->save_otter_slice($name, $ds);
    }
}

sub save_otter_slice {
    my( $self, $name, $dataset ) = @_;
    
    confess "Missing slice name argument"   unless $name;
    confess "Missing DatsSet argument"      unless $dataset;

    my $ace    = $self->aceperl_db_handle;
    my $client = $self->Client or confess "No Client attached";
    
    # Get the Genome_Sequence object ...
    $ace->find(Genome_Sequence => $name);
    my $ace_txt = $ace->raw_query('show -a');

    # ... its SubSequences ...
    $ace->raw_query('Follow SubSequence');
    $ace_txt .= $ace->raw_query('show -a');

    # ... and all the Loci attached to the SubSequences.
    $ace->raw_query('Follow Locus');
    $ace_txt .= $ace->raw_query('show -a');
    $ace->find(Person => '*');  # For Authors
    $ace_txt .= $ace->raw_query('show -a');

    # Then get the information for the TilePath
    $ace->find(Genome_Sequence => $name);
    $ace->raw_query('Follow AGP_Fragment');
    $ace_txt .= $ace->raw_query('show -a');
    
    # Cleanup text
    $ace_txt =~ s/\0//g;            # Remove nulls
    $ace_txt =~ s{^\s*//.+}{\n}mg;  # Strip comments
    
    #my $debug_file = "/tmp/otter-debug.$$.ace";
    #open DEBUG, ">> $debug_file" or die;
    #print DEBUG $ace_txt;
    #close DEBUG;
    
    return $client->save_otter_ace($ace_txt, $dataset);
}

sub unlock_all_slices {
    my( $self ) = @_;

    my $sd_h = $self->slice_dataset_hash;
    while (my ($name, $ds) = each %$sd_h) {
        $self->unlock_otter_slice($name, $ds);
    }
}

sub unlock_otter_slice {
    my( $self, $name, $dataset ) = @_;
    
    confess "Missing slice name argument"   unless $name;
    confess "Missing DatsSet argument"      unless $dataset;

    my $ace    = $self->aceperl_db_handle;
    my $client = $self->Client or confess "No Client attached";
    
    $ace->find(Genome_Sequence => $name);
    my $ace_txt = $ace->raw_query('show -a');

    $ace->find(Genome_Sequence => $name);
    $ace->raw_query('Follow AGP_Fragment');
    $ace_txt .= $ace->raw_query('show -a');
    
    # Cleanup text
    $ace_txt =~ s/\0//g;            # Remove nulls
    $ace_txt =~ s{^\s*//.+}{\n}mg;  # Strip comments
    
    return $client->unlock_otter_ace($ace_txt, $dataset);
}

sub aceperl_db_handle {
    my( $self ) = @_;
    
    my( $dbh );
    unless ($dbh = $self->{'_aceperl_db_handle'}) {
        my $home = $self->home;
        my $tace = $self->tace;
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
    my $tar  = $self->tar_file;
    mkdir($home, 0777) or die "Can't mkdir('$home') : $!\n";
    
    my $tar_command = "cd $home ; tar xf $tar";
    if (system($tar_command) != 0) {
        $self->error_flag(1);
        confess "Error running '$tar_command' exit($?)";
    }
    
    # These two acefiles from the tar file need to get parsed
    $self->add_acefile("$home/rawdata/methods.ace");
    $self->add_acefile("$home/rawdata/misc.ace");
    
    $self->make_passwd_wrm;
    $self->edit_displays_wrm;
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
        s/\s-t\s*"[^"]+/ -t "$title/i;
        last;
    }

    my $disp_out = gensym();
    open $disp_out, "> $displays" or confess "Can't write to '$displays' : $!";
    print $disp_out @disp;
    close $disp_out;
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

    return $errors ? 0 : 1;
}

sub write_pipeline_data {
    my( $self, $ss ) = @_;

    my $dataset = $self->Client->get_DataSet_by_name($ss->dataset_name);
    $dataset->selected_SequenceSet($ss);    # Not necessary?
    my $ens_db = Bio::Otter::Lace::PipelineDB::get_DBAdaptor(
        $dataset->get_cached_DBAdaptor
        );
    $ens_db->assembly_type($ss->name);
    my $factory = $self->make_AceDataFactory($ens_db);
    
    # create file for output and add it to the acedb object
    my $ace_file = $self->home . "/rawdata/pipeline.ace";
    $self->add_acefile($ace_file);
    my $fh = gensym();
    open $fh, "> $ace_file" or confess "Can't write to '$ace_file' : $!";
    $factory->file_handle($fh);

    my $slice_adaptor = $ens_db->get_SliceAdaptor();
    
    # note: the next line returns a 2 dimensional array (not a one dimensional array)
    # each subarray contains a list of clones that are together on the golden path
    my $sel = $ss->selected_CloneSequences_as_contig_list ;
    foreach my $cs (@$sel) {

        my $first_ctg = $cs->[0];
        my $last_ctg = $cs->[$#$cs];

        my $chr = $first_ctg->chromosome->name;  
        my $chr_start = $first_ctg->chr_start;
        my $chr_end = $last_ctg->chr_end;

        my $slice = $slice_adaptor->fetch_by_chr_start_end($chr, $chr_start, $chr_end);
        
        ### Check we got a slice
        my $tp = $slice->get_tiling_path;
        my $type = $slice->assembly_type;
        warn "assembly type = $type";
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
}

sub make_AceDataFactory {
    my( $self, $ens_db ) = @_;

    my $percent_identity_cutoff = undef; ## change this if a cutoff value is reqired

    # create new datafactory object - cotains all ace filters and produces the data from these
    my $factory = Bio::EnsEMBL::Ace::DataFactory->new;       
#    $factory->add_all_Filters($ensdb);   
   
    
   my $ana_adaptor = $ens_db->get_AnalysisAdaptor;
   
   ##----------code to add all of the ace filters to data factory-----------------------------------
    
    my @logic_class = (
        [qw{ SubmitContig   Bio::EnsEMBL::Ace::Filter::DNA              }],
        [qw{ RepeatMask     Bio::EnsEMBL::Ace::Filter::Repeatmasker     }],
        [qw{ trf            Bio::EnsEMBL::Ace::Filter::TRF              }],
        [qw{ genscan        Bio::EnsEMBL::Ace::Filter::Gene::Predicted  }],
        [qw{ Fgenesh        Bio::EnsEMBL::Ace::Filter::Gene::Predicted  }],
        [qw{ CpG            Bio::EnsEMBL::Ace::Filter::CpG              }],
        );

    foreach my $lc (@logic_class) {
        my ($logic_name, $class) = @$lc;
        if (my $ana = $ana_adaptor->fetch_by_logic_name($logic_name)) {
            my $filt = $class->new;
            $filt->analysis_object($ana);
            $factory->add_AceFilter($filt);
        } else {
            warn "No analysis called '$logic_name'\n";
        }
    }
    
    #halfwise
    if (my $ana = $ana_adaptor->fetch_by_logic_name('Pfam')) {
        my $halfwise = Bio::EnsEMBL::Ace::Filter::Gene::Halfwise->new;
        $halfwise->url_string('http\\:\\/\\/www.sanger.ac.uk\\/cgi-bin\\/Pfam\\/getacc?%s');   ##??is this still correct?
        $halfwise->analysis_object($ana);
        $factory->add_AceFilter($halfwise);
    } else {
        warn "No analysis called 'Pfam'\n";
    }

## big list for DNASimilarity / Protein_similarity

## note: most of the list here is taken from the previous version, 
## currently only the uncommented ones seem to be in the database   
    my %logic_tag_method = (
#        'Est2Genome'        => [qw{             EST_homol  EST_eg           }],
        'Est2Genome_human'  => [qw{             EST_homol  EST_Human     }],
        'Est2Genome_mouse'  => [qw{             EST_homol  EST_Mouse     }],
        'Est2Genome_other'  => [qw{             EST_homol  EST           }],
#        'Full_dbGSS'        => [qw{             GSS_homol  GSS_eg           }],
#        'Full_dbSTS'        => [qw{             STS_homol  STS_eg           }],
#        'sccd'              => [qw{             EST_homol  egag             }],
#        'riken_mouse_cdnal' => [qw{             EST_homol  riken_mouse_cdna }],
#        'primer'            => [qw{             DNA_homol  primer           }],
        'vertrna'           => [qw{ vertebrate_mRNA_homol  vertebrate_mRNA 0 }],
#        'zfishEST'          => [qw{             EST_homol  EST_eg-fish      }],
        );
        
    foreach my $logic_name (keys %logic_tag_method) {
        if (my $ana = $ana_adaptor->fetch_by_logic_name($logic_name)) {
            my( $tag, $meth, $coverage ) = @{$logic_tag_method{$logic_name}};
            my $sim = Bio::EnsEMBL::Ace::Filter::Similarity::DnaSimilarity->new;
            #warn "setting analysis object to '$ana' for '$logic_name'\n";
            $sim->analysis_object($ana);
            $sim->homol_tag($tag);
            $sim->method_tag($meth);
            $sim->hseq_prefix('Em:');
            $sim->max_coverage($coverage);
            if ( defined($percent_identity_cutoff) ) {
                $sim->percent_identity_cutoff($percent_identity_cutoff);
            }
            $factory->add_AceFilter($sim);
#            warn 'logic_tag:' , $tag , "\n" ;
        } else{
            warn "No analysis called '$logic_name'\n";
        }
    }
    
    
    ## protein similarity
    if (my $ana = $ana_adaptor->fetch_by_logic_name('swall')) {
        my $prot_sim = Bio::EnsEMBL::Ace::Filter::Similarity::ProteinSimilarity->new;
        $prot_sim->analysis_object($ana);
        $prot_sim->homol_tag('swall');
        $prot_sim->method_tag('BLASTX');
        if( defined($percent_identity_cutoff)  ){
            $prot_sim->percent_identity_cutoff($percent_identity_cutoff);
        }
        $factory->add_AceFilter($prot_sim);    
    } else {
        warn "No analysis called 'swall'\n";
    }
    
    return $factory;
}


sub DESTROY {
    my( $self ) = @_;
    
    my $home = $self->home;
    if ($self->error_flag) {
        warn "Not cleaning up '$home' because error flag is set\n";
        return;
    }
    
    $self->unlock_all_slices if $self->Client->write_access;
    rmtree($home);
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::AceDatabase

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

