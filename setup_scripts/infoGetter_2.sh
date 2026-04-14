#!/bin/bash

# Usage
usage() {
    echo "Usage: $0 -r <raw_data_dir> -o <output_dir> -c <optional controls_dir>"
    exit 1
}

# Parse arguments
while getopts "r:o:c:" opt; do
    case $opt in
        r) RAW_DIR="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        c) CONTROL_DIR="$OPTARG" ;;
        *) usage ;;
    esac
done

if [[ -z "$RAW_DIR" || -z "$OUTPUT_DIR" ]]; then
    usage
fi

mkdir -p "$OUTPUT_DIR"

read -p "Enable manual sample selection? (y/n): " MANUAL_SELECT

for SAMPLE_DIR in "$RAW_DIR"/*; do
    [[ ! -d "$SAMPLE_DIR" ]] && continue
    SAMPLE_ID=$(basename "$SAMPLE_DIR")

    if [[ "$MANUAL_SELECT" == "y" ]]; then
        echo "Sample directory: $SAMPLE_DIR"
        read -p "Create info for this sample? (y/n): " DO_SAMPLE
        [[ "$DO_SAMPLE" != "y" ]] && continue
    fi

    echo "Processing sample: $SAMPLE_ID"
    OUTPUT_SAMPLE_DIR="$OUTPUT_DIR/$SAMPLE_ID"
    mkdir -p "$OUTPUT_SAMPLE_DIR/raw" "$OUTPUT_SAMPLE_DIR/preprocessed" "$OUTPUT_SAMPLE_DIR/STAR" "$OUTPUT_SAMPLE_DIR/HTSeq" "$OUTPUT_SAMPLE_DIR/rMATS" "$OUTPUT_SAMPLE_DIR/MAJIQ" "$OUTPUT_SAMPLE_DIR/picard"

    # Find raw FASTQs
    mapfile -t RAW_1_FILES < <(find "$SAMPLE_DIR" -type f -name "*_1.fq.gz")
    mapfile -t RAW_2_FILES < <(find "$SAMPLE_DIR" -type f -name "*_2.fq.gz")
    # Sort input files - concatenation needs to be in the right order or else leads to poor mapping.
    IFS=$'\n' RAW_1_FILES=($(sort <<<"${RAW_1_FILES[*]}"))
    IFS=$'\n' RAW_2_FILES=($(sort <<<"${RAW_2_FILES[*]}"))
    unset IFS

    if [[ ${#RAW_1_FILES[@]} -eq 0 ]]; then
      echo "Warning: No _1 files found"
      PROCESSED_1=""
    elif [[ ${#RAW_1_FILES[@]} -gt 1 ]]; then
        echo "Multiple _1 reads found for $SAMPLE_ID:"
        printf '%s\n' "${RAW_1_FILES[@]}"
        read -p "Do you want to concatenate them? (y/n): " CONCAT_1_CHOICE
    
        if [[ "$CONCAT_1_CHOICE" == "y" ]]; then
            cat "${RAW_1_FILES[@]}" > "$OUTPUT_SAMPLE_DIR/preprocessed/${SAMPLE_ID}_1_merged.fq.gz"
            PROCESSED_1="$OUTPUT_SAMPLE_DIR/preprocessed/${SAMPLE_ID}_1_merged.fq.gz"
        else
            # Try to find pre-merged or pre-concatenated file
            PROCESSED_1=$(find "$SAMPLE_DIR" -type f -name "*merged_1.fq.gz" -o -name "*concat_1.fq.gz" -o -name "*cat_1.fq.gz" | head -n 1)
            if [[ -z "$PROCESSED_1" ]]; then
                echo "No pre-merged _1 file found in $SAMPLE_DIR"
        fi
    fi
    else
        PROCESSED_1="${RAW_1_FILES[0]}"
    fi


    if [[ ${#RAW_2_FILES[@]} -eq 0 ]]; then
      echo "Warning: No _2 files found"
      PROCESSED_2=""
    elif [[ ${#RAW_2_FILES[@]} -gt 1 ]]; then
        echo "Multiple _2 reads found for $SAMPLE_ID:"
        printf '%s\n' "${RAW_2_FILES[@]}"
        read -p "Do you want to concatenate them? (y/n): " CONCAT_2_CHOICE
    
        if [[ "$CONCAT_2_CHOICE" == "y" ]]; then
            cat "${RAW_2_FILES[@]}" > "$OUTPUT_SAMPLE_DIR/preprocessed/${SAMPLE_ID}_2_merged.fq.gz"
            PROCESSED_2="$OUTPUT_SAMPLE_DIR/preprocessed/${SAMPLE_ID}_2_merged.fq.gz"
        else
            PROCESSED_2=$(find "$SAMPLE_DIR" -type f -name "*merged_2.fq.gz" -o -name "*concat_2.fq.gz" -o -name "*cat_2.fq.gz" | head -n 1)
            if [[ -z "$PROCESSED_2" ]]; then
                echo "No pre-merged _2 file found in $SAMPLE_DIR"
            fi
        fi
    else
        PROCESSED_2="${RAW_2_FILES[0]}"
    fi


    CONTROL_PATH=${CONTROL_DIR:-"/iridisfs/pcd/outputs/non_pcd/"}
    mapfile -t CONTROL_BAMS < <(find "$CONTROL_PATH" -type f -name "*.bam")
    (IFS=,; echo "${CONTROL_BAMS[*]}") > "$OUTPUT_SAMPLE_DIR/rMATS/controls.txt"

    # Defaults
    STAR_output="$OUTPUT_SAMPLE_DIR/STAR"
    HTSeq_output="$OUTPUT_SAMPLE_DIR/HTSeq"
    rMATS_output="$OUTPUT_SAMPLE_DIR/rMATS"
    MAJIQ_output="$OUTPUT_SAMPLE_DIR/MAJIQ"
    PICARD_OUTPUT="$OUTPUT_SAMPLE_DIR/picard"

    STAR_INDEX="/iridisfs/pcd/resources/Genome_and_annotations/StarIndex/"
    LICENSE="/mainfs/scratch/lb3e23/Resources/Licenses/Majiq/majiq_license_academic_official.lic"

    RAW_1_JOINED=$(printf '"%s", ' "${RAW_1_FILES[@]}" | sed 's/, $//')
    RAW_2_JOINED=$(printf '"%s", ' "${RAW_2_FILES[@]}" | sed 's/, $//')

    # Resource defaults
    GTF="/iridisfs/pcd/resources/Genome_and_annotations/gencode.v48.chr_patch_hapl_scaff.annotation.gtf"
    GTF_unmasked="/iridisfs/pcd/resources/Genome_and_annotations/gencode.v48.chr_patch_hapl_scaff.annotation.gtf"
    FA="/iridisfs/pcd/resources/Genome_and_annotations/GRCh38.primary_assembly.genome_hydin2_gene_full_mask.fa"
    GFF=
    VEP_CACHE="/mainfs/scratch/lb3e23/cache/vep/"
    DBSNP="/mainfs/scratch/lb3e23/Resources/GRch38/snpVCF/dbSNP/chr_00-All.vcf"
    REFFLAT="/mainfs/scratch/lb3e23/Resources/GRch38/refFlat.txt"
    RRNA="/mainfs/scratch/lb3e23/Resources/gencode.v44.rRNA.interval_list"

    # Create initial JSON
    JSON_FILE="$OUTPUT_SAMPLE_DIR/metadata.json"
    cat <<EOF > "$JSON_FILE"
{
  "sample_id": "$SAMPLE_ID",
  "raw_files": {
    "1": [${RAW_1_JOINED}],
    "2": [${RAW_2_JOINED}]
  },
  "processed_files": {
    "1": "$PROCESSED_1",
    "2": "$PROCESSED_2"
  },
  "STAR_output": "$STAR_output",
  "HTSeq_output": "$HTSeq_output",
  "rMATS_output": "$rMATS_output",
  "MAJIQ_output": "$MAJIQ_output",
  "PICARD_OUTPUT": "$PICARD_OUTPUT",
  "STAR_index": "$STAR_INDEX",
  "controls": {
    "path": "$CONTROL_PATH",
    "sorted_bam": ""
  },
  "resource": {
    "annotation": {
      "gtf": "$GTF_unmasked",
      "fa": "$FA",
      "gff": "$GFF"
    },
    "rMATS": {
      "samplePath": "",
      "controlPaths": "$rMATS_output/controls.txt"
    },
    "MAJIQ": {
      "samplePath": "",
      "controlPaths": "$rMATS_output/controls.txt",
      "license": "$LICENSE"
    },
    "vep_cache": "$VEP_CACHE",
    "dbSNP_vcf": "$DBSNP",
    "refFlat": "$REFFLAT",
    "rRNA_interval": "$RRNA"
  }
}
EOF

    # Interactive customization loop
    while true; do
        read -p "Would you like to edit this metadata.json for sample $SAMPLE_ID? (y/n): " EDIT_CHOICE
        [[ "$EDIT_CHOICE" != "y" ]] && break

        echo "Which field would you like to change?"
        echo "Examples:"
        jq -r 'paths | join(".")' "$JSON_FILE" | grep -v '^\[\]' | sed 's/^/ - /'

        read -p "Enter JSON path (e.g., resource.annotation.gtf): " JSON_PATH
        read -p "New value (string): " NEW_VALUE

        # Escape quotes
        NEW_VALUE_ESCAPED=$(printf '%s' "$NEW_VALUE" | sed 's/"/\\"/g')
        jq --arg val "$NEW_VALUE_ESCAPED" "setpath([\"${JSON_PATH//./\",\"}\"]; \$val)" "$JSON_FILE" > "$JSON_FILE.tmp" && mv "$JSON_FILE.tmp" "$JSON_FILE"

        read -p "Edit another field? (y/n): " MORE
        [[ "$MORE" != "y" ]] && break
    done

    echo "Finished $SAMPLE_ID"

done

echo "All metadata files created."
