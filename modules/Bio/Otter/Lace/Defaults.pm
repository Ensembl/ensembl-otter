
### Bio::Otter::Lace::Defaults

package Bio::Otter::Lace::Defaults;

use strict;
use Carp;
use Getopt::Long 'GetOptions';
use Symbol 'gensym';
use Config::IniFiles;
use Data::Dumper;
use Bio::Otter::Lace::Client;

my $CLIENT_STANZA   = 'client';
my $DEFAULT_TAG     = 'default';
my $DEBUG_CONFIG    = 0;
#-------------------------------
my $CONFIG_INIFILES = [];
my %OPTIONS_TO_TIE  = (
                       -default => $DEFAULT_TAG, 
                       -nocase  => 1
                       );

my $HARDWIRED = {};
tie %$HARDWIRED, 'Config::IniFiles', (-file => \*DATA, %OPTIONS_TO_TIE);
# Make these accessible without call to do_getopt()
push(@$CONFIG_INIFILES, $HARDWIRED); 

# The tied hash for the GetOptions variables
my $DEFAULTS = {};
tie %$DEFAULTS, 'Config::IniFiles', %OPTIONS_TO_TIE;

our $GETOPT_ERRSTR  = undef;
my @CLIENT_OPTIONS = qw(
    host=s
    port=s
    author=s
    email=s
    pipeline!
    write_access!
    group=s
    gene_type_prefix=s
    debug!
    misc_acefile=s
    );

# @CLIENT_OPTIONS is Getopt::GetOptions() keys which will be included in the 
# $DEFAULTS->{$CLIENT_STANZA} hash.  To add another client option just include in above
# and if necessary add to hardwired defaults in do_getopt().

my $save_option = sub {
    my( $option, $value ) = @_;
    $DEFAULTS->{$CLIENT_STANZA}->{$option} = $value;
};
my $save_deep_option = sub {
    my $getopt = $_[1];
    my ($option, $value) = split(/=/, $getopt,2);
    $option = [split(/\./, $option)];
    my $param = pop @$option;
    return unless @$option;
    $DEFAULTS->{join(".", @$option)} = { $param => $value };
};
my $CALLED = "$0 @ARGV";


################################################
#
## PUBLIC METHODS
#
################################################


=head1 do_getopt

 A wrapper function around GetOptions

    We get options from:
     - files provided by list_config_files()
     - command line
     - hardwired defaults (in this subroutine)
    overriding as we go.

 Returns true on success, false otherwise, in the latter case 
the Bio::Otter::Lace::Defaults::GETOPT_ERRSTR variable is populated.

Suggested usage:
 @options = (-dataset => \$dataset);
 Bio::Otter::Lace::Defaults::do_getopt(@options) || die $Bio::Otter::Lace::Defaults::GETOPT_ERRSTR;

=cut

sub do_getopt {
    my( @script_args ) = @_;

    my ($this_user, $home_dir) = (getpwuid($<))[0,7];    
    
    my @conf_files = list_config_files();

    $CONFIG_INIFILES = []; # clear and add in case of multiple calls
    push(@$CONFIG_INIFILES, $HARDWIRED);

    my $file_options = [];
    foreach my $file(@conf_files){
	if (my $file_opts = options_from_file($file)) {
	    push(@$CONFIG_INIFILES, $file_opts);
	}
    }

    {   ############################################################################
        ############################################################################
        my $start = "Called as:\n\t$CALLED\nGetOptions() Error parsing options:";
        local $SIG{__WARN__} = sub { 
            my $err = shift; 
            $GETOPT_ERRSTR .= ( $GETOPT_ERRSTR ? "\t$err" : "$start\n\t$err" );
        } unless $DEBUG_CONFIG;
        $GETOPT_ERRSTR = undef; # in case this gets called more than once
        GetOptions(
                   # map {} makes these lines dynamically from @CLIENT_OPTIONS
                   # 'host=s'        => $save_option,
                   ( map { $_ => $save_option } @CLIENT_OPTIONS ),
                   # this allows setting of options as in the config file
                   'cfgstr=s'      => $save_deep_option,
                   # this is just a synonym feel free to add more
                   'view'          => sub { $DEFAULTS->{$CLIENT_STANZA}->{'write_access'} = 0 },
                   'local_fasta=s' => sub { $DEFAULTS->{'local_blast'}->{'database'} = $_[1] },
                   'noblast'       => sub { map { $_->{'local_blast'} = {} if exists $_->{'local_blast'} } @$CONFIG_INIFILES ; },
                   # this allows multiple extra config file to be used
                   'cfgfile=s'     => sub { my $opts = options_from_file($_[1]); push(@$CONFIG_INIFILES, $opts) if $opts },
                   # these are the caller script's options
                   @script_args,
                   ) or return 0;
        ############################################################################
        ############################################################################
    }

    push(@$CONFIG_INIFILES, $DEFAULTS);
#    die Dumper $CONFIG_INIFILES;
    return 1;
}

