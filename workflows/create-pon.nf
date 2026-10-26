/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    CREATE PANEL OF NORMALS WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Steps:
      1. PreprocessIntervals — prepare interval list with padding/binning
      2. AnnotateIntervals  — (optional) annotate with %GC, mappability, segdup
      3. CollectReadCounts  — count reads per interval for each normal
      4. CreateReadCountPanelOfNormals — merge all counts into a single PON,
         using annotated intervals if explicit GC correction is enabled
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// nf-core modules
include { GATK4_PREPROCESSINTERVALS          } from '../modules/nf-core/gatk4/preprocessintervals/main'
include { GATK4_COLLECTREADCOUNTS            } from '../modules/nf-core/gatk4/collectreadcounts/main'

// Local modules
include { ANNOTATEINTERVALS                  } from '../modules/local/annotateintervals'
include { CREATEREADCOUNTPANELOFNORMALS      } from '../modules/local/createreadcountpanelofnormals'
include { WRITE_PON_MANIFEST                 } from '../modules/local/write_pon_manifest'

workflow CREATE_PON {

    take:
    ch_normals          // channel: [ meta, bam, bai ]   -> run CollectReadCounts
    ch_existing_counts  // channel: [ meta, hdf5 ]       -> pre-computed HDF5 from another pipeline

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
    ch_versions = ch_versions.mix(GATK4_PREPROCESSINTERVALS.out.versions_gatk4)

    // Convert to value channel so the same interval_list can be reused by
    // both ANNOTATEINTERVALS and the .combine() with CollectReadCounts.
    ch_preprocessed_intervals = GATK4_PREPROCESSINTERVALS.out.interval_list
        .map { meta, interval_list -> interval_list }
        .first()

    // =========================================
    // 2. ANNOTATE INTERVALS (optional)
    //    Adds %GC (always, from FASTA), plus
    //    mappability and segdup tracks if given.
    //    Enables explicit GC correction in PON.
    // =========================================

    if (params.do_explicit_gc_correction) {

        ch_mappability = params.mappability_track_bed
            ? Channel.value([
                file(params.mappability_track_bed,     checkIfExists: true),
                file("${params.mappability_track_bed}.tbi", checkIfExists: true)
            ])
            : Channel.value([ [], [] ])

        ch_segdup = params.segmental_duplication_track_bed
            ? Channel.value([
                file(params.segmental_duplication_track_bed,     checkIfExists: true),
                file("${params.segmental_duplication_track_bed}.tbi", checkIfExists: true)
            ])
            : Channel.value([ [], [] ])

        ANNOTATEINTERVALS(
            ch_preprocessed_intervals,
            ch_fasta,
            ch_fai,
            ch_dict,
            ch_mappability,
            ch_segdup
        )
        ch_versions = ch_versions.mix(ANNOTATEINTERVALS.out.versions)
        ch_annotated_intervals = ANNOTATEINTERVALS.out.annotated
    } else {
        ch_annotated_intervals = Channel.value([])
    }

    // =========================================
    // 3. COLLECT READ COUNTS (per normal)
    // =========================================

    ch_normals_with_intervals = ch_normals.combine(ch_preprocessed_intervals)

    GATK4_COLLECTREADCOUNTS(
        ch_normals_with_intervals,
        ch_fasta,
        ch_fai,
        ch_dict
    )
    ch_versions = ch_versions.mix(GATK4_COLLECTREADCOUNTS.out.versions_gatk4.first())

    // =========================================
    // 4. CREATE PANEL OF NORMALS
    //    Collects all HDF5 counts and merges
    //    into a single PON file.
    // =========================================

    ch_all_counts = GATK4_COLLECTREADCOUNTS.out.hdf5
        .mix(ch_existing_counts)
        .map { meta, hdf5 -> hdf5 }
        .collect()

    CREATEREADCOUNTPANELOFNORMALS(
        ch_all_counts,
        ch_annotated_intervals
    )
    ch_versions = ch_versions.mix(CREATEREADCOUNTPANELOFNORMALS.out.versions)

    // =========================================
    // 4. WRITE BUILD MANIFEST
    //    Documents how this PON was built:
    //    parameters, sample list, build notes.
    // =========================================

    ch_sample_entries = ch_normals
        .map { meta, bam, bai -> "${meta.id} [bam]" }
        .mix(
            ch_existing_counts.map { meta, hdf5 -> "${meta.id} [precomputed counts]" }
        )
        .collect()

    WRITE_PON_MANIFEST(
        CREATEREADCOUNTPANELOFNORMALS.out.pon,
        ch_sample_entries
    )

    emit:
    pon      = CREATEREADCOUNTPANELOFNORMALS.out.pon
    manifest = WRITE_PON_MANIFEST.out.manifest
    versions = ch_versions
}
