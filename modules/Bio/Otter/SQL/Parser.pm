
### Bio::Otter::SQL::Parser

package Bio::Otter::SQL::Parser;

use strict;
use Symbol 'gensym';
use Text::ParseWords 'quotewords';
use Bio::Otter::SQL::StatementSet;
use Bio::Otter::SQL::TokenList;
use Bio::Otter::SQL::Statement::CreateTable;

sub new {
    return bless {}, shift;
}

sub parse_file {
    my( $self, $file_name ) = @_;
    
    my $fh = gensym();
    open $fh, $file_name or die "Can't read '$file_name' : $!";
    my $set = parse_fh($fh);
    close $fh;
    return $set;
}

sub parse_fh {
    my( $self, $fh ) = @_;
    
    my( @tokens, $comments );
    my $set = Bio::Otter::SQL::StatementSet->new;
    while (<>) {
        if (/^\s*(#|$)/) {
            #warn "COMMENT: $_";
            $comments .= $_;
            next;
        }
        
        my @line = grep defined($_), quotewords('[\s,\(\);=#]+', 'delimiters', $_);
        for (my $i = 0; $i < @line;) {
            my $tok = $line[$i];
            #warn "TOKEN: [$tok]\n";
            
            # Comments on the end of lines - nasty
            if ($tok =~ s/^([\W]*)#/#/) {
                $line[$i] = $tok;
                my $cmt = join('', splice(@line, $i));
                #warn "Adding '$cmt' to comments\nline now contains:\n", join('', @line), "\n";
                $comments .= $cmt;
                $line[$i] = $tok = $1;
            }
            
            if ($tok =~ /;\s*$/) {
                my $token_list = Bio::Otter::SQL::TokenList->new;
                foreach (@tokens, splice(@line, 0, $i + 1)) {
                
                    # Skip empty tokens
                    next unless /\S/;
                    
                    # Strip trailing and leading whitespace from all tokens
                    s/(^\s+|\s+$)//g;
                    
                    # Words begin with a quote (data)
                    # or contain word characters (sql keywords)
                    if (/(^["']|\w)/) {
                        $token_list->add_tokens($_);
                    } else {
                        #warn "ADDING: $_\n";
                        # Split strings of multiple punctuation into separate tokens
                        $token_list->add_tokens(unpack 'a' x length($_), $_);
                    }
                }
                if ('CREATE' eq uc $token_list->next_token
                 and 'TABLE' eq uc $token_list->next_token) {
                    my $st = Bio::Otter::SQL::Statement::CreateTable->new;
                    $st->comment_string($comments);
                    $st->process_TokenList($token_list);
                    $set->add_Statement($st);
                } else {
                    $set->add_Statement($token_list);
                    #warn "Skipping unknown statement type:\n", $token_list->string;
                }
                @tokens = ();
                $comments = '';
                $i = 0;
            } else {
                $i++;
            }
        }
        push(@tokens, @line);
    }
    if (length($comments)) {
        $set->add_Statement(
            Bio::Otter::SQL::Comment->new($comments)
            );
    }
    return $set;
}


1;

__END__

=head1 NAME - Bio::Otter::SQL::Parser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

