
### Bio::Otter::SQL::Clause::KeyDefinition

package Bio::Otter::SQL::Clause::KeyDefinition;

use strict;
use base 'Bio::Otter::SQL::Clause';
use Bio::Otter::SQL::Clause::KeyDefinition::Column;

sub type {
    my( $self, $type ) = @_;
    
    if ($type) {
        $self->{'_type'} = uc $type;
    }
    return $self->{'_type'};
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub add_Columns {
    my $self = shift;
    return unless @_;
    
    my $prop = $self->{'_Column_list'} ||= [];
    push(@$prop, @_);
}

sub Column_list {
    my $self = shift;
    
    if (my $prop = $self->{'_Column_list'}) {
        return @$prop;
    } else {
        return;
    }
}

sub string {
    my $self = shift;
    
    my $str = $self->type;
    if (my $n = $self->name) {
        $str .= " $n";
    }
    $str .= ' ('. join(', ', map $_->string, $self->Column_list) . ')';
}


{
    my %is_key_type = map {$_, 1} qw{ KEY PRIMARY UNIQUE INDEX };

    sub process_TokenList {
        my( $self, $list ) = @_;

        # Get index type and name
        my( @types );
        while (my $token = $list->next_token) {
            last if $token eq '(';
            $list->fatal_message("expected word or '(' but got '$token'")
                if $token =~ /\W/;
            if ($is_key_type{uc $token}) {
                push(@types, $token);
            } else {
                $list->fatal_message("Already have key name")
                    if $self->name;
                $self->name($token);
            }
        }
        $list->fatal_message("no types detected in key definition")
            unless @types;
        $self->type(join ' ', @types);  ### Could potentially be more sophisticated
        
        # Get list of columns
        while (my $token = $list->next_token) {
            $list->fatal_message("expected column name but got '$token'")
                if $token =~ /\W/;
            my $column = Bio::Otter::SQL::Clause::KeyDefinition::Column->new;
            $column->name($token);
            $self->add_Columns($column);
            my $punc = $list->next_token;
            
            # Deal with precision definitions
            if ($punc eq '(') {
                my $precision = $list->next_token;
                $list->fatal_message("expected precision but got '$token'")
                    if $token =~ /\W/;
                $column->precision($precision);
                $list->discard_next(')');
                $punc = $list->next_token;
            }
            
            if ($punc eq ')') {
                # At end of column definition
                last;
            }
            elsif ($punc ne ',') {
                # There is another column
                $list->fatal_message("expected comma in key definition but got '$punc'")
                    if $token =~ /\W/;
            }
        }
    }
}

1;

__END__

=head1 NAME - Bio::Otter::SQL::Clause::KeyDefinition

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

