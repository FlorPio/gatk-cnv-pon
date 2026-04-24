/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    CREATE PANEL OF NORMALS WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Steps:
      1. PreprocessIntervals — prepare interval list with padding/binning
      2. CollectReadCounts  — count reads per interval for each normal
      3. CreateReadCountPanelOfNormals — merge all counts into a single PON
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// nf-core modules
include { GATK4_PREPROCESSINTERVALS          } from '../modules/nf-core/gatk4/preprocessintervals/main'
include { GATK4_COLLECTREADCOUNTS            } from '../modules/nf-core/gatk4/collectreadcounts/main'

// Local modules
include { CREATEREADCOUNTPANELOFNORMALS      } from '../modules/local/createreadcountpanelofnormals'

workflow CREATE_PON {

    take:
    ch_normals  // channel: [ meta, bam, bai ]

    main:

    ch_versions = Channel.empty()

    // =========================================
    // Reference channels
    // NOTE: FASTA must be main chromosomes only
    //       (hg38 without alt/decoy/HLA contigs)
    // =========================================

    ch_fasta = Channel.value([ [:], file(params.fasta) ])
    ch_fai   = Channel.value([ [:], file(params.fai) ])
    ch_dict  = Channel.value([ [:], file(params.dict) ])

    // Intervals: optional for WGS, required for WES
    ch_intervals         = params.intervals
        ? Channel.value([ [:], file(params.intervals) ])
        : Channel.value([ [:], [] ])
    ch_exclude_intervals = params.exclude_intervals
        ? Channel.value([ [:], file(params.exclude_intervals) ])
        : Channel.value([ [:], [] ])

    // =========================================
    // 1. PREPROCESS INTERVALS
    //    Pads and bins the interval list.
    //    For WES: use capture targets with padding.
    //    For WGS: bins the genome into windows.
    // =========================================

    GATK4_PREPROCESSINTERVALS(
        ch_fasta,
        ch_fai,
        ch_dict,
        ch_intervals,
        ch_exclude_intervals
    )
    ch_versions = ch_versions.mix(GATK4_PREPROCESSINTERVALS.out.versions)

    ch_preprocessed_intervals = GATK4_PREPROCESSINTERVALS.out.interval_list
        .map { meta, interval_list -> interval_list }

    // =========================================
    // 2. COLLECT READ COUNTS (per normal)
    // =========================================

    ch_normals_with_intervals = ch_normals
        .map { meta, bam, bai ->
            [ meta, bam, bai, ch_preprocessed_intervals ]
        }

    GATK4_COLLECTREADCOUNTS(
        ch_normals_with_intervals,
        ch_fasta,
        ch_fai,
        ch_dict
    )
    ch_versions = ch_versions.mix(GATK4_COLLECTREADCOUNTS.out.versions.first())

    // =========================================
    // 3. CREATE PANEL OF NORMALS
    //    Collects all HDF5 counts and merges
    //    into a single PON file.
    // =========================================

    ch_all_counts = GATK4_COLLECTREADCOUNTS.out.hdf5
        .map { meta, hdf5 -> hdf5 }
        .collect()

    CREATEREADCOUNTPANELOFNORMALS(
        ch_all_counts
    )
    ch_versions = ch_versions.mix(CREATEREADCOUNTPANELOFNORMALS.out.versions)

    emit:
    pon      = CREATEREADCOUNTPANELOFNORMALS.out.pon
    versions = ch_versions
}
