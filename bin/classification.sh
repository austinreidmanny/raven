#!/bin/bash

################################################################################
# This script will take each newly assembled contig and query them against
# a given database (filepath provided by user in the `setup.sh` script)
# to determine the most likely taxonomic origin of each sequence
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

# Check for a DIAMOND database to use
if [[ -z "${DIAMOND_DB_DIR}" ]] ; then
  then echo -e "ERROR: Missing directory for Diamond database. \n" \
               "Please specify this DIAMOND_DB_DIR value in the setup.sh " \
               "script"   >&2
       exit 4
fi
################################################################################

################################################################################
# DIAMOND log start
################################################################################
echo "Began taxonomic classification at:" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log
################################################################################

################################################################################
# Classify the contigs with Diamond
################################################################################
# (Parameters 'block-size' and 'index-chunks' optimized for 50GB memory)

diamond \
blastx \
--verbose \
--more-sensitive \
--threads 6 \
--db ${DIAMOND_DB_DIR} \
--query data/contigs/${SAMPLES}.contigs.fasta \
--out analysis/diamond/${SAMPLES}.nr.diamond.txt \
--outfmt 102 \
--max-hsps 1 \
--top 1 \
--block-size 5 \
--index-chunks 2 \
--tmpdir ${TEMP_DIR}
################################################################################

################################################################################
# DIAMOND log end
echo "Finished taxonomic classification:" >> analysis/timelogs/${SAMPLES}.log
date >> analysis/timelogs/${SAMPLES}.log
################################################################################
