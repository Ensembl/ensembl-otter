
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
    local $" = '.';
    $DEFAULTS->{"@$option"} ||= { };
    $DEFAULTS->{"@$option"}->{param} = $value ;
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
                   'with-das!'     => sub { $DEFAULTS->{$CLIENT_STANZA}->{'with-das'} = $_[1] },
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
        warn sprintf("got // value '%s', found '%s' //\n",$conf_val||'undef', $found) if $DEBUG_CONFIG;
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


{
    my $METHODS_CACHE = {};
    
    use AceParse qw(aceParse);
    
    sub read_Methods{
        my ($file) = @_;
        return unless $file;
        unless(exists($METHODS_CACHE->{$file})){
            my $tables = {};
            open my $fh, $file || return $tables;
            while(my $table = AceParse->aceTableFromStream($fh)){
                my $class = $table->class;
                my $name  = $table->name;
                next unless $class && $name;
                print STDERR "have $class $name from $file\n";
                if($class eq 'Method'){
                    # rebless as a Bio::EnsEMBL::Ace::Method
                    $table = bless $table, 'Bio::EnsEMBL::Ace::Method';
                    $tables->{$name} = $table;
                }
            }
            close $fh;
            $METHODS_CACHE->{$file} = $tables;
        }
        my $ace_tables = $METHODS_CACHE->{$file};
        return $ace_tables; # these are the methods, keyed on their names
    }

    sub Bio::EnsEMBL::Ace::Method::right_priority{
        return rand(100);
    }



# returns a hash of method objects 
# keyed on Method name.
# The methods are sourced from files held on disk accessed by the operating system
    sub make_ace_methods{

        my $methods = {};

        # get the required options from the config
        my $base_methods_files = option_from_array([qw(client methods_files)]);
        my $groups             = option_from_array([qw(client use_method_groups)]);
        return $methods unless $base_methods_files;
        return $methods unless $groups;
        my @order              = split(',', $groups); # need to keep the order

        # make the objects for the base file
        foreach my $meth_file(split(",", $base_methods_files)){
            $methods = { %$methods, %{read_Methods($meth_file)} };
        }
        
        # need to sort into groups
        # groups defined in the otter_conf
        # keep the order from there!
        my $grps  = {map { $_ => [] } @order};
        foreach my $group(@order){
            print STDERR "looking at method_groups for '$group'\n";
            my $group_members =  option_from_array(['method_groups', $group]);
            $grps->{$group}   = [ split(',', $group_members) ];
        }
        print STDERR Dumper $grps;

        # add further (DAS) objects here, setting right priority to big number (10000)
        # this means they end up at the end of the @sorted list below
        my @userMethods = (); # 
        foreach my $userObj(@userMethods){
            
        }

        # set up right_priority
        # need floor() here somewhere I think
        my $min = 1;
        my $max = 100;
        my $sep = ($max - $min + 1) / (scalar(@order) + 1);
        for my $i(0..scalar(@order)-1){
            my $group   = $order[$i];
            my $members = $grps->{$group};
            print STDERR "@$members\n";
            my $g_min   = $sep * $i;
            my $g_max   = $sep * ($i + 1);
            # get the method objects from the hash
            my @g_Objs  = grep { defined } @$methods{@$members};
            # sort them on their current right_priority
            my @sorted  = sort {$a->right_priority <=> $b->right_priority } @g_Objs;
            my $g_sep   = ($g_max - $g_min + 1) / (scalar(@sorted) + 1);
            my $c_rghtp = $g_min;
            foreach my $obj(@sorted){
                $obj->right_priority($g_min);
                $g_min += $g_sep;
            }
        }

        return $methods;
    }
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

sub get_default_GeneMethods{

    my $stanza = 'gene_methods';
    my %defaults_hash = %{option_from_array([$stanza])};
    my @methods = ();
    # 
    my $EDITABLE   = 0; # is the gene method editable?
    my $CODING     = 1; # is the gene method coding?
    my $IS_SUB_CAT = 2; # is the method a sub category?
    my $TRUNC_VER  = 3; # should I make a truncated version?
    my $ORDER      = 4; # ORDER THE EDITABLE TO MAKE THE TREE WORK

    foreach my $method(keys(%defaults_hash)){
        my $properties = $defaults_hash{$method};
        my $prop_array = [ split(',', $properties) ];
        $defaults_hash{$method} = [ @$prop_array[$EDITABLE..$IS_SUB_CAT], undef, $prop_array->[$ORDER] || 0];
        if($prop_array->[$TRUNC_VER]){
            $defaults_hash{"${method}_trunc"} = [ 0, @$prop_array[$CODING..$IS_SUB_CAT], undef, 0];
        }
    }
    # there must be a better way.
    foreach my $method(sort { $defaults_hash{$a}->[$ORDER] <=> $defaults_hash{$b}->[$ORDER] } keys(%defaults_hash)){
        my $prop_array = $defaults_hash{$method};
        push(@methods, ($method => [ @$prop_array[$EDITABLE..$IS_SUB_CAT] ]));
    }

    return @methods;
}

sub get_dot_otter_config{
    my $configs = get_config_list();
    my $dot_otter_config;
    my ($home_dir) = (getpwuid($<))[7];
    my $location   = "$home_dir/.otter_config";
    foreach my $c(@{$configs}){
        my $obj = tied(%$c);
        next unless $obj;
        $dot_otter_config = $obj if $obj->FileName eq $location;
        last if $dot_otter_config;
    }
    unless($dot_otter_config){
        open(my $fh, ">>$location") || die "ERROR $!";
        close $fh;
        $dot_otter_config = options_from_file($location);
    }
    return $dot_otter_config;
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
    my $param   = pop @$array;
    my $section = join(".", @$array);
    warn sprintf "param '%s' and section '%s'", $param, $section if $DEBUG_CONFIG;
    my $value   = undef;
    my $found   = 0;

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
    # get the hash for a block [default]. this is same as the above but for only single named stanzas!
    }elsif((!$section) && exists $inifiles->{"$param"}){
        $value = $inifiles->{"$param"};
        $found = 1;
    # get the hash for a group of blocks [default.filter]
    # will include [default.filter.repeatmask], [default.filter.cpg] ...
    # this can be a pain, not sure stem finder is working as expected
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
#####################################################
# method groups
# annotation - this is manually annotated stuff
# prediction - automatic annotation
# simple     - simple features repeats etc...
# alignments - Blast results etc...
use_method_groups=annotation,prediction,simple,alignments

[method_groups]
annotation=Transcript
prediction=ensembl,est_genes,fgenesh,genscan
simple=repeats,cpg_islands
alignments=BLASTN,BLASTX,Uniprot


[gene_methods]
#Method name=Editable?,Coding?,Is sub-category?,Has truncated version?, Order (only for editables)
Coding=1,1,0,1,1
Transcript=1,0,0,1,2
Non_coding=1,0,1,1,3
Ambiguous_ORF=1,0,1,1,4
Immature=1,0,1,1,5
Antisense=1,0,1,1,6
IG_segment=1,1,0,1,7
Putative=1,0,0,1,8
Pseudogene=1,0,0,1,9
Processed_pseudogene=1,0,1,1,10
Unprocessed_pseudogene=1,0,1,1,11
Predicted= 1,0,0,1,12
Transposon=1,1,0,1,13
Artifact=1,0,0,1,14
TEC=1,0,0,1,15
# Auto-analysis gene types (non-editable)
fgenesh=0,1
FGENES=0,1
GENSCAN=0,1
HALFWISE=0,0
SPAN=0,0
EnsEMBL=0,1
genomewise=0,1
ncbigene=0,1
WashU-Supported=0,1
WashU-Putative=0,0
WashU-Pseudogene=0,0
 
