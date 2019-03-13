#!/bin/bash

################################################################################
# This script will extract the viral sequences, save their taxonomy info to
# a tab-delimited text file, and then save the sequences in a FASTA file
################################################################################

###############################################################################
# Error checking
###############################################################################
# If any step fails, the script will stop
set -euo pipefail

# Make sure that seqtk is installed
command -v seqtk || \
echo -e "ERROR: This script requires the tool `seqtk` but could not found. \n" \
        "Please install this application. \n" \
        "Exiting with error code 6..." >&2; exit 6

# Check to make sure sample names are given
if [[ -z "${SAMPLES}" ]] ;
  then echo -e "ERROR: Missing Sample names.\n Exiting with error code 1" >&2
  exit 1
fi

# Check to make sure there is a DIAMOND results file to read from
if [[ ! -f analysis/diamond/${SAMPLES}.nr.diamond.txt ]] ;
then echo -e "ERROR: No DIAMOND results file found. \n" \
             "Exiting with error code 7 ..." >&2; exit 7
fi
###############################################################################

################################################################################
# Viral sequences log info
################################################################################
echo "Beginning extraction of viral sequences at:" >> \
     analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log
################################################################################

################################################################################
# Extract viral sequences and save them to a new file
################################################################################
# Save the virus-specific taxonomy results
grep Viruses analysis/taxonomy/${SAMPLES}.nr.diamond.taxonomy.txt > \
     analysis/viruses/${SAMPLES}.viruses.taxonomy.txt

# Retrieve the viral sequences and save them in a FASTA file
grep Viruses analysis/taxonomy/${SAMPLES}.nr.diamond.taxonomy.txt | \
cut -f 1 | \
seqtk subseq data/contigs/${SAMPLES}.contigs.fasta - > \
      analysis/viruses/${SAMPLES}.viruses.fasta
################################################################################

################################################################################
# Print number of viral sequences
################################################################################
echo "Number of viral contigs in ${SAMPLES}:"
grep "^>" analysis/viruses/${SAMPLES}.viruses.fasta | \
wc -l
################################################################################

################################################################################
# Viral sequences log info
################################################################################
echo "Finished extraction of viral sequences at:" >> \
     analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log
################################################################################
