
### Bio::Vega::Transform

package Bio::Vega::Transform;

use strict;
use XML::Parser;
use Data::Dumper;   # For debugging

# This misses the "$VAR1 = " bit out from the Dumper() output
#$Data::Dumper::Terse = 1;

# Using inside-out object design for speed.

my(
	%tag_stack,
	%current_object,
	%current_string,
	%object_builders,
	%object_data,
	%is_multiple,
	%init_builders,
  );

sub DESTROY {
  my ($self) = @_;
  delete $tag_stack{$self};
  delete $current_object{$self};
  delete $current_string{$self};
  delete $object_builders{$self};
  delete $is_multiple{$self};
  delete $init_builders{$self};
  my $data = delete $object_data{$self};
  #printf STDERR "Destroying '%s'\n", ref($self);
  #warn "Unused data after parse: ", Dumper($data);
}

sub new {
  my ($pkg) = @_;
  my $scalar;
  my $self = bless \$scalar, $pkg;
  $self->initialize;
  $tag_stack{$self} = [];
  return $self;
}

sub parse {
  my ($self, $fh) = @_;
  my $parser = $self->new_Parser;
  $parser->parse($fh);
}

sub parsefile {
  my ($self, $filename) = @_;
  my $parser = $self->new_Parser;
  $parser->parsefile($filename);
}

sub new_Parser {
  my ($self) = @_;
  my $parser = XML::Parser->new(
										  ErrorContext    => 3,
										  Handlers => {
															Start => sub { 
															  $self->handle_start(@_);
															},
															End => sub {
															  $self->handle_end(@_);
															},
															Char => sub { 
															  $self->handle_char(@_);
															},
														  },
										 );
  return $parser;
}

sub object_builders {
  my ($self, $value) = @_;
  if ($value) {
	 $object_builders{$self} = $value;
  }
  return $object_builders{$self};
}

sub init_builders {
  my ($self,$value) = @_;
  if ($value) {
	 $init_builders{$self} = $value;
  }
  return $init_builders{$self};
}

sub set_multi_value_tags {
  my ($self, $value) = @_;
  if ($value) {
	 foreach my $row (@$value) {
		my ($context, @ele) = @$row;
		foreach my $element (@ele) {
		  $is_multiple{$self}{$context}{$element} = 1;
		}
	 }
  }
  return $is_multiple{$self};
}

sub handle_start {
  my $self    = shift;
  my $expat   = shift;
  my $element = shift;
  if ($object_builders{$self}{$element}) {
	 # This makes $element the "current context"
	 unshift @{$tag_stack{$self}}, $element;
	 # Anything left in @_ are attribute key, value pairs
	 for (my $i = 0; $i < @_; $i += 2) {
		$object_data{$self}{$element}{$_[$i]} = $_[$i + 1];
	 }
  }
  elsif (@_) {
	 # There are attribtes in a non-object creating tag.
	 $expat->xpcroak(
						  "This parser cannot handle attributes in '$element' tags:\n"
						  . Dumper({@_})
						 );
  }
  if (my $m=$init_builders{$self}{$element}){
	 print STDERR "initialize method called for $element\n";
	 if ($element eq 'otter'){
		$self->$m('otter');
	 }
	 elsif ($element eq 'vega'){
		$self->$m('vega');
	 }
  }
}

sub handle_char {
    my ($self, $expat, $txt) = @_;
    # The character handler may be called multiple times
    # by Expat on a single string. We therefore need
    # to append to the existing string.
    $current_string{$self} .= $txt;
}

sub handle_end {
  my ($self, $expat, $element) = @_;


  if (my $builder = $object_builders{$self}{$element}) {
	 # It is the end of a tag that we use to make an object.
	 # We now have all the data needed, and pass it to the
	 # builder method.
	 my $context = shift @{$tag_stack{$self}};
	 my $data    = delete $object_data{$self}{$context};
	 my $sub_object_data=$current_string{$self};
	 $sub_object_data =~ s/(^\s+|\s+$)//g;
	 if ( length($sub_object_data) !=0){
		delete $current_string{$self};
		$self->$builder($sub_object_data);
	 }
	 else{
		$self->$builder($data);
	 }
  }
  elsif (defined( my $str = delete $current_string{$self} )) {
	 # It is a tag that encloses non-markup text (its value).
	 # We save it under its tag (the key) in the current context.
	 my $context = $tag_stack{$self}[0];
	 $str =~ s/(^\s+|\s+$)//g;
	 #        warn "Setting '$element' to '$str'\n";
	 my $data = $object_data{$self}{$context};
	 if ($is_multiple{$self}{$context}{$element}) {
		# Tag can occur multiple times, so we save it in an array.
		my $list = $data->{$element} ||= [];
		push(@$list, $str);
	 } else {
		# Tag should only occur once, so check that it does not already have a value.
		if (defined( my $value = $data->{$element} )) {
		  # xpcroak method on Expat object gives
		  # some context in the XML.
		  $expat->xpcroak("Setting '$element' in '$context' to '$str' but already set to '$value'");
		} else {
		  $object_data{$self}{$context}{$element} = $str;
		}
	 }
  }
}

1;

__END__

=head1 NAME - Bio::Vega::Transform

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

