package ZMap::ConnectUtils;

use strict;
use warnings;
use Exporter;
use X11::XRemote;
use XML::Simple;
use POSIX qw(:signal_h :sys_wait_h);


our @ISA    = qw(Exporter);
our @EXPORT = qw(parse_params 
                 parse_request
                 parse_response
                 xml_escape
                 make_xml
                 obj_make_xml
                 newXMLObj
                 setObjNameValue
                 $WAIT_VARIABLE
                 );
our @EXPORT_OK = qw(xclient_with_id
                    xclient_with_name
                    list_xclient_names
                    delete_xclient_with_id
                    delete_xclient_with_name
                    flush_bad_windows
                    fork_exec
                    reset_sigCHLD
                    );
our %EXPORT_TAGS = ('caching' => [@EXPORT_OK],
                    'all'     => [@EXPORT, @EXPORT_OK]
                    );
our $WAIT_VARIABLE = 0;

my $DEBUG_FORK_EXEC = 0;

=pod

=head1 NAME

ZMap::ConnectUtils

=head1 DESCRIPTION

 functions which might get written over and over again.

=head1 PARSING FUNCTIONS

=head2 parse_params(string)

parse a string like name = value ; name = valU ; called = valid
into 
 {
    name   => [qw(value valU)],
    called  => 'valid'
 }

=cut

sub parse_request{
    my ($xml)  = shift;
    my $parser = XML::Simple->new();
    my $hash   = $parser->XMLin($xml);
    return $hash;
}

sub parse_params{
    warn "This doesn't work anymore!";
#    return {};

    my ($pairs_string) = shift;
    my ($param, $value, $out, $tmp);

    $pairs_string =~ s/\s//g; # no spaces allowed.
    my (@pairs)   = split(/[;]/,$pairs_string);

    foreach (@pairs) {
	($param,$value) = split('=',$_,2);
	next unless defined $param;
	next unless defined $value;
	push (@{$tmp->{$param}},$value);
    }
    # this removes the arrays if there's only one element in them.
    # I'm not sure I like this behaviour, but it means it's not
    # necessary to remember to add ->[0] to everything. 
    $out = { 
        map { scalar(@{$tmp->{$_}}) > 1 ? ($_ => $tmp->{$_}) : ($_ => $tmp->{$_}->[0]) } keys(%$tmp) 
        };
    
    return $out;
}

=head2 parse_response(string)

parse a response into (status, hash of xml)

=cut

sub parse_response{
    my $response = shift;
    my $delimit  = X11::XRemote::delimiter();

    my ($status, $xml) = split(/$delimit/, $response, 2);
    my $parser = XML::Simple->new();
    my $hash   = $parser->XMLin($xml);
    
    return wantarray ? ($status, $hash) : $hash;
}
sub make_xml{
    my ($hash) = @_;
    my $parser = XML::Simple->new(rootname => q{},
                                  keeproot => 1,
                                  );
    my $xml = $parser->XMLout($hash);
    return $xml;
}

sub obj_make_xml{
    my ($obj, $action) = @_;
    return unless $obj && $action;
    my $formatStr = '<zmap action="%s">%s</zmap>';
    return sprintf($formatStr, $action, xmlString($obj));
}
sub xml_escape{
    my $data    = shift;
    my $parser  = XML::Simple->new(NumericEscape => 1);
    my $escaped = $parser->escape_value($data);
    return $escaped;
}

