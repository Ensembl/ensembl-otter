
### Bio::Otter::SQL::Clause::ColumnDefinition

package Bio::Otter::SQL::Clause::ColumnDefinition;

use strict;

use base 'Bio::Otter::SQL::Clause';

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub type {
    my( $self, $type ) = @_;
    
    if ($type) {
        $self->{'_type'} = uc $type;
    }
    return $self->{'_type'};
}

sub is_text {
    return shift->type =~ /TEXT/;
}

sub precision {
    my( $self, $precision ) = @_;
    
    if ($precision) {
        $self->{'_precision'} = $precision;
    }
    return $self->{'_precision'};
}

sub add_properties {
    my $self = shift;
    return unless @_;
    
    my $prop = $self->{'_property_list'} ||= [];
    push(@$prop, @_);
}

sub property_list {
    my $self = shift;
    
    if (my $prop = $self->{'_property_list'}) {
        return @$prop;
    } else {
        return;
    }
}

# For ENUM or SET columns
sub add_values {
    my $self = shift;
    return unless @_;
    
    my $prop = $self->{'_value_list'} ||= [];
    push(@$prop, @_);
}

sub value_list {
    my $self = shift;
    
    if (my $prop = $self->{'_value_list'}) {
        return @$prop;
    } else {
        return;
    }
}

sub string {
    my( $self, $name_width ) = @_;
    
    $name_width ||= 20;
    my $str = sprintf "\%-${name_width}s  %s",
        $self->name,
        $self->type;
    if (my $a = $self->precision) {
        $str .= " ($a)";
    }
    elsif (my @values = $self->value_list) {
        $str .= ' (' . join(', ', @values) . ')';
    }
    
    foreach my $prop ($self->property_list) {
        $str .= " $prop";
    }
    
    return $str;
}

sub process_TokenList {
    my( $self, $list ) = @_;

    my $name = $list->next_token;
    $list->fatal_message("Expected column name but got '$name'")
        if $name =~ /\W/;
    $self->name($name);
    my $type = $list->next_token;
    $list->fatal_message("Expected column type but got '$type'")
        if $type =~ /\W/;
    $self->type($type);
    
    my $tok = $list->next_token;
    
    # Get any precision
    if ($tok eq '(') {
        $type = $self->type;
        if ($type eq 'ENUM' or $type eq 'SET') {
            my( @values );
            while (my $tok = $list->next_token) {
                last if $tok eq ')';
                next if $tok eq ',';
                push(@values, $tok);
            }
            $self->add_values(@values);
        } else {
            my $precision = $list->next_token;
            $list->fatal_message("Expected column precision but got '$precision'")
                if $type =~ /\W/;
            $self->precision($precision);
            $list->discard_next(')');
        }
        $tok = $list->next_token;
    }
    
    # Get any addtional column properties
    my( @prop );
    until ($tok eq ')' or $tok eq ',') {
        ### Make more sophisticated (NULL, NOT NULL, AUTO_INCREMENT etc...)
        
        push(@prop, $tok);
        $tok = $list->next_token;
    }
    $list->backup;
    $self->add_properties(@prop);
}

1;

__END__

=head1 NAME - Bio::Otter::SQL::Clause::ColumnDefinition

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

