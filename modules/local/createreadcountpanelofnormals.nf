process CREATEREADCOUNTPANELOFNORMALS {
    tag "PON"
    label 'process_medium'

    conda "bioconda::gatk4=4.6.2.0"
    container "docker.io/broadinstitute/gatk:4.6.2.0"

    input:
    path(counts)   // collected list of HDF5 files

    output:
    path("*.pon.hdf5"), emit: pon
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: params.pon_name ?: 'cnv_somatic'

    // Build --input arguments for each HDF5 file
    def input_args = counts.collect { "--input ${it}" }.join(' \\\n        ')

    def avail_mem = 3072
    if (!task.memory) {
        log.info('[GATK CreateReadCountPanelOfNormals] Available memory not known - defaulting to 3GB.')
    } else {
        avail_mem = (task.memory.mega * 0.8).intValue()
    }
    """
    gatk --java-options "-Xmx${avail_mem}M -XX:-UsePerfData" \\
        CreateReadCountPanelOfNormals \\
        ${input_args} \\
        --output ${prefix}.pon.hdf5 \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        gatk4: \$(echo \$(gatk --version 2>&1) | sed 's/^.*(GATK) v//; s/ .*\$//')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: params.pon_name ?: 'cnv_somatic'
    """
    touch ${prefix}.pon.hdf5

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        gatk4: \$(echo \$(gatk --version 2>&1) | sed 's/^.*(GATK) v//; s/ .*\$//')
    END_VERSIONS
    """
}
