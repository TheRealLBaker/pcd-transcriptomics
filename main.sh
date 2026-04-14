#!/bin/bash

# Usage
usage() {
    echo "Usage: $0 -d <data_dir>"
    exit 1
}

# Parse arguments
while getopts "d:" opt; do
    case $opt in
        d) data_dir="$OPTARG" ;;
        *) usage ;;
    esac
done

if [[ -z "$data_dir" ]]; then
    usage
fi

batch_dir=$data_dir

# Select software
read -p "Which software: STAR (s), rMATS (r), voila (v), HTSeq (h), Fastqc (f), gatk (g), picard (p): " SOFTWARE_SELECT

if [[ "$SOFTWARE_SELECT" == "s" ]]; then
    script="/iridisfs/pcd/scripts/STAR.sh"
    software="STAR"
    read -p "Would you like to redefine the output directory: (y/n)" OUT_DIR
elif [[ "$SOFTWARE_SELECT" == "r" ]]; then
    script="/iridisfs/pcd/scripts/rMATS.sh"
    software="rMATS"
elif [[ "$SOFTWARE_SELECT" == "v" ]]; then
    script="/iridisfs/pcd/scripts/voila.sh"
    software="voila"
elif [[ "$SOFTWARE_SELECT" == "h" ]]; then
    script="/iridisfs/pcd/scripts/HTSeq.sh"
    software="HTSeq"
elif [[ "$SOFTWARE_SELECT" == "f" ]]; then
    script="/iridisfs/pcd/scripts/FastQC.sh"
    software="fastQC"
elif [[ "$SOFTWARE_SELECT" == "p" ]]; then
    script="/iridisfs/pcd/scripts/picard.sh"
    software="picard"
elif [[ "$SOFTWARE_SELECT" == "g" ]]; then
    script="/iridisfs/pcd/scripts/gatk.sh"
    software="gatk"    
else
    echo "This feature has not been implemented yet!"
    exit 1
fi

# Ask about manual selection
read -p "Enable manual sample selection? (y/n): " MANUAL_SELECT

# Loop through samples
for sample_dir in "$batch_dir"/*/; do
    # Ensure it's a directory
    if [[ -d "$sample_dir" ]]; then
        sample_id=$(basename "$sample_dir")

        if [[ "$MANUAL_SELECT" == "y" ]]; then
            read -p "Do you want to run sample $sample_id? (y/n): " RUN_SAMPLE
            if [[ "$RUN_SAMPLE" != "y" ]]; then
                continue
            fi
        fi

        echo "Running ${software} for sample: $sample_id"
        $script -i "$sample_id" -b "$batch_dir"
    fi
done
