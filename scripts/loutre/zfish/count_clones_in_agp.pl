# Copyright [2018-2022] EMBL-European Bioinformatics Institute
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

$number;
for ($k = 1; $k < 26; $k++) {
    $name = "chr".$k.".agp";
    open(FH,$name);
    while(<FH>) {
        if (/\s+F\s+/) {
            $number++;
        }
    }
    print "$name\t$number\n";
    $number = 0;
    close FH;
}
open(FH,"chrU.agp");
while (<FH>) {
        if (/\s+F\s+/) {
            $number++;
        }
}
print "chrU.agp\t$number\n";