{
    # functions to cache clients
    my $CACHED_CLIENTS = {
        #'0x000000' => ['<X11::XRemote>', 'name']
    };
    my $AUTO_INCREMENT = 0;

=head1 FUNCTIONS TO CACHE CLIENTS

=over 5

=item I<create and retrieve>

=back

=head2 xclient_with_id(id)

return the xclient with specified id, creating if necessary.

=cut

    sub xclient_with_id{
        my ($id) = @_;

        # user can't use a name for some reason, lets make one up
        my $name = __PACKAGE__ . $AUTO_INCREMENT++;

        return xclient_with_name($name, $id);
    }

=head2 xclient_with_name(name, [id])

return the xclient with specified name, creating if id supplied.

=cut

    sub xclient_with_name{
        my ($name, $id) = @_;
        if(!$id){
            # we need to look it up
            ($id) = grep { $CACHED_CLIENTS->{$_}->[1] eq $name } keys %$CACHED_CLIENTS;
        }else{ 
            # check we haven't already got that name
            if(my ($cachedid) = grep { $CACHED_CLIENTS->{$_}->[1] eq $name} keys %$CACHED_CLIENTS){
                unless($id eq $cachedid){
                    warn "we've already got name $name with id $cachedid".
                        " cannot add id $id, try delete_xclient_with_id($id) first\n";
                    return undef;
                }
            }
        }
        return unless $id;

        local *xclient = sub{
            my ($id, $name)   = @_;
            my $client = $CACHED_CLIENTS->{$id}->[0];
            if(!$client){
                $client = X11::XRemote->new(-id     => $id, 
                                            -server => 0,
                                            -_DEBUG => 1
                                            );
                $CACHED_CLIENTS->{$id} = [ $client, $name ];
            }
            #print $client->window_id;

            return $client;
        };

        return xclient($id, $name);
    }

    sub list_xclient_names{
        flush_bad_windows();
        my @list = ();
        foreach my $obj_name(values(%$CACHED_CLIENTS)){
            next if $obj_name->[0]->_is_server();
            push(@list, $obj_name->[1]);
        }
        return @list;
    }

    sub list_xclient_ids{
        return keys %$CACHED_CLIENTS;
    }

=over 5

=item I<removal>

=head2 delete_xclient_with_id(id)

remove the xclient with specified id.

=cut

    # remove
    sub delete_xclient_with_id{
        my ($id) = @_;
        delete $CACHED_CLIENTS->{$id};
    }

=head2 delete_xclient_with_name(name)

remove the xclient with specified name.

=cut

    sub delete_xclient_with_name{
        my ($name) = @_;
        my ($id) = grep { $CACHED_CLIENTS->{$_}->[1] eq $name } keys %$CACHED_CLIENTS;
        delete_xclient_with_id($id);
    }

    sub flush_bad_windows{
        foreach my $id(keys %$CACHED_CLIENTS){
            my $obj = xclient_with_id($id);
            $obj->ping || delete_xclient_with_id($id);
        }
    }
}

{
    # so we can continue to catch sigCHLD 
    # and also provide this clean up to reset sigCHLD
    my $REAPER_REF = undef;

    sub reset_sigCHLD{
        $$REAPER_REF = undef;
        if ($SIG{CHLD}){
            $SIG{CHLD} = 'DEFAULT';
        }
    }

    sub fork_exec{
        my ($command, $children, $filenos, $cleanup) = @_;

        my @command = (ref($command) eq 'ARRAY' ? @$command : ());
        return unless @command;

        $children ||= {};
        $cleanup  = (ref($cleanup) eq 'CODE' ? $cleanup : sub {warn "child: cleaning up..." if $DEBUG_FORK_EXEC});

        my $REAPER = sub {
            my ($child, $continue) = (0,1);
            # If a second child dies while in the signal handler caused by the
            # first death, we won't get another signal. So must loop here else
            # we will leave the unreaped child as a zombie. And the next time
            # two children die we get another zombie. And so on.
            while (($child = waitpid(-1,WNOHANG)) > 0) {
                $children->{$child}->{'CHILD_ERROR'} = $?;
                $children->{$child}->{'ERRNO'} = $!;
                #$children->{$child}->{'ERRNO_HASH'} = \%!;
                $children->{$child}->{'EXTENDED_OS_ERROR'} = $^E;
                #$children->{$child}->{'ENV'} = \%ENV;
                eval { $cleanup->($children) } if WIFEXITED($?);
                if ($@){ 
                    warn "$cleanup->($child) Error, will reset SIGCHLD: $@"; 
                    $continue = 0; 
                }
            }
            #$SIG{CHLD} = \&REAPER;    # THIS DOESN'T WORK
            $SIG{CHLD} = $$REAPER_REF; # ODD BUT THIS DOES....still loathe sysV
            reset_sigCHLD() unless $continue;
        };
        $REAPER_REF = \$REAPER;
        $SIG{CHLD} = $REAPER;
        my $pid;
        if($pid = fork){
            warn "parent: fork() succeeded\n" if $DEBUG_FORK_EXEC;
            $children->{$pid}->{'ARGV'} = "@command";
            $children->{$pid}->{'PID'}  = $pid;
        }elsif($pid == 0){
            my $closeSTDIN  = ($filenos & 1);
            my $closeSTDOUT = ($filenos & (fileno(STDOUT) << 1));
            my $closeSTDERR = ($filenos & (fileno(STDERR) << 1));
            if($DEBUG_FORK_EXEC){
                warn "child: PID = '$$'\n";
                warn "child: closing FILEHANDLES:" 
                    . join(", ",( $closeSTDIN?'STDIN':'')
                           , ( $closeSTDOUT?'STDOUT':'')
                           , ( $closeSTDERR?'STDERR':''))
                    . "\n";
            }
            close(STDIN)  if $closeSTDIN;
            close(STDOUT) if $closeSTDOUT;
            close(STDERR) if $closeSTDERR;
            { exec @command; }
            # HAVE to use CORE::exit as tk redefines it!!!
            warn "child: exec '@command' FAILED\n ** ERRNO $!\n ** CHILD_ERROR $?\n";
            CORE::exit(); 
            # circular and lexicals don't get cleaned up though
            # global destruction cleans them up for us...
            # As we're exiting I don't think we care though
        }else{
            return undef;
        }
        return $pid;
    }
}


