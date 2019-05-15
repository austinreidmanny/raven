#!/bin/bash

#==================================================================================================#
# DNAtax
#==================================================================================================#
# This pipeline is be the driver script for DNAtax using the SLURM jobs manager
# Run this interactively by providing -p PROJECT & -s SRAaccs (full usage below)
#
# Full DNAtax pipeline downloads FASTQs from the NCBI-SRA, trims adapters,
# performs de novo contig assembly, determines the taxonomic origin of
# each sequence, translates these calls from NCBI TaxonIDs to full taxonomic
# lineages, extracts the viral sequences and saves them to its own FASTA file,
# and saves the results to a final permanent directory and cleans up.
#==================================================================================================#

function usage() {
    #==== FUNCTION ================================================================================#
    #        NAME: usage
    # DESCRIPTION: setup a usage statement that will inform the user how to correctly invoke the
    #              program
    #==============================================================================================#

    echo -e "ERROR: Missing project and/or sample names. \n" \
            "Make sure to provide a project name, \n" \
            "and one (or more) SRA run numbers separated by commas \n" \
            "Usage: $0 -p PROJECT -s SRR10001,SRR10002,SRR..." >&2
            exit 1;
}

function read_user_parameters() {
    #==== FUNCTION ================================================================================#
    #        NAME: read_user_parameters
    # DESCRIPTION: take in the project name and SRA accession numbers provided by user and make sure
    #              the pipeline is invoked correctly
    #==============================================================================================#

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
}

function process_names() {
    #==== FUNCTION ================================================================================#
    #        NAME: process_names
    # DESCRIPTION: use the user-provided parameters above to create variable names that can be
    #              called in the rest of the pipeline
    #==============================================================================================#

    # Retrieve name of the last sample (uses  older but cross-platform compatible BASH notation)
    LAST_SAMPLE=${ALL_SAMPLES[${#ALL_SAMPLES[@]}-1]}

    # Create a variable that other parts of this pipeline can use mostly for naming
    SAMPLES="${ALL_SAMPLES[0]}-${LAST_SAMPLE}"

    # Reset global expansion [had to change to read multiple sample names]
    set +f

    # If the pipeline is not called correctly, tell that to the user and exit
    if [[ -z "${PROJECT}" ]] || [[ -z "${SAMPLES}" ]] ; then
    	usage
    fi

    # As a check to the user, print the project name and sample numbers to the screen
    echo "PROJECT name: ${PROJECT}"
    echo "SRA sample accessions: ${SAMPLES}"

    # Make these available to subsequent child scripts
    export PROJECT
    export SAMPLES
}

#==================================================================================================#
# Run the initial setup steps
read_user_parameters
process_names
#==================================================================================================#

function setup_project_stucture() {
    # Launch the setup script
    echo "Launched setup.sh script"
    bin/setup.sh
}

function download_sra() {
    # Launch the script that downloads the SRA files from NCBI
    echo "Launched download_sra.sh"
    bin/download_sra.sh
}

function adapter_trimming() {
    # Launch the adapter trimming script
    bin/adapter_trimming.sh
}

function de_novo_assembly() {
    # Launch the de novo assembly scripts
    echo "Launched de_novo_assembly.sh"
    export MAX_MEM="50" # will be referenced directly by the assembly program
    bin/de_novo_assembly.sh
}

function classification() {
    # Launch the taxonomic classification script
    echo "Launched classification.sh"
    bin/classification.sh
}

function taxonomy() {
    # Launch the script that converts NCBI taxonomy IDs to full taxonomic lineages
    echo "Launched fetch_taxonomy.sh"
    bin/fetch_taxonomy.sh
}

function extract_viral() {
    # Launch the script that extracts viral sequences from all the assembled contigs
    echo "Launched extract_viral.sh"
    bin/extract_viral.sh
}

function cleanup() {
    # Launch the final save and cleanup script
    echo "Launched cleanup.sh"
    bin/cleanup.sh
}

#==================================================================================================#
# Run the pipeline
#==================================================================================================#

setup_project_stucture
download_sra
adapter_trimming
de_novo_assembly
classification
taxonomy
extract_viral
cleanup

#==================================================================================================#
