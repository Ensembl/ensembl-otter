# The guts of setting up MacOS specifics,
# usually called from _otter_env_core.sh.
#
# Assumes that the following have been set:
# OTTER_SWAC (to .../Contents/Resources)

# Set up bits and pieces needed by GTK

if [ -z "$OTTER_SWAC" ]
then
    echo "OTTER_SWAC not set. Script improperly installed." >&2
    exit 1
fi

bin_dir="${OTTER_SWAC}/bin"
export PATH="$bin_dir:$PATH"

export FONTCONFIG_PATH="${OTTER_SWAC}/etc/fonts"

# Make etc directory inside ~/.otter to store
# the gdk-pixbuf and pango config files needed
dot_otter=~/.otter
dot_otter_etc="$dot_otter/etc"
mkdir -p "$dot_otter_etc"

lib_path="${OTTER_SWAC}/lib"

# Create config file so that gdk-pixbuf can load
# its bitmap image format loaders
export GDK_PIXBUF_MODULE_FILE="$dot_otter_etc/gdk-pixbuf.loaders"

GDK_PIXBUF_MODULEDIR="${lib_path}/gdk-pixbuf-2.0/2.10.0/loaders" \
gdk-pixbuf-query-loaders > "$GDK_PIXBUF_MODULE_FILE"

# Need the X11 locale directory
export XLOCALEDIR="${OTTER_SWAC}/share/X11/locale"

unset bin_dir
unset dot_otter
unset dot_otter_etc
unset lib_path

export OTTER_MACOS=1

# EOF
