
### Bio::Otter::SQL::Statement::CreateTable

package Bio::Otter::SQL::Statement::CreateTable;

use strict;
use Carp;
use base 'Bio::Otter::SQL::Statement';
use Bio::Otter::SQL::Clause;


sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}


sub add_ColumnDefinitions {
    my $self = shift;
    return unless @_;
    
    my $prop = $self->{'_ColumnDefinition_list'} ||= [];
    push(@$prop, @_);
}

sub ColumnDefinition_list {
    my $self = shift;
    
    if (my $prop = $self->{'_ColumnDefinition_list'}) {
        return @$prop;
    } else {
        return;
    }
}


sub add_KeyDefinitions {
    my $self = shift;
    return unless @_;
    
    my $prop = $self->{'_KeyDefinition_list'} ||= [];
    push(@$prop, @_);
}

sub set_KeyDefinitions {
    my $self = shift;
    
    $self->{'_KeyDefinition_list'} = [@_];
}

sub KeyDefinition_list {
    my $self = shift;
    
    if (my $prop = $self->{'_KeyDefinition_list'}) {
        return @$prop;
    } else {
        return;
    }
}


sub add_Qualifiers {
    my $self = shift;
    return unless @_;
    
    my $prop = $self->{'_Qualifier_list'} ||= [];
    push(@$prop, @_);
}

sub Qualifier_list {
    my $self = shift;
    
    if (my $prop = $self->{'_Qualifier_list'}) {
        return @$prop;
    } else {
        return;
    }
}

sub set_Qualifier_name_value {
    my( $self, $name, $value ) = @_;
    
    my( $previous );
    foreach my $qual ($self->Qualifier_list) {
        if ($qual->name eq $name) {
            $previous = $qual->value;
            $qual->value($value);
            last;
        }
    }
    unless ($previous) {
        my $qual = Bio::Otter::SQL::Qualifier->new;
        $qual->name($name);
        $qual->value($value);
        $self->add_Qualifiers($qual);
    }
    return $previous;
}

sub make_transactional {
    my $self = shift;

    my $old_type = $self->set_Qualifier_name_value('TYPE', 'InnoDB');
    
    # The default table type is MyISAM
    $old_type ||= 'MyISAM';
    
    my( %text_column );
    foreach my $col ($self->ColumnDefinition_list) {
        if ($col->is_text) {
            $text_column{$col->name} = 1;
        }
    }
    
    my( $key_comments );
    my @keys = $self->KeyDefinition_list;
    KEY: foreach (my $i = 0; $i < @keys; $i++) {
        my $key = $keys[$i];
        foreach my $col ($key->Column_list) {
            if ($text_column{$col->name}) {
                $key_comments .= "\n## $old_type: " . $key->string . "\n";
                splice(@keys, $i, 1);
                next KEY;
            }
        }
    }
    $self->set_KeyDefinitions(@keys);
    if ($key_comments) {
        $self->append_comment($key_comments);
    }
}

{
    my %is_key_type = map {$_, 1} qw{ KEY PRIMARY UNIQUE INDEX };

    sub process_TokenList {
        my( $self, $list ) = @_;

        #warn "Parsing: ", $list->string;

        ### This is the hard bit to write
        my $name = $list->next_token;
        $list->fatal_message("Expected table name but got '$name'")
            if $name =~ /\W/;
        $self->name($name);
        
        $list->discard_next('(');

        # Get column and key creation clauses
        while (my $word = $list->next_token) {
            $list->fatal_message("Expected word or ')' but got '$word'")
                if $word =~ /\W/;
            my( $row );
            if ($is_key_type{uc $word}) {
                $row = Bio::Otter::SQL::Clause::KeyDefinition->new;
                $self->add_KeyDefinitions($row);
            } else {
                $row = Bio::Otter::SQL::Clause::ColumnDefinition->new;
                $self->add_ColumnDefinitions($row);
            }
            $list->backup;
            $row->process_TokenList($list);
            
            my $punc = $list->next_token;
            if ($punc eq ')') {
                last;
            }
            elsif ($punc ne ',') {
                $list->fatal_message("Expected ')' or ',' but got '$punc'");
            }
        }

        # Get any table qualifiers
        while (my $tok = $list->next_token) {
            last if $tok eq ';';
            my $qual = Bio::Otter::SQL::Qualifier->new;
            $qual->name($tok);
            $list->discard_next('=');
            my $value = $list->next_token;
            $list->fatal_message("Expected word but got '$value'")
                if $value =~ /\W/;
            $qual->value($value);
            $self->add_Qualifiers($qual);
        }
    }
}

sub string {
    my $self = shift;
    
    my $indent = '    ';
    my $str = $self->comment_string
        . "CREATE TABLE " . $self->name . " ("
        . join(',', map "\n$indent" . $_->string,
            $self->ColumnDefinition_list);
    if (my @keys = $self->KeyDefinition_list) {
        $str .= ",\n"
            . join(',', map "\n$indent" . $_->string, @keys)
    }
    $str .= "\n)";
    
    if (my @qual = $self->Qualifier_list) {
        #warn "Qualifiers: ", join ', ', map "[$_]", map defined($_) ? $_ : 'undef', @qual;
        $str .= " " . join(" ", map $_->string, @qual);
    }
    $str .= ";\n";
    return $str;
}


1;

__END__

=head1 NAME - Bio::Otter::SQL::Statement::CreateTable

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