sub make_Client {
    return Bio::Otter::Lace::Client->new;
}

sub option_from_array{
    my ($array) = @_;
    $array    ||= [];
    my $value   = undef;
    warn "option from array called // @$array //\n" if $DEBUG_CONFIG;

    my @arr_copy = @{$array};
    my $first    = shift @arr_copy;

    my $allow_hash = 1; # allow hash for first call to set_value

    my $set_value = sub {
        my ($conf_val, $found) = @_;
        my $value_is_hash    = ref($value)    eq 'HASH';
        my $conf_val_is_hash = ref($conf_val) eq 'HASH';
        warn "got // $conf_val $found //\n" if $DEBUG_CONFIG;
        return unless $found;
        if(($value_is_hash || $allow_hash) && $conf_val_is_hash){
            # initialise as first time it will be undef
            $value ||= {};
            # overwrite the previous $value
            $value   = { %$value, %$conf_val };
        }else{
            $value = $conf_val;
        }
        $allow_hash = 0;
    };

    # get first file
    #    - get default option from that
    #    - get option from that (if exists) and overwrite
    # get next file
    #    - get default option from that and overwrite
    #    - get option from that (if exists) and overwrite

    foreach my $conf(@$CONFIG_INIFILES){
        $set_value->( __internal_option_from_array($conf, [ ( $DEFAULT_TAG, @arr_copy ) ]) );
        $set_value->( __internal_option_from_array($conf, [ ($first, @arr_copy) ]) );
    }

    return $value;
}

sub list_config_files{
    #   ~/.otter_config
    #   $ENV{'OTTER_HOME'}/otter_config
    #   /etc/otter_config
    my @conf_files = ();
    push(@conf_files, "/etc/otter_config") if -e "/etc/otter_config";

    if ($ENV{'OTTER_HOME'}) {
        # Only add if OTTER_HOME environment variable is set
        push(@conf_files, "$ENV{'OTTER_HOME'}/otter_config");
    }
    my ($home_dir) = (getpwuid($<))[7];
    push(@conf_files, "$home_dir/.otter_config");
    return @conf_files;
}

sub save_all_config_files{
    eval{
        foreach my $config(@$CONFIG_INIFILES){
            my $obj = tied(%$config);
            next unless $obj;
            my $filename = $obj->GetFileName();
            warn "Saving '$filename' \n";
            next unless -w $filename;
            warn "       '$filename' is writeable\n";
            $obj->WriteConfig($filename) or die "Error Writing '$filename'";
            warn "Wrote '$filename'\n";
        }
    };
    if($@){
        warn "Failed Saving Config:\n$@";
    }
}


## sets the known gene methods for a particular XaceSeqChooser
sub set_known_GeneMethods{
    my ($self , $xace ) = @_ ;
    my @methods_mutable =  $self->get_default_GeneMethods ;
    
    confess "uneven number of arguments" if @methods_mutable % 2;
         
    for (my $i = 0; $i < @methods_mutable; $i+= 2) {
        my ($name, $flags) = @methods_mutable[$i, $i+1];
        my ($is_mutable, $is_coding , $has_parent) = @$flags;
        my $meth = $xace->fetch_GeneMethod($name);
        $meth->is_mutable($is_mutable);
        $meth->is_coding($is_coding); 
        $meth->has_parent($has_parent);
        $xace->add_GeneMethod($meth);
    }
}

