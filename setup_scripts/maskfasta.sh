#!/bin/bash

# Create bed file with coordinates of HYDIN2 
# chr1	146547367	146898974	HYDIN2	.	+ > HYDIN2.bed

# Mask fasta file
bedtools maskfasta -fi genome.fa -bed HYDIN2.bed -fo genome.masked.fa

# Use masked fasta to STAR index and use this to align using STAR