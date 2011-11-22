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
 
    # group together features by intron
 
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
    
    # and only return the best scoring features per intron
    
    for my $intron (keys %feats_by_introns) {
        my @feats = @{ $feats_by_introns{$intron} };
        if (@feats > $MAX_PER_INTRON) {
            my @sorted = sort { $b->score <=> $a->score } @feats;
            push @filtered, @sorted[0 .. ($MAX_PER_INTRON-1)];
        }
        else {
            push @filtered, @feats;
        }
    }
    
    return @filtered;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

