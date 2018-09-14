#kate:syntax python;

#######################################
### Analyzing an Egyptian genome
#######################################

from Bio import SeqIO

rule scaffold_names:
    input: "data/pilon.fasta"
    output: "results/scaffold_names.txt"
    shell: "cat {input} | grep '>' > {output}"
    
# Quantifying the sequence content individually for all scaffolds
rule sequence_content:
    input: "data/pilon.fasta"
    output: "results/num_bases.txt",
    run:
        # Counting sequence lengths of scaffolds
        with open(input[0], "rU") as handle:
            sum_bases = 0
            for record in SeqIO.parse(handle, "fasta"):
                sum_bases += len(record)
        # Computing numbers and writing them to file
        with open(input[0], "rU") as handle, open(output[0], "w") as f_out:
            header = ["SCAFFOLD","LEN","A","C","G","T","N"]
            header += ["PERCENT_A","PERCENT_C","PERCENT_G","PERCENT_T","PERCENT_BASES"]
            f_out.write("\t".join(header))
            for record in SeqIO.parse(handle, "fasta"):
                len_scaf = len(record)
                n_a = record.seq.count("A")
                n_c = record.seq.count("C")
                n_g = record.seq.count("G")
                n_t = record.seq.count("T")
                n_n = record.seq.count("N")
                n_acgtn = sum([n_a,n_c,n_g,n_t,n_n])
                # Make sure that the sequence contains only ACGTN bases
                assert(n_acgtn == len(record))
                percent = [round(100*x/n_acgtn,2) for x in [n_a,n_c,n_g,n_t,n_n]]
                percent_bases = round(100*len(record)/sum_bases,2)
                numbers = [len_scaf,n_a,n_c,n_g,n_t,n_n]+percent+[percent_bases]
                f_out.write(record.id+"\t" \
                                     +"\t".join([str(x) for x in numbers]) \
                                     +"\n")

# Quantifying the sequence content over all scaffolds
rule sequence_content_overall:
    input: "data/pilon.fasta"
    output: "results/num_all.txt",
    run:
        # Counting sequence lengths of scaffolds
        with open(input[0], "rU") as handle, open(output[0], "w") as f_out:
            num_records = 0
            n = 0
            n_a = 0
            n_c = 0
            n_g = 0
            n_t = 0
            n_n = 0
            for record in SeqIO.parse(handle, "fasta"):
                num_records += 1
                n += len(record)
                n_a += record.seq.count("A")
                n_c += record.seq.count("C")
                n_g += record.seq.count("G")
                n_t += record.seq.count("T")
                n_n += record.seq.count("N")
            f_out.write("NUM_RECORDS: "+str(num_records)+"\n")
            f_out.write("NUM_BASES: "+str(n)+"\n")
            f_out.write("NUM_A: "+str(n_a)+"\n")
            f_out.write("NUM_C: "+str(n_c)+"\n")
            f_out.write("NUM_G: "+str(n_g)+"\n")
            f_out.write("NUM_T: "+str(n_t)+"\n")
            f_out.write("NUM_N: "+str(n_n)+"\n")
            f_out.write("PERCENT_A: "+str(round(100*n_a/n,2))+"\n")
            f_out.write("PERCENT_C: "+str(round(100*n_c/n,2))+"\n")
            f_out.write("PERCENT_G: "+str(round(100*n_g/n,2))+"\n")
            f_out.write("PERCENT_T: "+str(round(100*n_t/n,2))+"\n")
            f_out.write("PERCENT_N: "+str(round(100*n_n/n,2))+"\n")
            
# Compute N50 and other related values as statistic for the assembly
rule compute_assembly_stats:
    input: "results/num_bases.txt"
    output: "results/assembly_stats.txt"
    run:
        lengths = []
        with open(input[0],"r") as f_in, open(output[0],"w") as f_out:
            for line in f_in:
                if line[:8] == "SCAFFOLD":
                    continue
                lengths.append(int(line.split("\t")[1]))
            lengths = sorted(lengths,reverse = True)
            n = sum(lengths)
            stat_type = [50,60,70,80,90]
            for stat in stat_type:
                num_bases_to_sum = stat *n/100
                sum_scaffold_lens = 0
                stop = False
                for scaffold_len in lengths:
                    if sum_scaffold_lens < num_bases_to_sum:
                        sum_scaffold_lens += scaffold_len
                    else:
                        break
                f_out.write("N"+str(stat)+": "+str(scaffold_len)+"\n")
                
