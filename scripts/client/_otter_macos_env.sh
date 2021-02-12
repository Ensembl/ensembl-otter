# Copyright [2018-2019] EMBL-European Bioinformatics Institute
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

export FONTCONFIG_PATH="${OTTER_SWAC}/share/fonts"

# Make etc directory inside ~/.otter to store
# the gdk-pixbuf and pango config files needed
dot_otter=~/.otter
dot_otter_etc="$dot_otter/etc"
mkdir -p "$dot_otter_etc"

if [ -d "${OTTER_SWAC}/lib/gdk-pixbuf-2.0" ]; then
  lib_path="${OTTER_SWAC}/lib"
else
  lib_path="/opt/local/lib"
fi

# Create config file so that gdk-pixbuf can load
# its bitmap image format loaders
export GDK_PIXBUF_MODULE_FILE="$dot_otter_etc/gdk-pixbuf.loaders"

GDK_PIXBUF_MODULEDIR="${lib_path}/gdk-pixbuf-2.0/2.10.0/loaders" \
gdk-pixbuf-query-loaders > "$GDK_PIXBUF_MODULE_FILE"

# Create config files for pango font handling library
pango_module_file="$dot_otter_etc/pango.modules"
export PANGO_RC_FILE="$dot_otter_etc/pangorc"

cat > $PANGO_RC_FILE << PANGO_RC

[Pango]
ModuleFiles = $pango_module_file

PANGO_RC

find "${lib_path}" -name 'libpango*.dylib' -print0 \
| xargs -0 pango-querymodules > "$pango_module_file"

# Need the X11 locale directory
export XLOCALEDIR="${OTTER_SWAC}/share/X11/locale"

unset bin_dir
unset dot_otter
unset dot_otter_etc
unset lib_path

export OTTER_MACOS=1

# EOF
