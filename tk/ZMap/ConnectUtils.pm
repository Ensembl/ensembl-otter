package ZMap::ConnectUtils;

use strict;
use warnings;
use Exporter;
use X11::XRemote;
use XML::Simple;

our @ISA    = qw(Exporter);
our @EXPORT_OK = qw(parse_request
                    parse_response
                    xml_escape
                    make_xml
                    obj_make_xml
                    newXMLObj
                    setObjNameValue
                    fork_exec
                    );
our %EXPORT_TAGS = ('caching' => [@EXPORT_OK],
                    'all'     => [@EXPORT_OK]
                    );

=pod

=head1 NAME

ZMap::ConnectUtils

=head1 DESCRIPTION

 functions which might get written over and over again.

=head1 PARSING FUNCTIONS

=cut

=head2 parse_response(string)

parse a response into (status, hash of xml)

=cut


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
        if(grep { /^$type$/ } @TYPES){
            my $obj = [];
            $obj->[0] = $type;
            $obj->[1] = { %{$encodedXSD->{$type}} };
            return $obj;
        }else{
            return;
        }
    }

    sub setObjNameValue{
        my ($obj, $name, $value) = @_;
        return unless $obj && $name && defined($value) && ref($obj) eq 'ARRAY';
        my $type = $obj->[0];
        if((grep { /$type/ } @TYPES) && exists($encodedXSD->{$type}->{$name})){
            if(ref($encodedXSD->{$type}->{$name}) eq 'ARRAY'){
                push(@{$obj->[1]->{$name}}, $value);
            }else{
                $obj->[1]->{$name} = $value;
            }
        }else{
            warn "Unknown type '$type' or name '$name'\n";
        }
        return;
    }

}

1;
__END__

