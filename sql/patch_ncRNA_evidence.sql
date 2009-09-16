################################################################################
#
# Patch file
# Extend the list of possible evidence type with ncRNA
#

ALTER TABLE evidence
MODIFY type ENUM('EST','ncRNA','cDNA','Protein','Genomic','UNKNOWN')
