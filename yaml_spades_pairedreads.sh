#!/bin/bash

OUTPUT="./${SAMPLES}.input.yaml"
FILES=${@}

# Write beginning of the file
echo '    [
      {
        orientation: "fr",
        type: "paired-end",
        left reads: [' > ${OUTPUT}

# For each SRX, write the location of the forward reads
for SAMPLE in ${FILES}
   do
      echo -n \
      '          "/n/scratch2/am704/nibert/' >> ${OUTPUT}
      echo \
      ${PROJECT}/sra/${SAMPLE}_1.fastq\", >> ${OUTPUT}
   done

# Remove the last comma
sed '$ s/.$//' ${OUTPUT} > ${OUTPUT}.temp
mv ${OUTPUT}.temp ${OUTPUT}

# Write some more formatting
echo \
'        ],
        right reads: [' >> ${OUTPUT}

# For each SRX, write the location of the reverse reads
for SAMPLE in ${FILES}
   do   
      echo -n \
      '          "/n/scratch2/am704/nibert/' >> ${OUTPUT}
      echo \
      ${PROJECT}/sra/${SAMPLE}_2.fastq\", >> ${OUTPUT}
   done

# Remove the last comma
sed '$ s/.$//' ${OUTPUT} > ${OUTPUT}.temp
mv ${OUTPUT}.temp ${OUTPUT}

# Write last bit of formatting
echo \
'        ]
      },
     ]' >> ${OUTPUT}

echo "Finished contructing input yaml for ${1}-${!#}"
