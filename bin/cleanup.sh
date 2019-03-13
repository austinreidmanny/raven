#!/bin/bash

################################################################################
# This is a final cleanup script that will save files to a final, permanent
# location and delete all the temporary files
################################################################################

################################################################################
# Error checking
################################################################################
# If any step fails, the script will stop to prevent propogating errors
set -euo pipefail

# Check to make sure project and samples are given
## This script depends on the directory structure established by setup.sh
## Project and Samples are checked by setup.sh, so by extension, if these don't
## exist, then setup.sh wasn't run either
if [[ -z "${PROJECT}" ]] || [[ -z "${SAMPLES}" ]] ;
  then echo "ERROR: Missing Project and/or Sample names." >&2
  exit 1
fi
################################################################################

################################################################################
# Copy results to final, permanent directory
################################################################################
mkdir -p ${FINAL_DIR}/analysis
mkdir -p ${FINAL_DIR}/scripts
mkdir -p ${FINAL_DIR}/data/contigs/

rsync -azv ${WORKING_DIR}/analysis/ ${FINAL_DIR}/analysis
rsync -azv ${WORKING_DIR}/scripts/ ${FINAL_DIR}/scripts
rsync -azv ${WORKING_DIR}/data/contigs/ ${FINAL_DIR}/data/contigs
################################################################################

################################################################################
# Handle FASTQ files
mkdir -p ${FINAL_DIR}/data/raw-sra
mkdir -p ${FINAL_DIR}/data/fastq-adapter-trimmed

echo "FASTQ files not saved long-term; " \
     "may be available in the working directory if needed: ${WORKING_DIR}" > \
     ${FINAL_DIR}/data/raw-sra/README.txt

echo "FASTQ files not saved long-term; " \
     "may be available in the working directory if needed: ${WORKING_DIR}" > \
     ${FINAL_DIR}/data/fastq-adapter-trimmed/README.txt
################################################################################

################################################################################
# Remove temporary files
rm -R ${TEMP_DIR}
################################################################################
