### Bio::Vega::ServerAnalysis::SolexaIntronFilter

package Bio::Vega::ServerAnalysis::SolexaIntronFilter;

use strict;
use warnings;

my $MAX_PER_INTRON = 10;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub run {
    my ($self, $features) = @_;
    
    my @filtered;
    
    my %feats_by_introns;
 
    for my $af (@$features) {
        my @ugfs = sort { $a->start <=> $b->start } $af->ungapped_features;
        next unless @ugfs > 1;
        my $first_exon = shift @ugfs;
        my $last_exon = pop @ugfs;
        my $intron_string = ($first_exon->end+1).'-';
        for my $f (@ugfs) {
            $intron_string .= ($f->start-1).'_'.($f->end+1).'-';
        }
        $intron_string .= ($last_exon->start-1);
        my $equivs = $feats_by_introns{$intron_string} ||= [];
        push @$equivs, $af; 
    }
    
    for my $intron (keys %feats_by_introns) {
        my @sorted = sort { $b->score <=> $a->score } @{ $feats_by_introns{$intron} };    
        push @filtered, @sorted[0 .. ($MAX_PER_INTRON-1)];
    }
    
    return @filtered;
}

1;

__END__

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk