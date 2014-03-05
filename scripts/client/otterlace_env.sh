
# The installation script will append the proper values to these
# lines.  (It stops substituting at the first non-assignment code.)
version=
anasoft=
OTTER_HOME=
otter_perl=

if [ -z "$OTTER_HOME" ]
then
    echo "This script has been improperly installed!  Consult the developers!" >&2
    exit 1
fi

source "${OTTER_HOME}/bin/_otterlace_env_core.sh"
