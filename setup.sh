#!/bin/bash

# Check to see if the Conda package manager is installed; if not, download & install it
conda -V || {
  echo -e "DNAtax uses the program 'conda' in order to make sure all the necessary \n" \
          "software is installed and up to date. \n\n" \
          "Please confirm all of the following prompts..."
  wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
  bash Miniconda3-latest-Linux-x86_64.sh
  echo "Conda has successfully installed! Please exit this window, begin a new " \
       "terminal session, and rerun this script ($0) to finish setup!"
  exit 0
  }

# Test to make sure that conda is installed correctly
conda list > /dev/null || \
{
echo "Conda was not set up correctly. Please retry or manually install Miniconda."
exit 1
}

# Configure conda to include the bioinformatics channels
conda config --add channels defaults
conda config --add channels bioconda
conda config --add channels conda-forge

# Setup a new environment where all the software needed for dnatax will be installed
conda create --name env_dnatax seqtk sra-tools spades diamond trim-galore
eval "$(conda shell.bash hook)"
conda activate env_dnatax
conda update --all

# Tell the user that the setup has completed!
echo -e "All necessary software as been successfully installed! \n" \
        "The DNAtax pipeline is now ready to run."
exit 0
