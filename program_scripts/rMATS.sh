#!/bin/bash

# Load in JSON reader
#module load jq
## conda environment activation
eval "$(conda shell.bash hook)"
# V.4.2.0
conda activate rmats

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
STAR_path=$(jq -r '.STAR_output' "$metadata")
echo "STAR: ${STAR_path}"
bam_path=$(find "${STAR_path}" -type f -name "*.bam" | head -n 1)
echo "bam: ${bam_path}"
folder_path="${batch_dir}/${sample_id}"
echo "folder: ${folder_path}"
output=$(jq -r '.rMATS_output' "$metadata")

txt_path="${output}/${sample_id}.txt"
# Check if the file does NOT exist
if [ ! -f "$txt_path" ]; then
    echo "File not found. Creating ${sample_id}.txt..."
    
    # Write the BAM path to the file
    echo "${bam_path}" > "$txt_path"
    
    echo "   [OK] Path written to $txt_path"
else
    echo "   [SKIP] ${sample_id}.txt already exists."
fi

# Update metadata.json in place
jq --arg sp "$txt_path" '.resource.rMATS.samplePath = $sp' "$metadata" > tmp.json && mv tmp.json "$metadata"

GTF=$(jq -r '.resource.annotation.gtf' "$metadata")
controls=$(jq -r '.resource.rMATS.controlPaths' "$metadata")
sample=$(jq -r '.resource.rMATS.samplePath' "$metadata")

temp="$output/temp"

# Clear subdirectories and start fresh
find "$output" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +


mkdir -p $temp
echo rmats.py --b1 $sample --b2 $controls --gtf $GTF --od "${output}" --tmp "${temp}" -t paired --readLength 150 --cstat 0.0001 --nthread 16  --libType fr-firststrand --allow-clipping --novelSS

# Create a temporary SLURM script
slurm_script="${output}/run_rmats_${sample_id}.slurm"

cat <<EOT > "$slurm_script"
#!/bin/bash
#SBATCH -J rMATS_${sample_id}  # Job name
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mail-user=lb3e23@soton.ac.uk  # Your email address
#SBATCH --mail-type=ALL  # Notifications for job start, end, and failure
#SBATCH --cpus-per-task=16  # Number of CPU cores
#SBATCH --time=20:00:00  # Max runtime

# Load in JSON reader
source /iridisfs/i6software/conda/miniconda-py3/etc/profile.d/conda.sh
conda activate rmats

# Run rMATS
rmats.py --b1 "\$sample" --b2 "\$controls" --gtf "\$GTF" --od "\${output}" --tmp "\${temp}" \
    -t paired --readLength 150 --cstat 0.0001 --nthread 16 --libType fr-firststrand \
    --allow-clipping --novelSS
rm -r "${temp}"

EOT

# Submit the SLURM script
sbatch --export=sample="$sample",controls="$controls",output="$output",temp="$temp",GTF="$GTF" "$slurm_script"

echo "SLURM job submitted: $slurm_script"