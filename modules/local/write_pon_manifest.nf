process WRITE_PON_MANIFEST {
    tag "manifest"
    label 'process_single'

    input:
    path  pon
    val   sample_entries   // List<String>, e.g. "EIW25_01_N03 [bam]"

    output:
    path "*.manifest.txt", emit: manifest

    when:
    task.ext.when == null || task.ext.when

    exec:
    def pon_version = params.pon_version ?: workflow.manifest.version ?: '1.0'
    def build_notes = params.build_notes ?: 'N/A'
    def pon_args    = params.pon_args ?: '(GATK defaults)'
    def n_samples   = sample_entries.size()
    def sample_list = sample_entries.sort().collect { "- ${it}" }.join('\n')
    def timestamp   = new java.util.Date().format('yyyy-MM-dd HH:mm:ss')

    def manifest_file = task.workDir.resolve("${pon.baseName}.manifest.txt")
    manifest_file.text = """\
        #===============================================================================
        # PON Build Manifest
        # Generated: ${timestamp}
        # Pipeline:  ${workflow.manifest.name} v${workflow.manifest.version}
        # Run name:  ${workflow.runName}
        # PON file:  ${pon.name}
        # Version:   ${pon_version}
        #===============================================================================

        ## Build Parameters
        - Reference FASTA:     ${params.fasta}
        - Reference dict:      ${params.dict}
        - Intervals:           ${params.intervals ?: '(WGS mode, no intervals)'}
        - Exclude intervals:   ${params.exclude_intervals ?: '(none)'}
        - Padding:             ${params.padding} bp
        - Bin length:          ${params.bin_length}
        - GATK container:      docker.io/broadinstitute/gatk:4.6.2.0
        - Samples in PON:      ${n_samples}

        ## CreateReadCountPanelOfNormals arguments
        ${pon_args}

        ## Samples Included
        ${sample_list}

        ## Notes
        ${build_notes}
        """.stripIndent()
}
