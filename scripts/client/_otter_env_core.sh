# Copyright [2018-2020] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The guts of setting up the otter environment,
# usually called from otter_env.sh which will set:
#
# version
# anasoft
# OTTER_HOME
# otter_perl

# In a development environment, the caller can set:
# ENSEMBL_OTTER_DEV        to override the location of ensembl-otter.
# ENSEMBL_DEV              to override the location of all EnsEMBL packages.
# ANACODE_PERL_MODULES_DEV to override the location of PerlModules.
# OTTER_LIB_PERL5_DEV      to override the location of other perl modules (Zircon).

# check that the installation script has set things up
if [ -z "$version" ] || [ -z "$otter_perl" ]
then
    echo "This script has been improperly installed!  Consult the developers!" >&2
    exit 1
fi

if [ -z "$OTTER_HOME" ]
then
    echo "OTTER_HOME not set. Script improperly installed." >&2
    exit 1
fi

if [ "$otter_perl" = 'perl_is_bundled' ] || [ -x "$otter_perl/perl" ]; then
    # ok
    :
else
    echo "Cannot find Perl at otter_perl=$otter_perl" >&2
    exit 1
fi


# Do not assume client is Inside.
#
# This will not re-configure for laptops which transition from guest
# to/from wired.
case "$( hostname -f 2>/dev/null || hostname )" in
    *.sanger.ac.uk)
        # On wired network.  Need proxy to fetch external resources,
        # but not to reach the Otter Server or a local Apache
        #http_proxy=http://webcache.sanger.ac.uk:3128
        export http_proxy
        no_proxy=.sanger.ac.uk,localhost
        export no_proxy
        ;;
esac

# Copy the *_proxy variables we want into *_PROXY, to simplify logic
if [ -n "$http_proxy" ]; then
    HTTP_PROXY="$http_proxy"
    export HTTP_PROXY
else
    unset  HTTP_PROXY
fi
if [ -n "$no_proxy" ]; then
    NO_PROXY="$no_proxy"
    export NO_PROXY
else
    unset  NO_PROXY
fi

# Copy http_proxy to https_proxy
if [ -n "$http_proxy" ]; then
    https_proxy="$http_proxy"
    HTTPS_PROXY="$http_proxy"
    export https_proxy HTTPS_PROXY
else
    unset  https_proxy HTTPS_PROXY
fi


export OTTER_HOME

LD_LIBRARY_PATH=
export LD_LIBRARY_PATH


# Settings for wublast needed by local blast searches
WUBLASTFILTER=$anasoft/bin/wublast/filter
export WUBLASTFILTER
WUBLASTMAT=$anasoft/bin/wublast/matrix
export WUBLASTMAT

# Some setup for acedb
ACEDB_NO_BANNER=1
export ACEDB_NO_BANNER

#cp -f "$OTTER_HOME/acedbrc" ~/.acedbrc

if [ -n "$ENSEMBL_OTTER_DEV" ]
then
    echo "  DEVEL override for ensembl-otter=        $ENSEMBL_OTTER_DEV"
    ensembl_otter_home="$ENSEMBL_OTTER_DEV"
    ensembl_otter_path="$ENSEMBL_OTTER_DEV/scripts/client"
fi
: ${ensembl_otter_home:=$OTTER_HOME/ensembl-otter}

if [ -n "$ENSEMBL_DEV" ]
then
    echo "  DEVEL override for all EnsEMBL=          $ENSEMBL_DEV"
    ensembl_home="$ENSEMBL_DEV"
fi
: ${ensembl_home:=$OTTER_HOME}

if [ -n "$ANACODE_PERL_MODULES_DEV" ]
then
    echo "  DEVEL override for Anacode Perl Modules= $ANACODE_PERL_MODULES_DEV"
    anacode_perl_modules="$ANACODE_PERL_MODULES_DEV"
fi
: ${anacode_perl_modules:=$OTTER_HOME/PerlModules}

if [ -n "$OTTER_LIB_PERL5_DEV" ]
then
    echo "  DEVEL override for Otter Perl Modules=   $OTTER_LIB_PERL5_DEV"
    otter_lib_perl5="$OTTER_LIB_PERL5_DEV"
fi
: ${otter_lib_perl5:=$OTTER_HOME/lib/perl5}

PERL5LIB="${PERL5LIB:+${PERL5LIB}:}\
$anacode_perl_modules:\
$ensembl_otter_home/modules:\
$ensembl_home/ensembl/modules:\
$otter_lib_perl5:\
$ensembl_otter_home/tk\
"

osname="$( uname -s )"

case "$osname" in
    Darwin)
        anasoft_distro=
        otter_perl=
        PERL5LIB="${PERL5LIB}:\
$anasoft/lib/site_perl:\
$anasoft/lib/perl5/site_perl:\
$anasoft/lib/perl5/vendor_perl:\
$anasoft/lib/perl5\
"
        if [ -z "$OTTER_MACOS" ]
        then
            source "$ensembl_otter_home/scripts/client/_otter_macos_env.sh"
        fi
        ;;

    *)
        distro_code="$( $anasoft/bin/anacode_distro_code )" || {
            echo "Failed to get $anasoft distribution type" >&2
            exit 1
        }
        anasoft_distro="$anasoft/distro/$distro_code"

        PERL5LIB="${PERL5LIB}:\
$anasoft_distro/lib:\
$anasoft_distro/lib/site_perl:\
$anasoft/lib:\
$anasoft/lib/site_perl\
"
        ;;
esac

ensembl_otter_path="${ensembl_otter_path:+$ensembl_otter_path:}\
$OTTER_HOME/bin\
"

otterbin="\
$ensembl_otter_path:\
${anasoft_distro:+$anasoft_distro/bin:}\
$anasoft/bin:\
${otter_perl:+$otter_perl:}\
/software/pubseq/bin/EMBOSS-5.0.0/bin\
"

if [ -n "$ZMAP_BIN" ]
then
    otterbin="$ZMAP_BIN:$otterbin"
    echo "  Hacked otterbin for ZMAP_BIN=$ZMAP_BIN" >&2
fi

if [ -n "$ZMAP_LIB" ]
then
    PERL5LIB="$ZMAP_LIB:$ZMAP_LIB/site_perl:$PERL5LIB"
    echo "  Hacked PERL5LIB for ZMAP_LIB=$ZMAP_LIB" >&2
fi

export PATH="$otterbin${PATH:+:$PATH}"

export PERL5LIB

export ensembl_otter_home
unset ensembl_otter_path
unset otterbin
unset ensembl_home
