package Bio::Otter::Log::Log4perl;
use strict;
use warnings;

use base 'Log::Log4perl';
Log::Log4perl->wrapper_register(__PACKAGE__);
# See L<Log::Log4perl/Using-Log::Log4perl-with-wrapper-functions-and-classes>

use Log::Log4perl qw( :levels );


=head1 NAME

Bio::Otter::Log::Log4perl - wrapper on Log::Log4perl

=head1 DESCRIPTION

Using this as a direct replacement for L<Log::Log4perl> prevents both

=over 2

=item 1. Log4perl: Seems like no initialization happened. Forgot to call init()?

=item 2. Suppression of log output, until initialisation is done.

=back

by doing an implicit init when necessary.

=cut


sub import {
    my ($class, @tag) = @_;
    my %tags = map { $_ => 1 } @tag;

    # Export our get_logger, leave everything else to SUPER
    if (delete $tags{get_logger}) {
        my $caller_pkg = caller();
        no strict qw(refs);
        *{"$caller_pkg\::get_logger"} = *get_logger;
    }

    @_ = ($class, keys %tags);
    goto &Log::Log4perl::import;
}

# Called as class method or subroutine, with maybe a $category
sub get_logger {
    my ($called, @arg) = @_;

    # Called as subroutine?  Fix up @arg
    if (!$called || $called ne __PACKAGE__) {
        unshift @arg, $called if defined $called;
        $called = __PACKAGE__;
    }

    # Get a logger for the category of the calling package,
    # by wrapper_register above
    my $logger = $called->SUPER::get_logger(@arg);

    # See L<Log::Log4perl/Initialize-once-and-only-once>
    unless ($called->initialized) {
        my ($prog) = $0 =~ m{([^/%{}]+)$};
        $prog = '(script)' unless defined $prog;

        Log::Log4perl->easy_init({ level => $DEBUG,
                                   layout => "%d $prog.%c %p: %m%n" });

        $logger->warn("$called did implicit init");
    }

    return $logger;
}


1;
