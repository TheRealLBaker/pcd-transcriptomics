#!/bin/bash

# Aim of the script is to generate the configuration txt file needed for MAJIQ, in a 1 patient vs 9 controls situation.
# Check if the correct number of arguments are passed
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <directory_path1> <directory_path2>"
    exit 1
fi

# Assign the arguments to variables, dir_path1 = path of patient STAR directory, dir_path2 = path of controls STAR directory
dir_path1=$1
dir_path2=$2

# Check if both directories exist
if [ ! -d "$dir_path1" ]; then
    echo "Directory $dir_path1 does not exist."
    exit 1
fi

if [ ! -d "$dir_path2" ]; then
    echo "Directory $dir_path2 does not exist."
    exit 1
fi

# Find .sorted.bam files in both directories and their subdirectories and save them in arrays
# < < process substitution. It allows the output of the commands inside (...) to be treated as a file for input redirection.
# Here, the output of  find ... | sort -u is substituted into the mapfile.
# mapfile stores everything into an array, -t removes trailing new lines characters.
# inside the find, -exex dirname {} + executes dirname on all files in the array once all files have been added, this wait is indicated by +. {} is a placeholder for all of the files. The output is piped into a sort function which does -u and gets unique values.
mapfile -t sorted_bam_files1 < <(find "$dir_path1" -type f -name "*.sorted.bam")
mapfile -t sorted_bam_files2 < <(find "$dir_path2" -type f -name "*.sorted.bam")
mapfile -t sorted_bam_dirs1 < <(find "$dir_path1" -type f -name "*.sorted.bam" -exec dirname {} + | sort -u)
mapfile -t sorted_bam_dirs2 < <(find "$dir_path2" -type f -name "*.sorted.bam" -exec dirname {} + | sort -u)
# Join arrays into comma-separated strings
#Internal Field Separator, it is "," in this case, list items joined into string, separated by ,
bamdirs1=$(IFS=,; echo "${sorted_bam_dirs1[*]}")
bamdirs2=$(IFS=,; echo "${sorted_bam_dirs2[*]}")
bamfiles1=$(IFS=,; echo "${sorted_bam_files1[*]}")
bamfiles2=$(IFS=,; echo "${sorted_bam_files2[*]}")

#When you use "${array_name[*]}", Bash treats the entire array as a single string, with each element separated by the first character of the IFS (Internal Field Separator) variable. By default, IFS is set to space, tab, and newline characters. So, "${array_name[*]}" will join all elements of the array into a single string with spaces between them.

#On the other hand, "${array_name[@]}" treats each element of the array as a separate word. It preserves any whitespace or special characters within the elements.

# Function to extract the desired part from file paths
extract_name() {
    local names=()  # Array to store extracted names
    # Loop through each file path in the array
    for file_path in "$@"; do
        # Extract the base name of the file without extension
        name=$(basename "$file_path" .sorted.bam)
        # Append the name with .sorted to the array
        names+=("${name}.sorted")
    done
    # Join the array into a single string with comma separation
    (IFS=,; echo "${names[*]}") # IFS necessary here, otherwise will just print out one sample.sorted
}
# Extract the desired part from file paths and save them in arrays
names1=($(extract_name "${sorted_bam_files1[@]}"))
names2=($(extract_name "${sorted_bam_files2[@]}"))
#echo "${sorted_bam_files2[@]}"
#echo "names2: $names2"
# Join all bam directories into one string
#all_bamdirs="$bamdirs1,$bamdirs2"
all_bamdirs="$bamdirs2"

# Use for loop to run each sample in the array

for file_path in "${sorted_bam_files1[@]}"; do
    
    # Extract the base name without the .sorted.bam extension
    out_name=$(basename "${file_path}" .sorted.bam)
    
    # Extract the name(s) using the extract_name function
    names1=($(extract_name "${file_path}"))
    
    # Create the output file path
    output_file="/mainfs/scratch/lb3e23/analysed/rnaseq/batch6/MAJIQ/${out_name}_majiqConfig.txt"
    dir1=$(dirname "$file_path")
    
    # Write to the output file
    {
        echo "[info]"
        echo "bamdirs=${dir1},${all_bamdirs}"
        echo "genome=hg38"
        echo "strandness=reverse"
        echo "[experiments]"
        echo "Patient=${names1[@]}"  # Use ${names1[@]} to handle array properly
        echo "Controls=${names2}"
    } > "$output_file"
    
    echo "Output written to $output_file"
done

exit 0
