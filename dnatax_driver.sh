#!/bin/bash

# no SBATCH commands needed because this will just launch the modules

# Set up a usage statement in case this program is called incorrectly
usage() { echo "Make sure to provide a project name" \
                "and one or more SRR accession numbers"
					1>&2;
					echo "Usage: $0 -p PROJECT -s SRR0001 (SRR0002) (SRR...)" \
          1>&2; exit 1; }

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

# Print the project name and sample numbers to the screen
echo "PROJECT name: ${PROJECT}"
echo "SRA sample accession: ${SAMPLES}"

# Make these available to all subsequent scripts
export PROJECT
export SAMPLES

# Launch the setup script
sbatch -p short --mem 2GB -c 1 -t 00-00:05 ./setup.sh

# Launch the script that downloads the SRA files from NCBI
sbatch -p short --mem 50GB -c 1 -t 00-01:00 ./download_sra.sh

# Launch the adapter trimming script
sbatch -p short --mem 50GB -c 1 -t 00-02:00 ./adapter_trimming.sh

# Launch the de novo assembly scripts
export MEM="50" # will be referenced directly by the assembly program
sbatch -p short --mem ${MEM}GB -c 6 -t 01-00:00 ./de_novo_assembly.sh

# Launch the taxonomic classification script
sbatch -p short --mem 50GB -c 6 -t 01-00:00 ./classification.sh

# Launch the script that converts NCBI taxonomy IDs to full taxonomic lineages
sbatch -p short --mem 2GB -c 1 -t 00-01:00 ./fetch_taxonomy.sh

# Launch the script that extracts viral sequences from all the assembled contigs
sbatch -p short --mem 2GB -c 1 -t 00-00:15

# Launch the final save and cleanup script
sbatch -p short --mem 8GB -c 1 -t 00-02:00 ./cleanup.sh
