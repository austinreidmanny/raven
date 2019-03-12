#!/bin/bash

# no SBATCH commands needed b/c this will just run briefly to launch the modules

################################################################################
# Objective
################################################################################
# This pipeline is be the driver script for DNAtax using the SLURM jobs manager
# Run this interactively by providing -p PROJECT & -s SRAaccs (full usage below)
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
# Set up a usage statement in case this program is called incorrectly
usage() { echo "ERROR: Missing project and/or sample names." \
               "Make sure to provide a project name" \
                "and one or more SRR accession numbers" >&2;
          echo "Usage: $0 -p PROJECT -s SRR0001 (SRR0002) (SRR...)" \
          >&2; exit 1; }

# Make sure the pipeline is invoked correctly, with project and sample names
while getopts "p:s:" arg; do
	case ${arg} in
		p ) # Take in the project name
		  PROJECT=${OPTARG}
                  ;;
		s ) # Take in the sample name(s)
		  SAMPLES=${OPTARG}
                  ;;
		* ) # Display help
		  usage
                  ;;
	esac
done
shift $((OPTIND-1))

# If the pipeline is not called correctly, tell that to the user and exit
if [[ -z "${PROJECT}" ]] || [[ -z "${SAMPLES}" ]] ; then
	usage
fi
################################################################################

################################################################################
# Print the project name and sample numbers to the screen (don't edit)
################################################################################
echo "PROJECT name: ${PROJECT}"
echo "SRA sample accession: ${SAMPLES}"

# Make these available to all subsequent scripts
export PROJECT
export SAMPLES
################################################################################

################################################################################
# Launch the pipeline scripts (CAN CONFIGURE!)
################################################################################
# Can customize, can run the indiviudal modules you need or can run all of them
# Note: setup.sh is basically required

# Launch the setup script
sbatch -p short --mem 2GB -c 1 -t 00-00:05 bin/setup.sh

# Launch the script that downloads the SRA files from NCBI
sbatch -p short --mem 50GB -c 1 -t 00-01:00 bin/download_sra.sh

# Launch the adapter trimming script
sbatch -p short --mem 50GB -c 1 -t 00-02:00 bin/adapter_trimming.sh

# Launch the de novo assembly scripts
export MAX_MEM="50" # will be referenced directly by the assembly program
sbatch -p short --mem ${MAX_MEM}GB -c 6 -t 01-00:00 bin/de_novo_assembly.sh

# Launch the taxonomic classification script
sbatch -p short --mem 50GB -c 6 -t 01-00:00 bin/classification.sh

# Launch the script that converts NCBI taxonomy IDs to full taxonomic lineages
sbatch -p short --mem 2GB -c 1 -t 00-01:00 bin/fetch_taxonomy.sh

# Launch the script that extracts viral sequences from all the assembled contigs
sbatch -p short --mem 2GB -c 1 -t 00-00:15 bin/extract_viral.sh

# Launch the final save and cleanup script
sbatch -p short --mem 8GB -c 1 -t 00-02:00 bin/cleanup.sh
################################################################################