#########################
{
    my $encodedXSD = {
        feature => {
            name   => undef,
            style  => undef,
            start  => undef,
            end    => undef,
            strand => undef,
            suid   => undef,
            edit_name  => undef,
            edit_style => undef,
            edit_start => undef,
            edit_end   => undef,
        },
        segment => {
            sequence => undef,
            start    => undef,
            end      => undef,
        },
        client => {
            xwid          => undef,
            request_atom  => undef,
            response_atom => undef,
        },
        location => {
            start => undef,
            end   => undef,
        },
        featureset => {
            suid     => undef,
            features => [],
        },
        error => {
            message => undef,
        },
        meta => {
            display     => undef,
            windowid    => undef,
            application => undef,
            version     => undef,
        },
        response => {},
        zoom_in => {},
        zoom_out => {},
    };
    my @TYPES = keys( %$encodedXSD );

    sub newXMLObj{
        my ($type) = @_;
        $type = lc $type;
        if(grep /^$type$/, @TYPES){
            my $obj = [];
            $obj->[0] = $type;
            $obj->[1] = { %{$encodedXSD->{$type}} };
            return $obj;
        }else{
            return undef;
        }
    }

    sub setObjNameValue{
        my ($obj, $name, $value) = @_;
        return unless $obj && $name && defined($value) && ref($obj) eq 'ARRAY';
        my $type = $obj->[0];
        if((grep /$type/, @TYPES) && exists($encodedXSD->{$type}->{$name})){
            if(ref($encodedXSD->{$type}->{$name}) eq 'ARRAY'){
                push(@{$obj->[1]->{$name}}, $value);
            }else{
                $obj->[1]->{$name} = $value;
            }
        }else{
            warn "Unknown type '$type' or name '$name'\n";
        }
    }

}
sub xmlString{
    my ($obj, $formatStr, @parts, $utype, $uobj) = @_; # ONLY $obj is used.
    return "" unless $obj && ref($obj) eq 'ARRAY';
    $formatStr = "";
    @parts     = ();
    $utype     = $obj->[0];
    $uobj      = $obj->[1];
    if($utype eq 'client'){
        $formatStr = '<client xwid="%s" request_atom="%s" response_atom="%s" />';
        @parts     = map { $uobj->{$_} || '' } qw(xwid request_atom response_atom);
    }elsif($utype eq 'feature'){
        @parts     = map { $uobj->{$_} || '' } qw(suid name style start end strand);
        if($uobj->{'edit_name'} 
           || $uobj->{'edit_start'} 
           || $uobj->{'edit_end'}
           || $uobj->{'edit_style'}){
            $formatStr = '<feature suid="%s" name="%s" style="%s" start="%s" 
                                   end="%s" strand="%s" >
                            <edit name="%s" style="%s" start="%s" end="%s"/>
                          </feature>';
            push(@parts, map{ $uobj->{$_} || '' } qw(edit_name edit_style edit_start edit_end));
        }else{
            $formatStr = '<feature suid="%s" name="%s" style="%s" start="%s" 
                                    end="%s" strand="%s"/>';
        }
    }elsif($utype eq 'featureset'){
        $formatStr = '<featureset suid="%s">%s</featureset>';
        @parts     = map { $uobj->{$_} || '' } qw(suid __empty);
        foreach my $f(@{$uobj->{'features'}}){
            $parts[1] .= xmlString($f);
        }
    }elsif($utype eq 'location'){
        $formatStr = '<location start="%s" end="%s" />';
        @parts     = map { $uobj->{$_} || '' } qw(start end); 
    }elsif($utype eq 'segment'){
        $formatStr = '<segment sequence="%s" start="%s" end="%s" />';
        @parts     = map { $uobj->{$_} || '' } qw(sequence start end);
    }else{
        warn "Unknown object type '$utype'\n";
    }
    return sprintf($formatStr, @parts);
}


1;
__END__

