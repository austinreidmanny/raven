#!/bin/bash

function usage() {
    #==== FUNCTION ================================================================================#
    #        NAME: usage
    # DESCRIPTION: setup a usage statement that will inform the user how to correctly invoke the
    #              program
    #==============================================================================================#

    echo -e "\nERROR: Missing SRA accessions. \n" \
            "Make sure to provide one (or more) SRA run numbers separated by commas \n\n" \
            "Usage: $0 -s SRR10001,SRR10002,SRR... \n\n" \
            "Optional parameters: \n" \
                  "-o (ouptut directory for saving the SRA files at the end; [default=current folder]) \n" \
                  "-m (maximum amount of memory to use [in GB]; [default=8] ) \n" \
                  "-n (number of CPUs/processors/cores to use; [default=use all available]) \n" \
                  "-t (temporary directory for storing temp files; [default='/tmp/']) \n\n"
            "Example of a complex run: \n" \
            "$0 -SRR1001,SRR10002 -o ~/Desktop/sra_files/ -m 30 -n 6 -t /tmp/ \n\n" \
            "Exiting program. Please retry with corrected parameters..." >&2; exit 1;
}

#==================================================================================================#
# Make sure the pipeline is invoked correctly, with project and sample names
#==================================================================================================#
    while getopts "s:o:m:n:t:" arg;
        do
        	case ${arg} in

        		s ) # Take in the sample name(s)
                    set -f
                    IFS=","
                    SAMPLES=(${OPTARG}) # call this when you want every individual sample
                        ;;

                o ) # set output directory, for where to save files to
                    OUTPUT_DIRECTORY=${OPTARG}
                        ;;

                m ) # set max memory to use (in GB; if any letters are entered, discard those)
                    MEMORY_ENTERED=${OPTARG}
                    MEMORY_TO_USE=$(echo $MEMORY_ENTERED | sed 's/[^0-9]*//g')
                        ;;

                n ) # set number of CPUs to use
                    NUM_THREADS=${OPTARG}
                        ;;

                t ) # set temporary directory
                    TEMP_DIR=${OPTARG}
                        ;;

                * ) # Display help
        		    usage
        		     	;;
        	esac
        done; shift $(( OPTIND-1 ))

#==================================================================================================#
# Check that necessary software is installed
#==================================================================================================#
command -v fasterq-dump > /dev/null || \
{   echo -e "ERROR: This requires 'fasterq-dump' from the NCBI sratoolkit, but it could not found. \n" \
        "Please install this application from https://github.com/ncbi/sra-tools/wiki/Downloads . \n" \
        "Exiting..." >&2; exit 6
    }

#==================================================================================================#
# Process parameters: use the user-provided parameters above to create variable names that can be
#                     called in the rest of the pipeline
#==================================================================================================#

    #==============================================================================================#
    # Sample names
    #==============================================================================================#

    # If no SRA accsessions are provided, tell that to the user & exit
    if [[ -z "${SAMPLES}" ]] ; then
     usage
    fi

    # Reset global expansion [had to change to read multiple sample names]
    set +f

    #==============================================================================================#
    # Output directory
    #==============================================================================================#

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
                echo "Cannot create user-provided output directory. Defaulting to current working directory './'"
                OUTPUT_DIRECTORY="./"
                mkdir ${OUTPUT_DIRECTORY}
            }
        fi
    fi

    # If user didn't provide out dir, then check to see if there's an
    # SRA_DIR environmental variable, which I set on the lab iMac; if not, just use current directory
    if [[ -z "${OUTPUT_DIRECTORY}" ]]; then
        if [[ ! -z "${SRA_DIR}" ]]; then
            OUTPUT_DIRECTORY=${SRA_DIR}
        else
            OUTPUT_DIRECTORY="./"
        fi
    fi

    # Create the output directory; if there is an error in creating in, then exit
    mkdir -p ${OUTPUT_DIRECTORY} || \
        { echo "Cannot create directory. Choose different output directory and retry." \
             "Exiting..." && exit 2
         }

    #==============================================================================================#
    # Temporary directory
    #==============================================================================================#

    # Create the temporary directory. If user provided one, try to use that
    ## If user didn't provide a temporary directory, or if temporary directory cannot be created,
    ## defeault to "/tmp/"

    if [[ -z "${TEMP_DIR}" ]]; then
        TEMP_DIR="./"
        mkdir -p ${TEMP_DIR}

    else
        if [[ ! -d ${TEMP_DIR} ]]; then
            mkdir -p ${TEMP_DIR} || \
            {
                echo "Cannot create user-provided temporary directory. Defaulting to '/tmp/'"
                OUTPUT_DIRECTORY="/tmp/"
            }
        fi

    #==============================================================================================#
    # Set up number of CPUs to use and RAM
    #==============================================================================================#
    # CPUs (aka threads aka processors aka cores):
    ## If provided by user, use that. Otherwise:
    ## Use `nproc` if installed (Linux or MacOS with gnu-core-utils); otherwise use `sysctl`
    if [[ -z "${NUM_THREADS}" ]] ; then
        {   command -v nproc > /dev/null && \
            NUM_THREADS=`nproc` && \
            echo "Number of processors available (according to nproc): ${NUM_THREADS}"; \
            } \
        || \
        {   command -v sysctl > /dev/null && \
            NUM_THREADS=`sysctl -n hw.ncpu` && \
            echo "Number of processors available (according to sysctl): ${NUM_THREADS}";
            }
    fi
    #==============================================================================================#
    # Set memory usage to 16GB if none given by user
    if [[ -z ${MEMORY_TO_USE} ]]; then
        echo "No memory limit set by user. Defaulting to 8GB"
        MEMORY_TO_USE="8"
    fi

    # As a check to the user, print the project name and sample numbers to the screen
    echo "SRA sample accessions: ${SAMPLES[@]}"
    echo "Memory to use: ${MEMORY_TO_USE}"
    echo "Number of processors to use: ${NUM_THREADS}"
#==================================================================================================#

#==================================================================================================#
# Download fastq files from the SRA
#==================================================================================================#
for SAMPLE in ${SAMPLES[@]}
   do \
      fasterq-dump \
      --split-3 \
      -t ${TEMP_DIR} \
      -e ${NUM_THREADS} \
      --mem=${MEMORY_TO_USE} \
      -p \
      --skip-technical \
      --rowid-as-name \
      --outdir ${OUTPUT_DIRECTORY} \
      ${SAMPLE}
   done
#==================================================================================================#

#==================================================================================================#
# Program complete
#==================================================================================================#
echo "Successfully downloaded SRA files for ${SAMPLES[@]}"
echo "Find SRA files at: ${OUTPUT_DIRECTORY}"
