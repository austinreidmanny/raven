# Raven
An RNA virus discovery pipeline (formerly `dnatax`).

Like the bird, `Raven` is smart and good at finding things (like viruses). Unlike the bird, this pipeline has not been cited by Edgar Allen Poe.

## Objective
`Raven` is a virus discovery pipeline for finding viruses in publicly available transcriptome data.

This pipeline simply takes in one or more SRA accession number (for RNA-seq datasets in the NCBI Sequence Read Archive)
and returns a list of viruses and their sequences.

The steps are:
- Download reads [`NCBI sra-tools`]
- Adapter trimming [`TrimGalore!`]
- De novo contig assembly [`rnaSPAdes`]
- Taxonomic classification [`DIAMOND`]
- Translate taxonomy [custom scripts using `JGI-ISF taxonomy server`]
- Mapping reads to assemblies to determine coverage values [`bwa-mem`]
- Binning [custom code to parse taxonomy results > `seqtk`]
- Print results to user

## Usage
```
Usage: ./raven.sh -p PROJECT -s SRR10001,SRR10002,SRR...

Optional parameters:
 -l (library type of the reads; 'paired' or 'single'; [default=auto determine])
 -m (maximum amount of memory to use [in GB]; [default=16] )
 -n (maximum number of CPUs to use; [default=attempt to auto-determine; not perfect])
 -w (set the working directory, where all analysis will take place; [default=current directory,
 but a scratch directory with a lot of storage is recommended])
 -f (set the final directory, where all the files will be copied to the end [default=current directory])
 -t (set the temporary directory, where the pipeline will dump all temp files [default='/tmp/raven/']
 -h (set the home directory where Raven is located; [default=current directory, is recommended not to change])
 -d (specify the full path to the DIAMOND database, including the db name - e.g., '/path/to/nr-database/nr'
 [default=none, will download all files to temp space and copy them to final directory at the end; NOTE:
 Raven requires a DIAMOND database, NCBI taxonmaps file, and NCBI protein2accessions file;
 These all must be located in the same directory as the DIAMOND database

 Example of a complex run:
 ./raven.sh -p trichomonas -s SRR1001,SRR10002 -l paired -m 30 -w external_drive/storage/ -f projects/raven/final/ -t /tmp/ -d tools/diamond/nr
```

## Limitations and desired changes
* Extend binning system from just `viruses` to a scheme that will separately bin `viruses`,  `eukaryotes`, and `bacteria`. Should be straightforward.
*  As it stands, this pipeline only works with RNA-seq data. The de novo assembly step invokes rnaSPAdes. That is really the only RNA-dependent portion of the pipeline. I could add an rna/dna option to the list of parameters and alter the assembly step to make it more flexible (like I did with `de_novo_assembly.sh` @ `github.com/austinreidmanny/nibert-lab-tools`)
