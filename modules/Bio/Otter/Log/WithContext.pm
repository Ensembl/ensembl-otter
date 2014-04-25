package Bio::Otter::Log::WithContext;

use warnings;
use strict;

use Carp;
use Log::Log4perl;
use Log::Log4perl::MDC;

BEGIN {

    Log::Log4perl->wrapper_register(__PACKAGE__);

    my $LOG_LEVEL_ADJUSTMENT = 1;

    my @levels = qw[ trace debug info warn error fatal ];
    my @carps  = qw[ logcarp logcluck logcroak logconfess ];
    my @extras = qw[ logdie logwarn error_warn error_die ];

    my %is_carp = map { $_ => 1 } @carps;

    ## no critic (Variables::ProhibitPackageVars)
    ## no critic (TestingAndDebugging::ProhibitNoStrict)

    for my $level (@levels, @carps, @extras) {
        no strict 'refs';

        *{$level} = sub {
            my ( $self, @message ) = @_;

            local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth + $LOG_LEVEL_ADJUSTMENT;

            my $new_carplevel = $Carp::CarpLevel;
            $new_carplevel = $new_carplevel + $LOG_LEVEL_ADJUSTMENT if $is_carp{$level};
            local $Carp::CarpLevel = $new_carplevel;

            my $save = Log::Log4perl::MDC->get($self->{key});
            Log::Log4perl::MDC->put($self->{key} => $self->{value});
            $self->{logger}->$level(@message);
            Log::Log4perl::MDC->put($self->{key} => $save);

            return 1;
        };
    }

    for my $level (@levels) {
        no strict 'refs';

        my $func = "is_${level}";
        *{$func} = sub {
            my ( $self, @args ) = @_;

            local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth + $LOG_LEVEL_ADJUSTMENT;

            return $self->{logger}->$func(@args);
        };
    }

}

{
    my %CONTEXT_LOGGER;

    sub _new {
        my ($pkg, $category, $key, $value) = @_;
        my $logger = Log::Log4perl->get_logger($category);
        my $self = bless { logger => $logger, key => $key, value => $value }, $pkg;
        return $CONTEXT_LOGGER{$category}->{$key}->{$value} = $self;
    }

    sub get_logger {
        my ($pkg, $category, $key, $value) = @_;

        $category = scalar caller(1) unless $category;
        $key   = 'core' unless defined $key;
        $value = 1      unless defined $value;

        my $logger = $CONTEXT_LOGGER{$category}->{$key}->{$value};
        return $logger if $logger;
        return $pkg->_new($category, $key, $value);
    }
}

1;

__END__

=head1 NAME

Bio::Otter::Log::WithContext - log with context info provided by class calling get_logger().

=head1 SYNOPSIS

  my $log_pattern = '%d %c %p [%X{name}]: %m%n';
  ...
  $self->name('foo_23');
  my $logger = Bio::Otter::Log::WithContext->get_logger($category, name => $self->name);
  $logger->debug('now with added context')

C<2014/04/25 16:13:45 Bio.Otter.Foo DEBUG [foo_23]: now with added context>

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

# EOF
