#!/bin/bash

#SBATCH -t 03-00:00
#SBATCH -p medium
#SBATCH --mem=200G
#SBATCH -c 6
#SBATCH -o logs/slurm-%j.log
#SBATCH -e logs/slurm-%j.err
#SBATCH --mail-type=ALL
#SBATCH --mail-user=austinmanny@g.harvard.edu

################################################################################
# Objective
################################################################################
# This pipeline is be the driver script for DNAtax using the SLURM jobs manager
# Run this by SBATCHing with -p PROJECT & -s SRAaccs (full usage below)
#
# Full DNAtax pipeline downloads FASTQs from the NCBI-SRA, trims adapters,
# performs de novo contig assembly, determines the taxonomic origin of
# each sequence, translates these calls from NCBI TaxonIDs to full taxonomic
# lineages, extracts the viral sequences and saves them to its own FASTA file,
# and saves the results to a final permanent directory and cleans up.
#
# Can customize the last code block to run the just tasks you'd like
################################################################################

################################################################################
# Error checking code to make sure the pipeline is called correctly (don't edit)
################################################################################
set -euo pipefail

# Set up a usage statement in case this program is called incorrectly
usage() { echo -e "ERROR: Missing project and/or sample names. \n" \
              "Make sure to provide a project name, \n" \
              "and one (or more) SRA run numbers separated by commas \n" \
              "Usage: $0 -p PROJECT -s SRR10001,SRR10002,SRR..." >&2; exit 1; }

# Make sure the pipeline is invoked correctly, with project and sample names
while getopts "p:s:" arg; do
	case ${arg} in
		p ) # Take in the project name
		  PROJECT=${OPTARG}
			;;
		s ) # Take in the sample name(s)
                  set -f
                  IFS=","
                  ALL_SAMPLES=(${OPTARG}) # call this when you want every individual sample
                       ;;

		* ) # Display help
		  usage
		       ;;
	esac
done
shift $((OPTIND-1))

# Retrieve last sample using older but cross-platform compatible BASH notation
LAST_SAMPLE=${ALL_SAMPLES[${#ALL_SAMPLES[@]}-1]}

# Create a variable that other parts of this pipeline can use mostly for naming
SAMPLES="${ALL_SAMPLES[0]}-${LAST_SAMPLE}"

# Reset global expansion
set +f

# If the pipeline is not called correctly, tell that to the user and exit
if [[ -z "${PROJECT}" ]] || [[ -z "${SAMPLES}" ]] ; then
	usage
fi
################################################################################

################################################################################
# Print the project name and sample numbers to the screen (don't edit)
################################################################################
echo "PROJECT name: ${PROJECT}"
echo "SRA sample accessions: ${SAMPLES}"

# Make these available to subsequent scripts
export PROJECT
export SAMPLES
export ALL_SAMPLES

# For some reason, BASH won't export ALL_SAMPLES with the underscore
ALLSAMPLES=${ALL_SAMPLES}
export ALLSAMPLES
################################################################################

################################################################################
# Launch the pipeline scripts (CAN CONFIGURE!)
################################################################################
# Can customize, can run the indiviudal modules you need or can run all of them
# Note: setup.sh is basically required

# Launch the setup script
echo "Launching setup.sh script"
. bin/setup.sh
cd ${HOME_DIR}

# Launch the script that downloads the SRA files from NCBI
#echo "Launching download_sra.sh"
. bin/download_sra.sh
cd ${HOME_DIR}

# Launch the adapter trimming script
echo "Launching adapter_trimming.sh"
bin/adapter_trimming.sh

# Launch the de novo assembly scripts
export MAX_MEM="200" # will be referenced directly by the assembly program
echo "Launching de_novo_assembly.sh"
bin/de_novo_assembly.sh

# Launch the taxonomic classification script
echo "Launching classification.sh"
bin/classification.sh

# Launch the script that converts NCBI taxonomy IDs to full taxonomic lineages
echo "Launching fetch_taxonomy.sh"
bin/fetch_taxonomy.sh

# Launch the script that extracts viral sequences from all the assembled contigs
echo "Launching extract_viral.sh"
bin/extract_viral.sh

# Launch the final save and cleanup script
echo "Launching cleanup.sh"
bin/cleanup.sh
################################################################################
