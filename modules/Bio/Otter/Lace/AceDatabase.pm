
### Bio::Otter::Lace::AceDatabase

package Bio::Otter::Lace::AceDatabase;

use strict;
use Carp;
use File::Path 'rmtree';
use Symbol 'gensym';
use Fcntl qw{ O_WRONLY O_CREAT };
use Ace;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub OtterClient {
    my( $self, $client ) = @_;
    
    if ($client) {
        $self->{'_OtterClient'} = $client;
    }
    return $self->{'_OtterClient'};
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
    my( $self ) = @_;

    my $dir = $self->home;
    my $otter_ace = "$dir/rawdata/otter.ace";
    my $fh = gensym();
    open $fh, "> $otter_ace" or die "Can't write to '$otter_ace'";
    print $fh $self->fetch_otter_ace;
    close $fh or confess "Error writing to '$otter_ace' : $!";
    $self->add_acefile($otter_ace);
    $self->save_slice_dataset_hash;
}

sub fetch_otter_ace {
    my( $self ) = @_;

    my $client = $self->OtterClient or confess "No otter client attached";
    
    my $ace = '';
    my $selected_count = 0;
    foreach my $ds ($client->get_all_DataSets) {
        if (my $ctg_list = $ds->selected_CloneSequences_as_contig_list) {
            foreach my $ctg (@$ctg_list) {
                $selected_count += @$ctg;
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
        }
    }
    
    if ($selected_count) {
        return $ace;
    } else {
        return;
    }
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
    
    my $cl   = $self->OtterClient or confess "No Otter Client attached";
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
    my $client = $self->OtterClient or confess "No OtterClient attached";
    
    $ace->find(Genome_Sequence => $name);
    my $ace_txt = $ace->raw_query('show -a');

    $ace->raw_query('Follow SubSequence');
    $ace_txt .= $ace->raw_query('show -a');

    $ace->find(Genome_Sequence => $name);
    $ace->raw_query('Follow AGP_Fragment');
    $ace_txt .= $ace->raw_query('show -a');

    $ace->raw_query('Follow Locus');
    $ace_txt .= $ace->raw_query('show -a');
    $ace->find(Person => '*');  # For Authors
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
    my $client = $self->OtterClient or confess "No OtterClient attached";
    
    $ace->find(Genome_Sequence => $name);
    my $ace_txt = $ace->raw_query('show -a');
    
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



sub DESTROY {
    my( $self ) = @_;
    
    my $home = $self->home;
    if ($self->error_flag) {
        warn "Not cleaning up '$home' because error flag is set\n";
        return;
    }
    
    $self->unlock_all_slices if $self->OtterClient->write_access;
    rmtree($home);
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::AceDatabase

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

