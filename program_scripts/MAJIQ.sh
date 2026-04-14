#!/bin/bash

# jq is not a module in Iridis 6 atm so I've installed it in my conda env bedtools
# Load in JSON reader
source /iridisfs/i6software/conda/miniconda-py3/etc/profile.d/conda.sh
conda activate bedtools

## virtual environment activation
#cd /mainfs/scratch/lb3e23/Majiq_env/
#source majiq/bin/activate

# Initialise the environment exactly like a login shell
source /etc/profile
module --ignore_cache apptainer/1.4.2

# Check to see if both arguments are provided.
# Usage function
usage() {
    echo "Usage: $0 -i <sample_id> -b <batch_dir>"
    exit 1
}

# Initialize variables
sample_id=""
batch_dir=""

# Manual argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--sample)
            sample_id="$2"
            shift 2
            ;;
        -b|--batch)
            batch_dir="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option $1"
            usage
            ;;
    esac
done

# Ensure both required arguments are provided
if [[ -z "$sample_id" || -z "$batch_dir" ]]; then
    echo "Error: Missing required arguments."
    usage
fi


metadata="${batch_dir}/${sample_id}/metadata.json"
GFF=$(jq -r '.resource.annotation.gff' "$metadata")
sample=$(jq -r '.resource.MAJIQ.samplePath' "$metadata")
output=$(jq -r '.MAJIQ_output' "$metadata")
license=$(jq -r '.resource.MAJIQ.license' "$metadata")

# Provide license for MAJIQ - best way to do this is to put the licence in the working directory (i.e., the current cd)
export MAJIQ_LICENSE_FILE=$license
echo $license
mkdir -p "${output}/build"
echo majiq build $GFF -c $sample -o "${output}/build"

# Update metadata to include path for build files
jq --arg MAJIQ_path "$output/build/" '.resource.MAJIQ.build = $MAJIQ_path' "$metadata" > "${batch_dir}/${sample_id}/metadata.tmp" && mv "${batch_dir}/${sample_id}/metadata.tmp" "$metadata"
