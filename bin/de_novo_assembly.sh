#!/bin/bash

function usage() {
    #==== FUNCTION ================================================================================#
    #        NAME: usage
    # DESCRIPTION: setup a usage statement that will inform the user how to correctly invoke the
    #              program
    #==============================================================================================#

    echo -e "\nERROR: Missing samples and/or program type. \n" \
            "Make sure to provide path samples \n\n" \
            "Usage for paired-end reads: \n" \
            "$0 -p dna|rna -1 path/to/reads_R1.fq -2 path/to/reads_R2.fq \n\n" \
            "Usage in unpaired mode: \n" \
            "$0 -p dna|rna -u path/to/unpaired_reads.fq \n\n" \
            "Optional parameters: \n" \
                  "-o (directory for saving the files at the end; [default=current folder]) \n" \
                  "-m (maximum amount of memory to use [in GB]; [default=16] ) \n" \
                  "-n (number of CPUs/processors/cores to use; [default=use all available]) \n" \
                  "-t (temporary directory for storing temp files; [default='/tmp/']) \n" \
            "Example of a complex run: \n" \
            "$0 -SRR1001,SRR10002 -d ~/Desktop/sra_files/ -m 30 -n 6 -t /tmp/ \n\n" \
            "Exiting program. Please retry with corrected parameters..." >&2; exit 1;
}

#==================================================================================================#
# Make sure the pipeline is invoked correctly, with project and sample names
#==================================================================================================#
    while getopts "p:1:2:u:o:m:n:t:" arg;
        do
        	case ${arg} in

                p ) # Program Type (dna or rna)
                    MOLECULE_TYPE=(${OPTARG})

                    if [[ ${MOLECULE_TYPE} == "dna" ]]; then
                        SPADES_PROGRAM="spades.py"
                    elif [[ ${MOLECULE_TYPE} == "rna" ]]; then
                        SPADES_PROGRAM="rnaspades.py"
                    else
                           echo "ERROR: SPAdes program type must be 'dna' or 'rna' (no quotes)";
                           echo "Exiting..." >&2;
                           exit 3;
                    fi
                        ;;

                1 ) # Samples: if paired, give the path and full filename for the forward read
                    FORWARD_READS=(${OPTARG})
                        ;;

                2 ) # Samples: if paired, give the path and full filename for the reverse read
                    REVERSE_READS=(${OPTARG})
                        ;;

                u ) # Samples: if unpaired, give the path and full filename for the reads
                    UNPAIRED_READS=(${OPTARG})
                        ;;

                o ) # set output directory, for where to save files to; files will be in a subfolder with the name of the reads
                    USER_PROVIDED_OUTPUT_DIRECTORY=${OPTARG}

                    if [[ ! -z ${FORWARD_READS} ]] ; then
                       READS_NAME=`echo ${FORWARD_READS} | sed 's/_[A-Z]*1.f[a-z]*q//'`

                       if [[ -z ${READS_NAME} ]]; then
                           READS_NAME=${FORWARD_READS}
                       fi

                    elif [[ ! -z ${UNPAIRED_READS} ]] ; then
                       READS_NAME=`echo ${UNPAIRED_READS} | sed 's/.f[a-z]*q//'`

                       if [[ -z ${READS_NAME} ]]; then
                           READS_NAME=${UNPAIRED_READS}
                       fi

                    else
                        usage; exit 10
                    fi
                       OUTPUT_DIRECTORY=${USER_PROVIDED_OUTPUT_DIRECTORY}/${READS_NAME}
                        ;;

                m ) # set max memory to use (in GB; if any letters are entered, discard those)
                    MEMORY_ENTERED=${OPTARG}
                    MEMORY_TO_USE=$(echo $MEMORY_ENTERED | sed 's/[^0-9]*//g')
                        ;;

                n ) # set number of CPUs to use
                    NUM_THREADS=${OPTARG}
                        ;;

                t ) # set temporary directory (put in a random subdirectory to avoid conflicts if running in parallel)
                    TEMP_DIR=${OPTARG}/${RANDOM}
                        ;;

                * ) # Display help
        		    usage
        		     	;;
        	esac
        done; shift $(( OPTIND-1 ))

#==================================================================================================#
# Check that necessary software is installed
#==================================================================================================#
{ command -v rnaspades.py > /dev/null || \
  command -v spades.py > /dev/null
} || \
{   echo -e "ERROR: This requires 'spades' or 'rnaspades' de novo assemblers, but it could not found. \n" \
        "Please install these applications. \n" \
        "Exiting..." >&2; exit 6
}

#==================================================================================================#
# Process parameters: use the user-provided parameters above to create variable names that can be
#                     called in the rest of the pipeline
#==================================================================================================#

    #==============================================================================================#
    #  Make sure required arguments are provided
    #==============================================================================================#

    # If no SPAdes program type is provided, tell that to the user & exit
    if [[ -z "${SPADES_PROGRAM}" ]] ; then
     usage
    fi

    if { [[ -z ${FORWARD_READS} ]] && [[ -z ${REVERSE_READS} ]]
       } && [[ -z ${UNPAIRED_READS} ]] ; then
             usage
             echo "No complete library of reads provided. Exiting..."
             exit 9
    fi
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
        echo "No memory limit set by user. Defaulting to 16GB"
        MEMORY_TO_USE="16"
    fi

    # As a check to the user, print the project name and sample numbers to the screen
    echo "Memory to use: ${MEMORY_TO_USE}"
    echo "Number of processors to use: ${NUM_THREADS}"
#==================================================================================================#


function de_novo_assembly() {
    #==============================================================================================#
    # Construct contigs from the raw reads using SPAdes
    #==============================================================================================#

    # Paired reads
    if {
        [[ ! -z ${FORWARD_READS} ]] && [[ ! -z ${REVERSE_READS} ]]
       }; then

        ${SPADES_PROGRAM} \
        -o ${OUTPUT_DIRECTORY} \
        -1 ${FORWARD_READS} \
        -2 ${REVERSE_READS} \
        --threads ${NUM_THREADS} \
        -m ${MEMORY_TO_USE} \
        --tmp-dir ${TEMP_DIR} ;

    # Unpaired reads
    elif [[ ! -z ${UNPAIRED_READS} ]] ; then
        ${SPADES_PROGRAM} \
        -o ${OUTPUT_DIRECTORY} \
        -s ${UNPAIRED_READS} \
        --threads ${NUM_THREADS} \
        -m ${MEMORY_TO_USE} \
        --tmp-dir ${TEMP_DIR} ;

    else
        echo "Encountered unknown problem when trying to run de novo assembly.";
        echo "Could not determine library type (paired or unpaired). Exiting...";
        usage ;
        exit 9
    fi
    #==============================================================================================#
}

#==================================================================================================#
# Run the de novo aseembly
#==================================================================================================#
de_novo_assembly

#==================================================================================================#
# Program complete
#==================================================================================================#
echo "Successfully assembled contigs. Files located at: ${OUTPUT_DIRECTORY}"
