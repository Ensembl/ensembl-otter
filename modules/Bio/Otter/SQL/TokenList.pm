
### Bio::Otter::SQL::TokenList

package Bio::Otter::SQL::TokenList;

use strict;
use Carp;

sub new {
    return bless {}, shift;
}

sub add_tokens {
    my $l = shift->{'_tokens'} ||= [];
    push(@$l, @_);
}

sub next_token {
    my $self = shift;
    
    my $i    = $self->{'_index'} ||= 0;
    my $list = $self->{'_tokens'} or return;
    if (defined(my $token = $list->[$i])) {
        $self->{'_index'} = $i + 1;
        return $token;
    } else {
        $self->{'_index'} = undef;
        return;
    }
}

sub previous_token {
    my $self = shift;
    
    my $i    = $self->{'_index'}  or return;
    my $list = $self->{'_tokens'} or return;
    if (defined(my $tok = $list->[$i-2])) {
        return $tok;
    } else {
        return;
    }
}

sub token_list {
    my $self = shift;
    
    if (my $l = $self->{'_tokens'}) {
        return @$l;
    } else {
        return;
    }
}

sub reset {
    shift->{'_index'} = undef;
}

sub backup {
    my $self = shift;
    
    $self->{'_index'}  or return;
    $self->{'_index'}--;
}

sub string {
    my( $self, $error_i, $error_indicator ) = @_;
    
    my $save_i = $self->{'_index'};
    $self->reset;
    
    if (defined $error_i) {
        $error_indicator ||= '>>>>>';
    }
    
    my $indent = '    ';
    
    my $level = 0;
    my $str = '';
    my $first = 1;
    while (my $token = $self->next_token) {
        
        if ($error_i and $self->{'_index'} == $error_i) {
            $str .= $error_indicator;
        }
        
        if ($token eq '(') {
            $level++;
            if ($level == 1) {
                $str .= " (\n" . $indent;
            } else {
                $str .= " (";
            }
        }
        elsif ($token eq ')') {
            $level--;
            $str .= $level > 0 ? ')' : "\n)";
        }
        elsif ($token eq ',') {
            if ($level == 1) {
                $str .= ",\n" . $indent;
                $first = 1;
            } else {
                $str .= ',';
            }
        }
        elsif ($first) {
            $str .= $token;
            $first = 0;
        }
        else {
            my $previous = $self->previous_token;
            if ($previous and $previous eq '(') {
                $str .= $token;
            }
            elsif ($token !~ /\w/) {
                $str .= $token;
            }
            else {
                $str .= " $token";
            }
        }
    }
    $str .= "\n";
    
    $self->{'_index'} = $save_i;
    
    return $str;
}

sub fatal_message {
    my( $self, @msg ) = @_;
    
    my $i = $self->{'_index'};
    $self->reset;
    my $indicator = '>>>>>';
    confess "\nERROR: @msg at '$indicator' indicator in statement:\n", $self->string($i, $indicator);
}

sub discard_next {
    my( $self, $expect ) = @_;
    
    my $next = $self->next_token;
    if ($expect ne $next) {
        $self->fatal_message("Expected '$expect' but next token was '$next'");
    }
}


1;

__END__

=head1 NAME - Bio::Otter::SQL::TokenList

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

