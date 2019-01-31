#!/bin/bash

OUTPUT="scripts/${SAMPLES}.input.yaml"
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
      '          "../data/fastq-adapter-trimmed/' >> ${OUTPUT}
      echo \
      ${SAMPLE}_1_val_1.fq\", >> ${OUTPUT}
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
      '          "../data/fastq-adapter-trimmed/' >> ${OUTPUT}
      echo \
      ${SAMPLE}_2_val_2.fq\", >> ${OUTPUT}
   done

# Remove the last comma
sed '$ s/.$//' ${OUTPUT} > ${OUTPUT}.temp
mv ${OUTPUT}.temp ${OUTPUT}

# Write last bit of formatting
echo \
'        ]
      },
     ]' >> ${OUTPUT}

echo "Finished contructing input yaml for ${SAMPLES}"

