### Bio::Vega::ServerAnalysis::SolexaDepth

package Bio::Vega::ServerAnalysis::SolexaDepth;

use strict;
use warnings;

use Data::Dumper;

use Bio::EnsEMBL::SimpleFeature;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub run {
    my ($self, $features) = @_;
    
    my @depth_features;
    
    my %depth;
    
    my $slice;
    
    for my $af (@$features) {
        $slice ||= $af->slice;
        my @fs = $af->ungapped_features;
        for my $f (@fs) {
            #if ($f->start > 1 and $f->end < $slice->length) {
                for (my $i = $f->start; $i < $f->end; $i++) {
                    $depth{$i}++;    
                }
            #}
        }
    }
    
    my ($start, $end, $tot_depth);
    
    my $i = 0;
    
    for my $b (sort { $a <=> $b } keys %depth) {
        
        if (!$start) {
            $start = $b;
            $end = $b;
        }
        elsif ($b != $end+1) {
            # end this feature
          
            my $sf = Bio::EnsEMBL::SimpleFeature->new(
                -start         => $start,
                -end           => $end+1,
                -strand        => 1,
                -slice         => $slice,
                #-score         => log(($tot_depth / ($end - $start))+1),
                -score         => ($tot_depth / ($end - $start)),
                -display_label => 'solexa_summary_feature_'.$i++,
            );
            
            push @depth_features, $sf;
            
            #print "New feature: $start - $end\n";
            
            $start = $b;
            $end = $b;
            $tot_depth = 0;
        }
        else {
            $end++;
            $tot_depth += $depth{$b};
        }
    }
    
    return @depth_features;
}

1;

__END__

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk


