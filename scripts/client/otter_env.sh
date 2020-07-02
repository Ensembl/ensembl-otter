#!/bin/sh
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

source "${OTTER_HOME}/bin/_otter_env_core.sh"
