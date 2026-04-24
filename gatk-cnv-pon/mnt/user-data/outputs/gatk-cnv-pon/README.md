# GATK CNV Panel of Normals Pipeline

Nextflow pipeline to create a GATK Panel of Normals (PON) for somatic CNV analysis.

## Overview

```
Normal BAMs ──► PreprocessIntervals ──► CollectReadCounts ──► CreateReadCountPanelOfNormals ──► PON.hdf5
                    (once)                (per sample)              (merge all)
```

## Quick Start

### 1. Prepare Samplesheet

```csv
sample,bam
Normal_01,/path/to/Normal_01.recal.bam
Normal_02,/path/to/Normal_02.recal.bam
```

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

The output `pon_results/pon/cnv_somatic.pon.hdf5` is used directly by the [gatk-cnv-somatic](https://github.com/FlorPio/gatk-cnv-somatic) pipeline via the `--pon` parameter.

## Parameters

| Parameter | Description | Default |
|---|---|---|
| `--input` | Samplesheet CSV (sample,bam) | Required |
| `--outdir` | Output directory | Required |
| `--fasta` | Reference genome FASTA (main chroms only) | Required |
| `--intervals` | Target intervals (WES) or null (WGS) | `null` |
| `--exclude_intervals` | Blacklist regions | `null` |
| `--bin_length` | Bin size (0 = no binning, use for WES) | `0` |
| `--padding` | Padding around intervals (bp) | `250` |
| `--pon_name` | Output PON file prefix | `cnv_somatic` |

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

- Use **≥20 normal samples** for a robust PON
- All normals must be processed with the **same reference genome** and **same intervals**
- Do not mix WES and WGS normals in the same PON
- Exclude normals with known germline CNVs from the PON
- The **same GATK version** should be used for PON creation and CNV calling

## Author

**Florencia Piovaroli** — [@FlorPio](https://github.com/FlorPio)
