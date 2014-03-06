# Attempts to set up a sane otterlace environment for running or testing otterlace
# using *this* ensembl-otter tree.
#
# An installed otterlace elsewhere provides other components.
# If not specified by OTTER_HOME, we attempt to find one.

source "${ANACODE_TEAM_TOOLS}/otterlace/release/scripts/_otterlace.sh" || exit 1
config_get version_major
config_get version_minor

# FIXME: duplication with otterlace_build
if [ -n "$version_minor" ]
then
    # (already tagged by otterlace_release_tag)
    version="${version_major}.${version_minor}"
else
    # (ensembl-otter dev branch)
    version="$version_major"
fi

# sanity check
if [ -z "$version" ]
then
    echo "error: the otterlace version is not set" >&2
    exit 1
fi

# Placeholder for something better, possibly ( built on | similar to )
# otterlace/release/scripts/anacode_source_repo
otter_server_perl5lib="\
$HOME/gitwk-ensembl/ensembl-pipeline/modules:\
/nfs/anacode/WEBVM_docs.dev/apps/webvm-deps/ensembl-branch-74/ensembl-variation/modules\
"


osname="$( uname -s )"
case "$osname" in
    Darwin)
        # If we need a default OTTER_SWAC, take it from OTTER_HOME if we can, else take a stab
        if [ -n "$OTTER_HOME" ]; then
            if [ -z "$OTTER_SWAC" ]; then
                OTTER_SWAC="$( cd -P "${OTTER_HOME}/../.."; pwd )"
            fi
        else
            : ${OTTER_SWAC:=/Applications/otterlace.app/Contents/Resources}
        fi
        printf '  OTTER_SWAC=%s\n' "$OTTER_SWAC"
        export OTTER_SWAC

        if [ -z "$OTTER_HOME" ]; then
            OTTER_HOME="${OTTER_SWAC}/otter/otter_rel${version}"
            if ! grep -q otterlace_installed=true $OTTER_HOME/bin/otterlace; then
                echo "'$OTTER_HOME' is broken." >&2
                exit 1
            fi
        fi
        anasoft="$OTTER_SWAC"
        otter_perl='perl_is_bundled'
        ;;

    *)
        anasoft="/software/anacode"
        if [ -z "$OTTER_HOME" ]; then
            OTTER_HOME="$anasoft/otter/otter_dev"
            # nb. scripts/client/otterlace chases the symlink, we don't bother.
            # otter_dev doesn't leave the previous version around like otter_test
            if ! grep -q otterlace_installed=true $OTTER_HOME/bin/otterlace; then
                echo $OTTER_HOME is broken.
                OTTER_HOME="$anasoft/otter/otter_live"
                echo Switching to $OTTER_HOME
            fi
        fi
        otter_perl="$( dirname $( which perl ) )"
        ;;
esac

ENSEMBL_OTTER_DEV="$( cd -P $( dirname "${BASH_SOURCE[0]}" )/..; pwd )"
export ENSEMBL_OTTER_DEV

printf '  OTTER_HOME=%s\n' "$OTTER_HOME"

source "${ENSEMBL_OTTER_DEV}/scripts/client/_otterlace_env_core.sh"

# Libs which are needed to run tests for Otter Server, but provided or
# requred for otterlace client
PERL5LIB="$PERL5LIB:$otter_server_perl5lib"
