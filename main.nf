#!/usr/bin/env nextflow

/*
 * AHRR — human read removal
 *
 * Authors: Aaron Berkman, Mamana Mbiyavanga, Shaun Aron, Scott Hazelhurst
 * Licence: MIT
 *
 * Wraps NCBI sra-human-scrubber (scripts/scrub.sh) as a Nextflow workflow that
 * can run behind a GA4GH WES endpoint. A caller stages the input FASTQ as a
 * DRS object; WES resolves that DRS URI to a local path on the node that runs
 * the task and passes it in as `params.reads`. The k-mer database
 * (`params.db`) is supplied per node, never staged from user input, and never
 * returned to the submitter.
 */

nextflow.enable.dsl = 2

// --- Parameters (names must match workflow.yaml input_param/output_param) ---
params.reads        = null                                   // WES injects the DRS-resolved FASTQ path here
params.outdir       = 'results'                              // published outputs
params.db           = '/opt/scrubber/data/human_filter.db'   // node-local database — never a user input, never returned
params.remove       = false                                  // false = mask human reads to 'N'; true = drop them (scrub.sh -x)
params.keep_removed = false                                  // true = also emit the removed human reads (scrub.sh -r)
params.cpus         = 2                                       // SCRUB CPUs — raise per deployment
params.mem          = '4 GB'                                  // SCRUB memory — raise for large inputs and large databases

process SCRUB {
    tag   { reads.simpleName }
    cpus  params.cpus
    publishDir params.outdir, mode: 'copy'

    input:
    path reads
    path db

    output:
    path "*.fastq.clean",            emit: clean
    path "*.human_spots.fastq",      optional: true, emit: removed
    path "scrub_report.txt",         emit: report

    script:
    // Flags derived from the submitter's choices (see workflow.yaml inputs).
    // Coerce to real booleans. A string such as "false" is truthy in Groovy,
    // and a raw param must never be interpolated into the shell script below.
    def remove_b    = params.remove.toString().toBoolean()
    def keep_b      = params.keep_removed.toString().toBoolean()
    def remove_flag = remove_b ? '-x' : ''
    def keep_flag   = keep_b   ? '-r' : ''
    """
    set -euo pipefail

    # Stream the FASTQ through scrub.sh (stdin -> stdout). Streaming avoids a
    # second full on-disk copy, which matters for whole-run FASTQ. Decompress
    # gzip on the fly so either .fastq or .fastq.gz can be submitted.
    reader=cat
    case "${reads}" in *.gz) reader=zcat ;; esac
    base="${reads.simpleName}"

    \$reader "${reads}" \\
      | scrub.sh -d "${db}" -p ${task.cpus} ${remove_flag} ${keep_flag} \\
      > "\${base}.fastq.clean" 2> scrub_report.txt

    # When removed reads were requested, normalise scrub.sh's removed-reads
    # output to the published name. The match is deliberately broad: the exact
    # filename has varied between scrubber releases.
    if [ "${keep_b}" = "true" ]; then
      for f in *.removed_spots *removed*; do
        if [ -e "\$f" ] && [ "\$f" != "\${base}.fastq.clean" ]; then
          mv "\$f" "\${base}.human_spots.fastq"; break
        fi
      done
    fi
    """
}

workflow {
    if( !params.reads )
        error "No input reads provided. params.reads is set from the resolved DRS object(s)."

    // params.reads is one path, or a list (multi-file, paired-end R1+R2, or
    // multi-lane). Each file is scrubbed independently -> one *.fastq.clean each.
    reads_ch = Channel.fromPath( params.reads instanceof List ? params.reads : [params.reads] )

    SCRUB( reads_ch, file(params.db) )
}
