package Bio::Otter::Lace::LogFile;

use strict;
use warnings;
use Symbol 'gensym';
use File::Basename;
use Carp;

$| = 1;

{
    my @tail         = ();
    my $tail_size    = 0;
    my $callback     = undef;
    sub keep_history{
        return unless $tail_size;
        push(@tail, @_);
        $callback->() if ref($callback);
        my $c = scalar @tail - $tail_size;
        return unless $c > 1;
        splice(@tail, 0, $c);
    }
    sub tail_log{
        return (@tail);
    }
    sub set_tail_size{
        my ($size) = shift;
        $size    ||= 20;
        $tail_size = $size;
    }
    sub register_callback{
        $callback = shift if @_;
    }
    sub delete_callback{
        $callback = undef;
    }
}

my $SCRIPT_NAME = basename($ENV{SCRIPT_NAME} || $0);

sub TIEHANDLE{
    my $class = shift;
    my $file  = shift;
    my $fh;
    if(fileno($file) || ref($file) eq 'GLOB'){
	open($fh, ">&=". fileno($file)) || return;
    }else{
	$fh = gensym();
    }
    $SIG{__WARN__} = sub { $^S ? $fh->PRINT("(\$^S true) @_" ) : $fh->_warning(@_); };
    # $^S is true only when in an eval{}
    # see 'perldoc -f eval' and 'man perlvar'
    $SIG{__DIE__}  = sub { $fh->_death(@_) unless $^S; };
    bless $fh, ref($class) || $class;
    $fh->OPEN($file, @_) unless ref($file) eq 'GLOB';
    return $fh;
}
sub EOF     { eof($_[0]) }
sub TELL    { tell($_[0]) }
sub FILENO  { fileno($_[0]) }
sub SEEK    { seek($_[0],$_[1],$_[2]) }
sub CLOSE   { close($_[0]) }
sub BINMODE { binmode($_[0]) }
sub FETCH   { $_[0] }

sub OPEN{
    $_[0]->CLOSE if defined($_[0]->FILENO);
    @_ == 2 ? open($_[0], $_[1]) : open($_[0], $_[1], $_[2]);
}
sub READ     { read($_[0],$_[1],$_[2]) }
sub READLINE { my $fh = $_[0]; <$fh> }
sub GETC     { getc($_[0]) }


sub WRITE{
    my $fh = $_[0];
    $fh->_print(&_log_prefix ." ". substr($_[1],0,$_[2]));
}
sub PRINTF{
    my $fh  = shift;
    my $fmt = shift;
    $fh->_print(&_log_prefix . " " . sprintf($fmt, @_) . "\n");
}
sub PRINT {
    my $fh = shift;
    $fh->_print(&_log_prefix . " @_\n");
}

sub DESTROY{
    my $fh = shift;
    # just implementing this method like this seemed to clean up some weird (!!!) errors
    # not sure if we need UNTIE too....
    #$fh->_print(&_log_prefix . " DESTROY method of LogFile.pm\n");
}

sub _print{
    my ($fh, $message) = @_;
    keep_history($message);
    print $fh $message;
}
sub _warning{
    my $fh = shift;
    $fh->_print(&_log_prefix . " @_");
}
sub _death{
    my $fh = shift;
    # printing to STDOUT is v.eff scary considering this is a tied STDERR fh!!!
    # It does seem to work though and can catch compile time errors.
    # print STDOUT "<otter>\n<response>\nERROR : please email anacode\@sanger.ac.uk for help\n</response>\n<otter>\n";
    $fh->_print(&_log_prefix . Carp::longmess(' Carping from die()...'));
    exit 2;
}

sub _log_prefix{
    if ($ENV{REMOTE_ADDR}) {
        return join(' ', $SCRIPT_NAME , scalar(localtime), $ENV{REMOTE_ADDR});
    } else {
        return join(' ', $SCRIPT_NAME , scalar(localtime));
    }
}
sub import{
    tie(*STDERR, __PACKAGE__, \*STDERR);
}
1;



__END__

=head1 NAME - LogFile.pm

=head1 AUTHOR

Roy Storey,,,, B<email> rds@sanger.ac.uk

