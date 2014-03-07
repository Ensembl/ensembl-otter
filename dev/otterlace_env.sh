# Attempts to set up a sane otterlace environment for running or testing otterlace
# using *this* ensembl-otter tree.
#
# An installed otterlace elsewhere provides other components.
# If not specified by OTTER_HOME, we attempt to find one.

ENSEMBL_OTTER_DEV="$( cd -P $( dirname "${BASH_SOURCE[0]}" )/..; pwd )"
export ENSEMBL_OTTER_DEV

source "${ANACODE_TEAM_TOOLS}/otterlace/release/scripts/_otterlace.sh" || exit 1

version="dev-from-checkout" # required to be set, but not used?

# Placeholder for something better, possibly ( built on | similar to )
# otterlace/release/scripts/anacode_source_repo
otter_server_perl5lib="\
$HOME/gitwk-ensembl/ensembl-pipeline/modules:\
/nfs/anacode/WEBVM_docs.dev/apps/webvm-deps/ensembl-branch-74/ensembl-variation/modules\
"

# Input: $ENSEMBL_OTTER_DEV $OTTER_SWAC optional:$1
# Output: Set $OTTER_HOME which looks installed, or fail
__otter_find_installed() {
    local leafname
    leafname="$1"
    if ! OTTER_HOME=$(
            if [ -n "$leafname" ]; then
                # construct path to some designated release
                # scripts/client/otterlace chases the symlink, but we don't bother.
                # (otter_dev doesn't leave the previous version around like otter_test)
                otter_swac=$OTTER_SWAC otter_ipath_get "" holtdir && \
                    printf '/%s' "$leafname"
            else
                # construct path from full version, including feature branch
                cd $ENSEMBL_OTTER_DEV
                otter_swac=$OTTER_SWAC otter_ipath_get "" otter_home
            fi
        ); then
        # failed to get a path
        printf "    otter_ipath_get failed to derive OTTER_HOME from\n      OTTER_SWAC=%s plus ENSEMBL_OTTER_DEV=%s - are we in the right place?\n" \
            "$OTTER_SWAC" "$ENSEMBL_OTTER_DEV" >&2
        return 1
    elif ! [ -d "$OTTER_HOME" ]; then
        printf "    OTTER_SWAC=%s plus ENSEMBL_OTTER_DEV=%s\n      makes OTTER_HOME=%s ,\n      but that is not a directory\n" \
            "$OTTER_SWAC" "$ENSEMBL_OTTER_DEV" "$OTTER_HOME" >&2
        return 1
    elif ! grep -q otterlace_installed=true $OTTER_HOME/bin/otterlace; then
        printf "    OTTER_HOME=%s: broken or not properly installed." \
            "$OTTER_HOME" >&2
        return 1
    fi
    # variable OTTER_HOME is set, under $OTTER_SWAC
    return 0
}

if [ -n "$OTTER_HOME" ]; then
    printf "[w]   Called with OTTER_HOME=%s - risk of shadowing from environment already set up?\n\n" "$OTTER_HOME" >&2
fi

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
            __otter_find_installed || bail "Could find no OTTER_HOME"
        fi
        anasoft="$OTTER_SWAC"
        otter_perl='perl_is_bundled'
        ;;

    *)
        anasoft="/software/anacode"
        if [ -z "$OTTER_HOME" ]; then
            __otter_find_installed \
                || __otter_find_installed otter_dev \
                || __otter_find_installed otter_live \
                || bail "Could find no OTTER_HOME"
        fi
        otter_perl="$( dirname $( which perl ) )"
        ;;
esac

printf '  OTTER_HOME=%s\n' "$OTTER_HOME"

source "${ENSEMBL_OTTER_DEV}/scripts/client/_otterlace_env_core.sh" || exit 5

# Libs which are needed to run tests for Otter Server, but provided or
# requred for otterlace client
PERL5LIB="$PERL5LIB:$otter_server_perl5lib"
