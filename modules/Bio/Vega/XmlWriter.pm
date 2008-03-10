
### Bio::Vega::XmlWriter

package Bio::Vega::XmlWriter;

use strict;
use Carp;
use Bio::Vega::Utils::XmlEscape qw{ xml_escape };

my (%indent, %level, %open_tag, %string);

sub DESTROY {
    my ($self) = @_;
    
    # Could check here for tags left open or xml string un-flushed.

    delete $indent{$self};
    delete $level{$self};
    delete $open_tag{$self};
    delete $string{$self};
}

sub new {
    my ($pkg, $indent) = @_;
    
    my $scalar;
    my $self = bless \$scalar, $pkg;
    $indent{$self} = $indent || 2;
    $level{$self} = 0;
    $open_tag{$self} = [];
    return $self;
}

sub add_data {
    my ($self, $data) = @_;
    
    $string{$self} .= $data;
}

sub flush {
    my ($self) = @_;
    
    # Could check that we don't have open tags, but might be
    # too restrictive; we might want to send a large quantity
    # of data down a filehandle and close the tags later.
    return delete $string{$self};
}

sub open_tag {
    my ($self, $name, $attr) = @_;
    
    my $tag_str = $self->_begin_tag($name, $attr);

    $tag_str .= qq{>\n};
    push @{$open_tag{$self}}, $name;
    $string{$self} .= $tag_str;
    $level{$self} += $indent;
}

sub close_tag {
    my ($self) = @_;
    
    my $name = pop @{$open_tag{$self}} or confess "No tag to close";
    $level{$self} -= $indent;
    $string{$self} .= $self->_end_tag($name);
}

sub full_tag {
    my ($self, $name, $attr, $data) = @_;

    $string{$self} .= $self->_begin_tag($name, $attr)
        . xml_escape($data)
        . $self->_end_tag($name);
}

sub _begin_tag {
    my ($self, $name, $attr) = @_;
    
    my $tag_str = ' ' x $level{$self} . qq{<$name};
    if ($attr) {
        while (my ($attrib, $value) = each %$attr) {
            $tag_str .= qq{ $name="} . xml_escape($value) . qq{"};
        }
    }
    return $tag_str;
}

sub _end_tag {
    my ($self, $name) = @_;
    
    return ' ' x $level{$self} . qq{</$name>\n};
}

1;

__END__

=head1 NAME - Bio::Vega::Utils::XmlWriter

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

