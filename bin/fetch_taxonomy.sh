#!/bin/bash

#!/bin/bash

################################################################################
# This script will read in the results from DIAMOND and translate the NCBI
# taxon ID into a meaningful taxonomic lineage (domain; kingdom; phylum; ...etc)
#
# The output format is tab delimited text file with the following fields:
# CONTIG-NAME EVALUE SUPERKINGOM KINGDOM PHYLUM CLASS ORDER FAMILY GENUS SPECIES
################################################################################

################################################################################
# Error checking
################################################################################
# If any step fails, the script will stop to prevent propogating errors
set -euo pipefail

# Check to make sure project and sample names are provided
if [[ -z "${PROJECT}" ]] || [[ -z "${SAMPLES}" ]] ;
  then echo "ERROR: Missing Project and/or Sample names." >&2
  exit 1
fi

# Change to the working directory
cd ${WORKING_DIR}

# Check to make sure the diamondToTaxonomy.py script is available
if [[ ! -f scripts/diamondToTaxonomy.py ]] ;
  then echo -e "ERROR: No diamondToTaxonomy.py script found. \nExiting..." >&2
  exit 5
fi
################################################################################

################################################################################
# Taxonomy log info
################################################################################
echo "Beginning taxonomy conversion:" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log
################################################################################

################################################################################
# Convert taxon IDs to full taxonomy strings
################################################################################
cd analysis/diamond/
../../scripts/diamondToTaxonomy.py ${SAMPLES}.nr.diamond.txt
mv ${SAMPLES}.nr.diamond.taxonomy.txt ../taxonomy/
cd ../../
################################################################################

################################################################################
# Taxonomy sequences log info
################################################################################
echo "Finished taxonomy conversion:" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log
################################################################################
