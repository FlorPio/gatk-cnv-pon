process ANNOTATEINTERVALS {
    tag "annotate"
    label 'process_low'

    conda "bioconda::gatk4=4.6.2.0"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ce/ced519873646379e287bc28738bdf88e975edd39a92e7bc6a34bccd37153d9d0/data'
        : 'community.wave.seqera.io/library/gatk4_gcnvkernel:edb12e4f0bf02cd3'}"

    input:
    path intervals
    tuple val(meta_ref),  path(fasta)
    tuple val(meta_fai),  path(fai)
    tuple val(meta_dict), path(dict)
    tuple path(mappability_bed), path(mappability_tbi)
    tuple path(segdup_bed),      path(segdup_tbi)

    output:
    path "*.annotated.tsv",  emit: annotated
    path "versions.yml",     emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: 'preprocessed'

    def mappability_arg = mappability_bed ? "--mappability-track ${mappability_bed}"        : ''
    def segdup_arg      = segdup_bed      ? "--segmental-duplication-track ${segdup_bed}"   : ''

    def avail_mem = 3072
    if (!task.memory) {
        log.info('[GATK AnnotateIntervals] Available memory not known - defaulting to 3GB.')
    } else {
        avail_mem = (task.memory.mega * 0.8).intValue()
    }
    """
    gatk --java-options "-Xmx${avail_mem}M -XX:-UsePerfData" \\
        AnnotateIntervals \\
        --intervals ${intervals} \\
        --reference ${fasta} \\
        ${mappability_arg} \\
        ${segdup_arg} \\
        --output ${prefix}.annotated.tsv \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        gatk4: \$(echo \$(gatk --version 2>&1) | sed 's/^.*(GATK) v//; s/ .*\$//')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: 'preprocessed'
    """
    touch ${prefix}.annotated.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        gatk4: \$(echo \$(gatk --version 2>&1) | sed 's/^.*(GATK) v//; s/ .*\$//')
    END_VERSIONS
    """
}
