
### Bio::Otter::Lace::PipelineStatus

package Bio::Otter::Lace::PipelineStatus;

use strict;
use Carp;
use Data::Dumper;
use Bio::EnsEMBL::Analysis;


sub new{
    my( $pkg, %args ) = @_;
    my $self = {_runnable_logic_names => [],
                map { "_".lc(substr($_,1)) => $args{$_} } keys(%args)
                };
    return bless $self, $pkg;
}
sub unfinished{
    my $self = shift;
    unless($self->{'_unfinished'}){
        my $full_list  = $self->full();
        my $completed  = $self->completed();
        my $unfinished = {};
        foreach my $logic_name(@$full_list){
            # creates an Analysis object for the incomplete logic_name
            my $anaObj = Bio::EnsEMBL::Analysis->new(-logic_name => $logic_name,
                                                     -created    => 'not run yet',
                                                     -db_version => 'unknown');
            $unfinished->{$logic_name} = $anaObj unless $completed->{$logic_name};
        }
        $self->{'_unfinished'} = $unfinished;
    }
    return $self->{'_unfinished'};
}
sub list_unfinished{
    my ($self, $sep) = @_;
    $sep ||= ", ";
    return join($sep, keys(%{$self->unfinished()}));
}
sub full{
    my $self = shift;
    return $self->{'_runnable_logic_names'} || [];
}
sub unavailable{
    my ($self, $unavailable) = @_;
    $self->{'_unavailable'}  = 1 if $unavailable || !Bio::Otter::Lace::Defaults::fetch_pipeline_switch();
    return $self->{'_unavailable'} || 0;
}
sub completed{
    my $self = shift;
    warn "Get only method" if @_;
    return $self->{'_completed'} || {};
}
sub short_display{
    my $self        = shift;
    my $unavailable = $self->unavailable();
    my $unfinished  = scalar(keys(%{$self->unfinished()}));
    my $display     = "complete";
    return "unavailable" if $unavailable;
    return "missing" if $unfinished;
    return $display;
}

sub add_completedAnalysis{
    my ($self, $ana) = @_;
    if($ana){
        my $exp_object_type = "Bio::EnsEMBL::Pipeline::Analysis";
        my $act_object_type = ref($ana);
        warn "wanted an '$exp_object_type' not an '$act_object_type'" 
            unless $exp_object_type eq $act_object_type;
        my $logic_name = $ana->logic_name();
        $self->{'_completed'} ||= {};
        $self->{'_completed'}->{lc $logic_name} = $ana;
    }
}
################
1;

__END__

=head1 NAME - Bio::Otter::Lace::PipelineStatus

=head1 SYNOPSIS

=head1 DESCRIPTION

Designed to have hold information on the status of a 
CloneSequence in the pipeline.

=head1 AUTHOR

Roy Storey B<email> rds@sanger.ac.uk