## this method stores the defualt GeneMethod values.
### I intended Colin to add this to the config file in order
### to get it out of the code, but he added it here.
sub get_default_GeneMethods{
    my ($self ) = @_ ;       
    my @methods = (

        # note: if the sub category field is 0 it is a parent if it is 1 it is a child of the last parent listed 
        # Method name              Editable?    Coding?  sub-category of?        
        # New set of methods for Otter
        Coding                         => [1,         1,          0],
        Transcript                     => [1,         0,          0],
        Non_coding                     => [1,         0,          1],
        Ambiguous_ORF                  => [1,         0,          1],
        Immature                       => [1,         0,          1],
        Antisense                      => [1,         0,          1],
        IG_segment                     => [1,         1,          0],
        Putative                       => [1,         0,          0],
        Pseudogene                     => [1,         0,          0],
        Processed_pseudogene           => [1,         0,          1],
        Unprocessed_pseudogene         => [1,         0,          1],
        Predicted                      => [1,         0,          0],
        Transposon                     => [1,         1,          0],
	Artifact                       => [1,         0,          0],
	TEC                            => [1,         0,          0],
        # newly added - truncated versions of above methods        
        Coding_trunc                   => [0,         1,          1],
        Transcript_trunc               => [0,         0,          0],
        Non_coding_trunc               => [0,         0,          1],
        Ambiguous_ORF_trunc            => [0,         0,          1],
        Immature_trunc                 => [0,         0,          1],
        Antisense_trunc                => [0,         0,          1],
        IG_segment_trunc               => [0,         1,          0],
        Putative_trunc                 => [0,         0,          0],
        Pseudogene_trunc               => [0,         0,          0],
        Processed_pseudogene_trunc     => [0,         0,          1],
        Unprocessed_pseudogene_trunc   => [0,         0,          1],
        Predicted_trunc                => [0,         0,          0],
	Transposon_trunc               => [0,         1,          0],
	Artifact_trunc                 => [0,         0,          0],
	TEC_trunc                      => [0,         0,          0],
        
        # Auto-analysis gene types (non-editable)
        fgenesh                        => [0,         1],
        FGENES                         => [0,         1],
        GENSCAN                        => [0,         1],
        HALFWISE                       => [0,         0],
        SPAN                           => [0,         0],
        EnsEMBL                        => [0,         1],
        genomewise                     => [0,         1],
        ncbigene                       => [0,         1],
        'WashU-Supported'              => [0,         1],
        'WashU-Putative'               => [0,         0],
        'WashU-Pseudogene'             => [0,         0],
    );
    return @methods;

}

################################################
#
## UTILITY METHODS - MADE FOR YOU
#
################################################

sub fetch_gene_type_prefix {
    return option_from_array([ $CLIENT_STANZA, 'gene_type_prefix' ]);
}

sub fetch_pipeline_switch {
    return option_from_array([ $CLIENT_STANZA, 'pipeline' ]) ? 1 : 0;
}

sub misc_acefile {
    return option_from_array([ $CLIENT_STANZA, 'misc_acefile' ]);
}

sub get_config_list{
    return $CONFIG_INIFILES;
}

sub cmd_line{
    return $CALLED;
}


################################################
#
## INTERNAL METHODS - NOT MADE FOR YOU
#
################################################
# options_from_file

sub options_from_file{
    my ($file, $previous) = @_;
    my $ini;
    return undef unless -e $file;
    eval{
        print STDERR "Trying $file\n" if $DEBUG_CONFIG;
        tie %$ini, 'Config::IniFiles', ( -file => $file, %OPTIONS_TO_TIE) or die $!;
    };
    if($@){
        print STDERR "Tie Failed for '$file': \n". $@;
        return undef;
    }
    return $ini;
}

sub __internal_option_from_array{
    my ($inifiles, $array) = @_;
    return unless tied( %$inifiles );
    my $filename = tied( %$inifiles )->GetFileName();
    warn "option from array inifile called // $inifiles @$array // looking at $filename\n" if $DEBUG_CONFIG;
    my $param = pop @$array;
    my $value = undef;
    my $found = 0;
    my $section = join(".", @$array);

    my $stem_finder = sub {
        my ($s, $p) = @_;
        my $val  = {};
        my $stem = "$s.$p";
        foreach my $k(keys(%$inifiles)){
            $val = { %$val, ($1 => $inifiles->{$k}) } if $k =~ /^$stem\.(.+)/;
        }
        return (scalar(keys(%$val)) ? $val : undef);
    };
    # get the explicit call for a parameter client host
    if(exists $inifiles->{$section} && exists $inifiles->{$section}->{$param}){
        $value = $inifiles->{$section}->{$param};
        $found = 1;
    # get the hash for a block [default.use_filters]
    }elsif(exists $inifiles->{$section. ".$param"}){
        $value = $inifiles->{$section. ".$param"};
        $found = 1;
    # get the hash for a group of blocks [default.filter]
    # will include [default.filter.repeatmask], [default.filter.cpg] ...
    }elsif(my $stem = $stem_finder->($section, $param)){
        $value = $stem;
        $found = 1;
    # all the above failed to find the specified node of tree
    }else{ 
        $found = 0; 
    }
    return ($value, $found);
}