# Downloading the Busco lineage information
rule download_linage:
    output: temp("busco_lineage/mammalia_odb9.tar.gz")
    shell: "wget -P busco_lineage https://busco.ezlab.org/datasets/mammalia_odb9.tar.gz"
    
# ... and extracting it; the output files are just two of the many files in this
# archive
rule extract_lineage:
    input: "busco_lineage/mammalia_odb9.tar.gz"
    output: "busco_lineage/mammalia_odb9/lengths_cutoff",
            "busco_lineage/mammalia_odb9/scores_cutoff"
    shell: "tar --directory busco_lineage -xvzf {input}"
                    
# Running Busco on a genome file
# --force: Deleting results folder; start new run
# --tmp: Likely /tmp is too small, so make a new tmp folder on scratch (also 
#  this can be accessed much quicker)
# --blast_single_core: There is a (known!) bug, that blast sometimes fails in
# multi-cpu mode. I also observe this for GRCh38, with exactly the corresponding
# error message; therefore, this is run with a single core.
# Note: According to Busco documentation, 3.1Gbp genome assessment with 12 CPUs 
# takes 6 days and 15 hours
# I use a separate environment for busco, because, as of now, its newest version
# cannot be used together with the repeatmasker and installing it together 
# would result in downgrading of augustus, blast, boost and busco to older 
# versions.
rule run_busco:
    input: "busco_lineage/mammalia_odb9/lengths_cutoff",
           "seq_GRCh38/Homo_sapiens.GRCh38.dna.primary_assembly.fa"
    output: "run_busco_EGYPTREF/short_summary_busco_EGYPTREF.txt"
    threads: 24
    conda: "envs/busco.yaml"
    shell: "rm -rf /scratch/tmp_busco_1; " + \
           "mkdir /scratch/tmp_busco_1; " + \
           "run_busco --in {input[1]} " + \
                     "--out busco_EGYPTREF " + \
                     "--lineage_path busco_lineage/mammalia_odb9 " + \
                     "--mode genome " + \
                     "--force " + \
                     "--cpu 24 " + \
                     "--blast_single_core " + \
                     "--tmp /scratch/tmp_busco_1; " + \
                     "rm -rf /scratch/tmp_busco_1; "

# Running Busco on a genome file
rule run_busco_grch38:
    input: "busco_lineage/mammalia_odb9/lengths_cutoff",
           "seq_GRCh38/Homo_sapiens.GRCh38.dna.primary_assembly.fa"
    output: "run_busco_GRCh38/short_summary_busco_GRCh38.txt"
    threads: 24
    conda: "envs/busco.yaml"
    shell: "rm -rf /scratch/tmp_busco_2; " + \
           "mkdir /scratch/tmp_busco_2; " + \
           "run_busco --in {input[1]} " + \
                     "--out busco_GRCh38 " + \
                     "--lineage_path busco_lineage/mammalia_odb9 " + \
                     "--mode genome " + \
                     "--force " + \
                     "--cpu 24 " + \
                     "--blast_single_core " + \
                     "--tmp /scratch/tmp_busco_2; " + \
                     "rm -rf /scratch/tmp_busco_2; "

# Downloading all GRCh38 sequence data available from Ensembl (release 93,
# but note, that on sequence level, the release shouldn't make a difference)
rule download_GRCh38:
    output: "seq_GRCh38/Homo_sapiens.GRCh38.{dna_type}.{chr_or_type}.fa.gz"
    run: 
        # Remove target dir to obtain file name for download
        base = output[0].split("/")[1]
        shell("wget -P seq_GRCh38 " + \
        "ftp://ftp.ensembl.org/pub/release-93/fasta/homo_sapiens/dna/{base}")
              
