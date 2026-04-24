// ModelSegments for normal samples — copy-ratio only mode.
// Used as QC: detects CNVs in the normal that could
// indicate the sample is unsuitable for somatic analysis
// or should be excluded from the Panel of Normals.
//
// This is the normal-only step from the GATK official
// cnv_somatic_pair_workflow.wdl.

process MODELSEGMENTS_NORMAL {
    tag "${meta.id}"
    label 'process_low'

    conda "bioconda::gatk4=4.6.2.0"
    container "docker.io/broadinstitute/gatk:4.6.2.0"

    input:
    tuple val(meta), path(denoised_cr)

    output:
    tuple val(meta), path("*.modelFinal.seg"),  emit: segments
    tuple val(meta), path("*.cr.seg"),          emit: cr_segments
    tuple val(meta), path("*.modelBegin.seg"),  emit: model_begin, optional: true
    tuple val(meta), path("*.modelFinal.cr.param"), emit: cr_param, optional: true
    path "versions.yml",                        emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    def avail_mem = 3072
    if (!task.memory) {
        log.info('[GATK ModelSegments Normal] Available memory not known - defaulting to 3GB.')
    } else {
        avail_mem = (task.memory.mega * 0.8).intValue()
    }
    """
    gatk --java-options "-Xmx${avail_mem}M -XX:-UsePerfData" \\
        ModelSegments \\
        --denoised-copy-ratios ${denoised_cr} \\
        --output-prefix ${prefix} \\
        -O . \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        gatk4: \$(echo \$(gatk --version 2>&1) | sed 's/^.*(GATK) v//; s/ .*\$//')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.modelFinal.seg
    touch ${prefix}.cr.seg

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        gatk4: \$(echo \$(gatk --version 2>&1) | sed 's/^.*(GATK) v//; s/ .*\$//')
    END_VERSIONS
    """
}
