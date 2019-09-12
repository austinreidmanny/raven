#!/bin/bash

# =================================================================================================#
# adapter_trimming.sh
#     trim adapters from a pair of paired-end sequencing files in fastq format
#     will add support for unpaired reads in the future
# =================================================================================================#
echo -e "Welcome to 'adapter_trimming.sh' !"

# If one step fails, stop the script and exit
set -eo pipefail

# =================================================================================================#
# Ensure the script is called correctly
# =================================================================================================#
# Set up a usage statement in case this program is called incorrectly
usage() { echo -e "\nERROR: Missing sample name (needed for naming files) or input files. \n" \
	          "Proper usage for trimming adapters from paired-end reads: \n\n" \
		  "$0 -s mysample -1 sample-reads_R1.fq -2 sample-reads_R2.fq \n\n" \
		  "Optional parameter: \n" \
		      "-o (output directory for saving trimmed files; [default = './' (current directory)]) \n\n" \
                  "Example of a complex run: \n" \
                  "$0 -s my_sample -1 sample-reads_R1.fq -2 sample-reads_R2.fq -o trimmed_reads/ \n\n" \
       	          "Exiting program. Please retry with corrected parameters..." >&2; exit 1;
        }

# Make sure the pipeline is invoked correctly, with project and sample names
while getopts "s:o:1:2:" arg; do
        case ${arg} in
                s ) # Take in the sample name for naming
                  SAMPLE=${OPTARG}
                        ;;
                1 ) # path to forward reads fastq
                  FORWARD_READS=${OPTARG}
                        ;;
                2 ) # path to reverse reads fastq
                  REVERSE_READS=${OPTARG}
                        ;;
	        o ) # set the output directory
                  OUTPUT_DIRECTORY=${OPTARG}
                        ;;
                * ) # Display help
                  usage
                        ;;
        esac
done
shift $(( OPTIND-1 ))

# Check that required parameters are provided
if [[ -z "${SAMPLE}" ]] || [[ -z "${FORWARD_READS}" ]] || [[ -z "${REVERSE_READS}" ]]; then
	usage
fi

# Set up an empty log file
cat /dev/null > ${SAMPLE}.adapter_trimming.log

# Create an output directory to store the output files
## If user didn't provide one, just use a subdirectory in working directory
if [[ -z ${OUTPUT_DIRECTORY} ]]; then
    OUTPUT_DIRECTORY="./"
    mkdir -p ${OUTPUT_DIRECTORY}

else
    # If user provided a desired output directory: check to make sure output directory doesn't exist;
    # then create output directory; if error, just default to a results subdirectory within current dir
    if [[ ! -d ${OUTPUT_DIRECTORY} ]]; then
        mkdir -p ${OUTPUT_DIRECTORY} || \
        {
            echo "Cannot create user-provided output directory. Defaulting to current working directory './'" | \
                 tee ${SAMPLE}.adapter_trimming.log
            OUTPUT_DIRECTORY="./"
            mkdir ${OUTPUT_DIRECTORY}
        }
    fi
fi
# =================================================================================================#

#==================================================================================================#
# Create conda environment with the necessary software for a more robust, reproducible analysis
#==================================================================================================#
# Necessary bit of code to be able to run conda within a script
eval "$(conda shell.bash hook)"

# Check to see if the trimming conda environment has been set up previously; if not, create it
conda list -n env_trim > /dev/null || \
conda create -n env_trim trim-galore

# Activate the trimming conda environemnt so we can use those tools; if there's a problem, exit
conda activate env_trim > /dev/null || {
    echo "ERROR: Cannot activate conda environment 'env_trim' containing neccessary software." \
         "EXITING..." | tee -a ${SAMPLE}.adapter_trimming.sh; exit 2
}
#==================================================================================================#


function adapter_trimming() {

    #===FUNCTION===================================================================================#
    # Name:        adapter_trimming
    # Description: Trim adapters from raw fastq files
    #==============================================================================================#

    #==============================================================================================#
    # Create conda environment with the necessary software
    #==============================================================================================#
    eval "$(conda shell.bash hook)"
    # Check to see if the trimming conda environment has been set up previously; if not, create it
    conda list -n env_trim > /dev/null || \
        conda create -n env_trim trim-galore

    # Activate the trimming conda environemnt so we can use those tools; if there's a problem, exit
    conda activate env_trim > /dev/null || {
	    echo "ERROR: Cannot activate conda environment 'env_trim' containing neccessary software." \
	         "EXITING..." | tee -a ${SAMPLE}.adapter_trimming.sh; exit 2
            }
    #==============================================================================================#

    #==============================================================================================#
    # Ensure that the necessary software is installed
    command -v trim_galore > /dev/null || {
        echo -e "ERROR: This script requires 'trim_galore' but it could not found. \n" \
	        "Please install this application. \n" \
                "Exiting with error code 6..." >&2; exit 6
        }
    #==============================================================================================#

    #==============================================================================================#
    # Adapter trimming log info
    echo "Began adapter trimming at:    $(date)" | \
        tee -a ${SAMPLE}.adapter_trimming.log
    #==============================================================================================#

    #==============================================================================================#
    # Run TrimGalore! in paired or single end mode, depending on input library type
    #==============================================================================================#

    # I know it is paired-end, so I will hard-code this
    LIB_TYPE="paired"

    ## Paired-end mode
    if [[ ${LIB_TYPE} == "paired" ]]; then
        trim_galore \
        --paired \
        --stringency 5 \
        --quality 1 \
        -o ${OUTPUT_DIRECTORY} \
        --fastqc_args "--outdir ${OUTPUT_DIRECTORY}" \
	--gzip \
	--basename ${SAMPLE} \
	${FORWARD_READS} \
        ${REVERSE_READS}

    else
       echo -e "ERROR: could not determine library type" >&2 \
               "Possibly mixed input libraries: both single & paired-end reads" >&2
       exit 3

    fi
    #==============================================================================================#

    #==============================================================================================#
    # Adapter trimming log info
    echo "Finished adapter trimming at:    $(date)" | \
       tee -a ${SAMPLE}.adapter_trimming.log
    #==============================================================================================#
}

adapter_trimming
