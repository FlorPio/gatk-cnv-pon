# GATK CNV Panel of Normals Pipeline

Nextflow pipeline to create a GATK Panel of Normals (PON) for somatic CNV analysis.

## Overview

```
Normal BAMs ──► PreprocessIntervals ──► AnnotateIntervals ──► CollectReadCounts ──► CreateReadCountPanelOfNormals ──► PON.hdf5
                    (once)              (optional, GC corr.)     (per sample)              (merge all)                 + manifest.txt

Pre-computed counts ─────────────────────────────────────────────────────────────────┘
(skip CollectReadCounts)
```

The PON is built from **germline/normal** samples (never tumor). It captures the systematic technical noise of your workflow (GC bias, per-target capture efficiency, batch effects) so the somatic pipeline can denoise tumors against it.

## Quick Start

### 1. Prepare Samplesheet

The samplesheet has three columns: `sample`, `bam`, `counts`. For each row set **exactly one** of `bam` or `counts`:

```csv
sample,bam,counts
Normal_01,/path/to/Normal_01.recal.bam,
Normal_02,/path/to/Normal_02.recal.bam,
Normal_03,,/path/to/Normal_03.counts.hdf5
```

- **`bam` set** → the pipeline runs `CollectReadCounts` for that normal.
- **`counts` set** → a read-count file (HDF5 or TSV) already produced elsewhere is used directly, skipping `CollectReadCounts`.

BAM and pre-computed normals can be mixed in the same run. Pre-computed counts **must** have been generated with the exact same intervals (same reference, padding, bin length, interval-merging rule) as this pipeline produces — otherwise `CreateReadCountPanelOfNormals` rejects the mismatched files.

Or use the interactive PON manager:
```bash
./pon_manager.sh
```

### 2. Run Pipeline

```bash
nextflow run FlorPio/gatk-cnv-pon \
    -profile docker \
    -params-file params.json \
    --input pon_samplesheet.csv \
    --outdir pon_results
```

### 3. Use the PON

The output `pon_results/pon/<pon_name>.pon.hdf5` is used directly by the [gatk-cnv-somatic](https://github.com/FlorPio/gatk-cnv-somatic) pipeline via the `--pon` parameter.

**Important:** the somatic pipeline must count the tumor over the **same preprocessed interval list** this build publishes (`pon_results/intervals/<pon_name>.preprocessed.interval_list`), not the raw capture `.interval_list`/`.bed`. Otherwise `DenoiseReadCounts` fails with *"Sample intervals must be identical to the original intervals used to build the panel of normals."*

## Outputs

| Path | Description |
|---|---|
| `<outdir>/pon/<pon_name>.pon.hdf5` | The Panel of Normals |
| `<outdir>/pon/<pon_name>.manifest.txt` | Build manifest: parameters, GATK args, and the sample list (`[bam]` vs `[precomputed counts]`) |
| `<outdir>/intervals/<pon_name>.preprocessed.interval_list` | Preprocessed intervals — feed this to the somatic pipeline |
| `<outdir>/intervals/<pon_name>.annotated.tsv` | Annotated intervals (when GC correction is enabled) |
| `<outdir>/counts/*.hdf5` | Per-normal read counts |

## Parameters

### Core
| Parameter | Description | Default |
|---|---|---|
| `--input` | Samplesheet CSV (`sample,bam,counts`) | Required |
| `--outdir` | Output directory | Required |
| `--fasta` | Reference genome FASTA (main chroms only) | Required |
| `--intervals` | Target intervals (WES) or null (WGS) | `null` |
| `--exclude_intervals` | Blacklist regions | `null` |
| `--bin_length` | Bin size (0 = no binning, use for WES) | `0` |
| `--padding` | Padding around intervals (bp) | `50` |
| `--pon_name` | Output PON file prefix | `cnv_somatic` |

### Manifest
| Parameter | Description | Default |
|---|---|---|
| `--pon_version` | Version tag recorded in the manifest | `null` |
| `--build_notes` | Free-form notes recorded in the manifest | `null` |
| `--pon_args` | Extra args for `CreateReadCountPanelOfNormals` (also recorded in the manifest) | `null` |

### Explicit GC correction
| Parameter | Description | Default |
|---|---|---|
| `--do_explicit_gc_correction` | Run `AnnotateIntervals` and pass the result to the PON via `--annotated-intervals` | `true` |
| `--mappability_track_bed` | Optional mappability track (`.bed.gz` with `.tbi`) | `null` |
| `--segmental_duplication_track_bed` | Optional segmental-duplication track (`.bed.gz` with `.tbi`) | `null` |
| `--feature_query_lookahead` | `AnnotateIntervals` lookahead (bp) | `1000000` |

When `--do_explicit_gc_correction` is `true` (the default), `AnnotateIntervals` computes %GC from the FASTA (always) plus the mappability/segdup tracks if provided, and the PON applies explicit GC-bias correction.

## PON Manager

The `pon_manager.sh` script helps manage which normal samples go into the PON:

```bash
# Interactive mode
./pon_manager.sh

# CLI mode
./pon_manager.sh add --sample 711_N01 --bam /path/to/bam --run run_2025_03
./pon_manager.sh list
./pon_manager.sh rebuild
```

See `./pon_manager.sh --help` for full usage.

## GATK Recommendations

- Use **germline/normal** samples only — never tumor
- Use **≥20 normal samples** for a robust PON
- All normals (and the tumor denoised against the PON) must be processed with the **same reference genome** and **same intervals**
- Do not mix WES and WGS normals in the same PON
- Exclude normals with known germline CNVs from the PON
- The **same GATK version** should be used for PON creation and CNV calling

## Author

**Florencia Piovaroli** — [@FlorPio](https://github.com/FlorPio)
