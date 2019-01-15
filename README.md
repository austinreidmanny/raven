# Master Pipeline

2019-01-15

## Pipeline description
Right now, I am using basically the same pipeline across multiple projects. 
The steps are:
- Download [NCBI sra-tools]
- Contig assembly [rnaSPAdes]
- Taxonomic classification [diamond]
- Translate taxonomy [custom scripts using JGI-ISF]
- Extract relevant sequences [seqtk]
- Refinement [manual using SRA-BLAST]

The last two steps are performed manually.

## Usage

The pipelines themselves are very easy to run. They are called by 
`pipeline_PROJECT.sh SRX0000001 [...]`, which runs the pipeline 
by pooling all SRA accessions called.

## Limitations and desired changes
The only downside is that any arguments given are assumed to be SRA accesions.
To keep everything organized, I use relative paths, built by the PROJECT name.
This PROJECT name is supplied within the script, changed per project.

I would like to ammend this so that there is a required -project flag first,
and then SRA accessions are given.

I would also like to modularize this, by breaking it into modules within the
script. So I would have a DOWNLOAD module, CONTIG_ASSEMBLY module, etc.

In this repo, I will work on these changes.   