sub set_hash_val{
    my ($hash, $keys, $value) = @_;
    my $lastKey = lc(pop @$keys);
    
    foreach my $key (@$keys) {
	$key = lc $key;
	if (not exists($hash->{$key})) {
	    $hash->{$key} = {};
	} elsif (ref($hash->{$key}) ne 'HASH') {
	    my $oldVal = $hash->{$key};
	    $hash->{$key} = {};
	    warn "Looks like something's been defined twice\n";
	    $hash->{$key}{'_setHashVal_'} = $oldVal;
	}
	# Traverse hash
	$hash = $hash->{$key};
    }
    if(not exists($hash->{$lastKey})){
        $hash->{$lastKey} = $value;
    }elsif(ref($hash->{$lastKey}) eq 'HASH'){
        #warn "Having to use '_setHashVal_' as key and $lastKey $value in hash THIS IS BAD!\n";
        warn "Key '$lastKey' already existed with a hash below. Using '_setHashval_' instead\n";
        $hash->{'_setHashVal_'} = $value;
    }else{
        warn "You've set '@$keys $lastKey' twice. This should be ok\n";
        #use Data::Dumper;
        #warn Dumper $hash->{$lastKey};
        $hash->{$lastKey} = $value;
    }
}




1;



=head1 NAME - Bio::Otter::Lace::Defaults

=head1 DESCRIPTION

Loads default values needed for creation of an
otter client from:

  command line
  ~/.otter_config
  $ENV{'OTTER_HOME'}/otter_config
  /etc/otter_config
  hardwired defaults (in this module)

in that order.  The values filled in, which can
be given by command line options of the same
name, are:

=over 4

=item B<host>

Defaults to B<localhost>

=item B<port>

Defaults to B<39312>

=item B<author>

Defaults to user name

=item B<email>

Defaults to user name

=item B<write_access>

Defaults to B<0>

=back


=head1 EXAMPLE

Here's an example config file:


  [client]
  port=33999

  [default.use_FilteRs]
  trf=1
  est2genome_mouse=1

  [zebrafish.use_filters]
  est2genome_mouse=0

  [default.filter.est2genome_mouse]
  module=Bio::EnsEMBL::Ace::Filter::Similarity::DnaSimilarity
  max_coverage=12


which will make this hash:

    $Bio::Otter::Lace::DEFAULTS = {
        'client' => {
            'port' => 33999,
            },       
        'default' => {
            'use_filters' => {
                'trf' => 1,
                'est2genome_mouse' => 1
                },
            'filter' => {
                'est2genome_mouse' => {
                    'module' => 'Bio::EnsEMBL::Ace::Filter::Similarity::DnaSimilarity',
                    'max_coverage' => 12
                },
            },
        },
        'zebrafish' => {
            'use_filters' => {
                'trf' => 1,
                'est2genome_mouse' => 0,
            },
        },
    };

N.B. ALL hash keys are lower cased to ensure ease
of look up.  You can also specify options on the
command line using the B<cfgstr> option.  Thus:

    -cfgstr zebrafish.use_filters.est2genome_mouse=0

will switch off est2genome_mouse for the
zebrafish dataset exactly as the config file example
above does.

=head1 SYNOPSIS

  use Bio::Otter::Lace::Defaults;

  # Script can add Getopt::Long compatible options
  my $foo = 'bar';
  Bio::Otter::Lace::Defaults::do_getopt(
      'foo=s'   => \$foo,     
      );

  # Make a Bio::Otter::Lace::Client
  my $client = Bio::Otter::Lace::Defaults::make_Client();

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

=cut


__DATA__
##########
## This is where the HARDWIRED ABSOLUTE DEFAULTS are stored
[client]
host=localhost
port=33999
author=
email=
write_access=0
debug=1
pipeline=1 