# Download README
rule download_GRCh38_readme:
    output: "seq_GRCh38/README"
    shell: "wget -P seq_GRCh38 " + \
           "ftp://ftp.ensembl.org/pub/release-93/fasta/homo_sapiens/dna/README"

# Downloading all GRCh38 sequence files available under the ENSEMBLE release 93
# FTP address 
CHR_OR_TYPE = ["chromosome."+str(x) for x in range(1,23)] \
       + ["chromosome."+str(x) for x in ["MT","X","Y"]] \
       + ["nonchromosomal","primary_assembly","toplevel","alt"]
rule download_GRCh38_all:
    input: expand("seq_GRCh38/"+ \
                  "Homo_sapiens.GRCh38.{dna_type}.{chr_or_type}.fa.gz", \
            dna_type=["dna","dna_rm","dna_sm"],chr_or_type=CHR_OR_TYPE),
           "seq_GRCh38/README"

# Uncompressing fasta files, needed e.g. for Busco analysis
# -d decompress; -k keep archive; -c to stdout
rule uncompress_fasta:
    input: "seq_GRCh38/{fname}.fa.gz"
    output: "seq_GRCh38/{fname}.fa"
    shell: "gzip -cdk {input} > {output}"

# Copy the assembled sequence
rule cp_and_rename_assembly:
    input: "data/pilon.fasta"
    output: "seq_EGYPTREF/Homo_sapiens.EGYPTREF.dna.toplevel.fa"
    shell: "cp {input} {output}"

# Running repeatmasker on the Egyptian genome assembly
# I use a separate environment for repeatmasker, because, as of now, it cannot 
# be used together with the newest busco version and installing it together 
# would result in downgrading of augustus, blast, boost and busco to older 
# versions.
# -s  Slow search; 0-5% more sensitive, 2-3 times slower than default
# -q  Quick search; 5-10% less sensitive, 2-5 times faster than default
# -qq Rush job; about 10% less sensitive, 4->10 times faster than default
# -html Creates an additional output file in xhtml format
# -gff Creates an additional Gene Feature Finding format output
rule run_repeatmasker:
    input: "seq_{assembly}/Homo_sapiens.{assembly}.dna.toplevel.fa"
    output: "repeatmasked_{assembly}/Homo_sapiens.{assembly}.dna.toplevel.fa.cat",
            "repeatmasked_{assembly}/Homo_sapiens.{assembly}.dna.toplevel.fa.masked",
            "repeatmasked_{assembly}/Homo_sapiens.{assembly}.dna.toplevel.fa.out",
            "repeatmasked_{assembly}/Homo_sapiens.{assembly}.dna.toplevel.fa.out.gff",
            "repeatmasked_{assembly}/Homo_sapiens.{assembly}.dna.toplevel.fa.out.html",
            "repeatmasked_{assembly}/Homo_sapiens.{assembly}.dna.toplevel.fa.tbl"
    threads: 24
    conda: "envs/repeatmasker.yaml"
    shell: "workdir=$PWD; cd /scratch; " + \
           "rm -rf /scratch/repeatmasked_{wildcards.assembly}; " + \
           "mkdir /scratch/repeatmasked_{wildcards.assembly}; " + \
           "RepeatMasker -species mammalia " + \
           "             -dir /scratch/repeatmasked_{wildcards.assembly} " + \
           "             -pa 24 " + \
           "             -xsmall " + \
           "             -q " + \
           "             -html " + \
           "             -gff $workdir/{input}; " + \
           "cd $workdir; "
           "rsync -avz /scratch/repeatmasked_{wildcards.assembly} .; " + \
           "rm -rf /scratch/repeatmasked_{wildcards.assembly}; "

rule run_repeatmasker_all:
    input: "repeatmasked_GRCh38/Homo_sapiens.GRCh38.dna.toplevel.fa.tbl",
           "repeatmasked_EGYPTREF/Homo_sapiens.EGYPTREF.dna.toplevel.fa.tbl"
            

