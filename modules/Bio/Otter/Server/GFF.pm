
package Bio::Otter::Server::GFF;

use strict;
use warnings;

use Bio::Otter::Lace::ViaText qw( %LangDesc );
use Bio::Vega::Enrich::SliceGetAllAlignFeatures;
use Bio::Vega::Utils::EnsEMBL2GFF;

use base qw( Bio::Otter::ServerScriptSupport );

my @gff_keys = qw(
    rebase
    gff_source
    gff_seqname
    );

sub send_requested_features {
    my ($pkg) = @_;

    $pkg->send_features(
        sub {
            my ($self) = @_;
            return $self->get_requested_features;
        });

    return;
}

sub send_features {
    my ($pkg, $features_sub) = @_;

    my $self = $pkg->new;

    my $gff;
    if (eval {
        my $features = $features_sub->($self);
        $gff = $self->_features_gff($features);
        1;
        }) {
        $self->compression(1);
        $self->send_response($self->gff_header . $gff);
    }
    else {
        $self->error_exit($@);
    }

    return;
}

sub get_requested_features {

    my ($self) = @_;

    my @feature_kinds  = split(/,/, $self->require_argument('kind'));
    my $analysis_list = $self->param('analysis');
    my @analysis_names = $analysis_list ? split(/,/, $analysis_list) : ( undef );
    my $filter_module = $self->param('filter_module');

    my @feature_list = ();

    foreach my $analysis_name (@analysis_names) {
        foreach my $feature_kind (@feature_kinds) {
            my $param_descs = $LangDesc{$feature_kind}{-call_args};
            my $getter_method = "get_all_${feature_kind}s";

            my @param_list = ();
            foreach my $param_desc (@$param_descs) {
                my ($param_name, $param_def_value, $param_separator) = @$param_desc;

                my $param_value = (scalar(@$param_desc)==1)
                    ? $self->require_argument($param_name)
                    : defined($self->param($param_name))
                    ? $self->param($param_name)
                    : $param_def_value;
                if($param_value && $param_separator) {
                    $param_value = [split(/$param_separator/,$param_value)];
                }
                $param_value = $analysis_name if $param_value =~ /$analysis_name/;
                push @param_list, $param_value;
            }

            my $features = $self->fetch_mapped_features($feature_kind, $getter_method, \@param_list,
                                                        map { defined($self->param($_)) ? $self->param($_) : '' }
                                                        qw(cs name type start end metakey csver csver_remote)
                );

            push @feature_list, @$features;
        }
    }

    if ($filter_module) {
        
        # detaint the module string
        
        my ($module_name) = $filter_module =~ /^((\w+::)*\w+)$/;

        # for the moment be very conservative in what we allow

        if ($module_name =~ /^Bio::Vega::ServerAnalysis::\w+$/) {
            
            eval "require $module_name"; ## no critic(BuiltinFunctions::ProhibitStringyEval)
            
            die "Failed to 'require' module $module_name: $@" if $@;
            
            my $filter = $module_name->new;
            
            $self->log(scalar(@feature_list)." features before filtering...");
            
            @feature_list = $filter->run(\@feature_list);
            
            $self->log(scalar(@feature_list)." features after filtering...");
        }
        else {
            die "Invalid filter module: $filter_module";
        }
    }

    # workaround: some of our pipelines put features on the wrong strand
    if ( $self->param('swap_strands') ) {
        for my $f (@feature_list) {
            if ($f->can('hstrand') && $f->hstrand == -1) {
                $f->hstrand($f->hstrand * -1);
                $f->strand($f->strand * -1);
                $f->cigar_string(join '', reverse($f->cigar_string =~ /(\d*[A-Za-z])/g))
            }
        }
    }

    return \@feature_list;
}

sub gff_header {
    
    my ($self) = @_;
    
    my $name    = $self->param('type');
    my $start   = $self->param('start');
    my $end     = $self->param('end');
    
    if ($self->param('rebase')) {
        $name .= '_'.$start.'-'.$end;
        $end = $end - $start + 1;
        $start = 1;
    }
    
    return Bio::Vega::Utils::GFF::gff_header($name, $start, $end);
}

sub _features_gff {
    my ($self, $features) = @_;

    my %gff_args = map { $_ => $self->param($_) } $self->_gff_keys;
    my $features_gff = join '', map { $_->to_gff(%gff_args) || '' } @{$features};

    return $features_gff;
};

sub _gff_keys {
    return @gff_keys;
}

1;

__END__

=head1 AUTHOR

Jeremy Henty B<email> jh13@sanger.ac.uk

