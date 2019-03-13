#!/bin/bash

###############################################################################
# This script will set up the computational environment for the pipeline
###############################################################################

###############################################################################
# Error checking
###############################################################################
# If any step fails, the script will stop
set -euo pipefail

# Check to make sure project and samples are given
if [[ -z "${PROJECT}" ]] || [[ -z "${SAMPLES}" ]] ;
  then echo "ERROR: Missing Project and/or Sample names." >&2
  exit 1
fi

# Set up directory structure, as such #

# Project/
#  > data
#  > analysis
#  > scripts

# Will run all the analysis in scratch space (maximum read/write speed)
# Will allocate specific temp space that is deleted at end of job
# Will save final results in a permanent space

###############################################################################
# Customize the paths for Home, Working, Temp, and Final directories #
###############################################################################
export HOME_DIR=`pwd`
export WORKING_DIR="/n/scratch2/am704/nibert/${PROJECT}/"
export TEMP_DIR="/n/scratch2/am704/tmp/${PROJECT}/${SAMPLES}/"
export FINAL_DIR="/n/data1/hms/mbib/nibert/austin/${PROJECT}/"
export DIAMOND_DB_DIR="/n/data1/hms/mbib/nibert/austin/diamond/nr"
###############################################################################

# Create these directories
mkdir -p ${WORKING_DIR}
mkdir -p ${TEMP_DIR}
mkdir -p ${FINAL_DIR}

# Change to the working directory
cd ${WORKING_DIR}

# Setup data subdirectory
mkdir -p data/contigs
mkdir -p data/raw-sra
mkdir -p data/fastq-adapter-trimmed

# Setup analysis subdirectory
mkdir -p analysis/timelogs
mkdir -p analysis/contigs
mkdir -p analysis/diamond
mkdir -p analysis/taxonomy
mkdir -p analysis/viruses

# Setup scripts subdirecotry
mkdir -p scripts

# Copy key scripts (taxonomy and yaml-config-builders) from HOME to WORKING dir
if [[ -f ${HOME_DIR}/diamondToTaxonomy.py ]] && \
   [[ -f ${HOME_DIR}/yaml_spades_pairedreads.sh && || \
   [[ -f ${HOME_DIR}/yaml_spades_singlereads.sh]];

  then echo "All neccessary scripts are available to copy. COPYING...";
  cp ${HOME_DIR}/diamondToTaxonomy.py scripts/
  cp ${HOME_DIR}/yaml_spades_pairedreads.sh scripts/
  cp ${HOME_DIR}/yaml_spades_singlereads.sh scripts/;

# If the scripts are not available to copy, then tell user where to download
# them, then exit
else
  echo "One or more of the following scripts are missing:" \
       "diamondToTaxonomy.py, yaml_spades_pairedreads.sh, " \
       "yaml_spades_singlereads.sh" >&2
  echo "Please download these from github.com/austinreidmanny/dnatax" >&2
  echo "ERROR: Cannot find mandatory helper scripts. Exiting" >&2
  exit 1
fi

# Setup script has finished
echo "Setup complete"
