=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Bio::Otter::Log::WithContext;

use warnings;
use strict;

use Carp;
use Bio::Otter::Log::Log4perl;
use Log::Log4perl::MDC;

BEGIN {

    Log::Log4perl->wrapper_register(__PACKAGE__);

    my $LOG_LEVEL_ADJUSTMENT = 1;

    my @levels = qw[ trace debug info warn error fatal ];
    my @carps  = qw[ logcarp logcluck logcroak logconfess ];
    my @extras = qw[ logdie logwarn error_warn error_die ];

    my %is_carp = map { $_ => 1 } @carps;

    ## no critic (Variables::ProhibitPackageVars)

    for my $level (@levels, @carps, @extras) {
        my $code = sub {
            my ( $self, @message ) = @_;

            local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth + $LOG_LEVEL_ADJUSTMENT;

            my $new_carplevel = $Carp::CarpLevel;
            $new_carplevel = $new_carplevel + $LOG_LEVEL_ADJUSTMENT if $is_carp{$level};
            local $Carp::CarpLevel = $new_carplevel;

            $self->{save} = Log::Log4perl::MDC->get($self->{key});
            Log::Log4perl::MDC->put($self->{key} => $self->{value});
            $self->{logger}->$level(@message);
            Log::Log4perl::MDC->put($self->{key} => $self->{save});
            delete $self->{save};

            return 1;
        };

        ## no critic (TestingAndDebugging::ProhibitNoStrict)
        no strict 'refs';
        *{$level} = $code;
    }

    for my $level (@levels) {
        my $func = "is_${level}";
        my $code = sub {
            my ( $self, @args ) = @_;

            local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth + $LOG_LEVEL_ADJUSTMENT;

            return $self->{logger}->$func(@args);
        };

        ## no critic (TestingAndDebugging::ProhibitNoStrict)
        no strict 'refs';
        *{$func} = $code;
    }

}

sub _new {
    my ($pkg, $category, $key, $value) = @_;
    $value =~ s/:/../g;     # avoid : to keep logparser code happy
    my $logger = Log::Log4perl->get_logger($category);

    Bio::Otter::Log::Log4perl->check_init($logger);
    # This init will prevent "Forgot to call init()?" and log
    # silencing, but it doesn't make the context visible.

    my $self = bless { logger => $logger, key => $key, value => $value }, $pkg;
    return $self;
}

sub get_logger {
    my ($pkg, $category, $key, $value) = @_;

    $category = scalar caller(1) unless $category;
    $key   = 'name'      unless defined $key;
    $value = '-default-' unless defined $value;

    return $pkg->_new($category, $key, $value);
}

sub DESTROY {
    my ($self) = @_;
    if ($self->{save}) {
        Log::Log4perl::MDC->put($self->{key} => $self->{save});
        delete $self->{save};
    }
    return;
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
