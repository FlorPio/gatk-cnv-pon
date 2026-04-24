#!/usr/bin/env bash
# ============================================================
# pon_manager.sh — Interactive PON Registry Manager
# ============================================================
# Manages a registry of approved normal samples for building
# a GATK Panel of Normals (PON) for somatic CNV analysis.
#
# Usage:
#   ./pon_manager.sh                     # Interactive menu
#   ./pon_manager.sh add --sample ID --bam /path/to/bam [--run RUN_ID]
#   ./pon_manager.sh list
#   ./pon_manager.sh remove --sample ID
#   ./pon_manager.sh rebuild [--dry-run]
#   ./pon_manager.sh export
#
# The registry is stored as a TSV file (default: pon_registry.tsv)
# ============================================================

set -euo pipefail

# ============================================================
# CONFIGURATION — edit these to match your environment
# ============================================================
REGISTRY_FILE="${PON_REGISTRY:-pon_registry.tsv}"
PON_PIPELINE="${PON_PIPELINE:-FlorPio/gatk-cnv-pon}"
PON_OUTPUT_DIR="${PON_OUTPUT_DIR:-pon_results}"
NEXTFLOW_PROFILE="${NEXTFLOW_PROFILE:-docker}"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ============================================================
# HELPER FUNCTIONS
# ============================================================

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}     GATK CNV — Panel of Normals Manager          ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_info()    { echo -e "${BLUE}ℹ${NC}  $1"; }
print_success() { echo -e "${GREEN}✓${NC}  $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC}  $1"; }
print_error()   { echo -e "${RED}✗${NC}  $1"; }

# Initialize registry if it doesn't exist
init_registry() {
    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo -e "sample_id\tbam_path\tdate_added\trun_origin\tstatus\tnotes" > "$REGISTRY_FILE"
        print_info "Created new registry: ${REGISTRY_FILE}"
    fi
}

# Count approved samples
count_approved() {
    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "0"
        return 0
    fi
    awk -F'\t' '$5 == "approved" { count++ } END { print count+0 }' "$REGISTRY_FILE"
}

# Check if sample exists in registry
sample_exists() {
    local sample_id="$1"
    grep -q "^${sample_id}	" "$REGISTRY_FILE" 2>/dev/null
}

# Validate BAM file exists and has index
validate_bam() {
    local bam_path="$1"
    local errors=0

    if [[ ! -f "$bam_path" ]]; then
        print_error "BAM file not found: ${bam_path}"
        errors=1
    fi

    local bai_path="${bam_path}.bai"
    local bai_path_alt="${bam_path%.bam}.bai"
    if [[ ! -f "$bai_path" ]] && [[ ! -f "$bai_path_alt" ]]; then
        print_warning "BAM index not found (.bai). You may need to run: samtools index ${bam_path}"
    fi

    return $errors
}

# ============================================================
# COMMAND: add
# ============================================================
cmd_add() {
    local sample_id=""
    local bam_path=""
    local run_origin="manual"
    local notes=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sample)  sample_id="$2";  shift 2 ;;
            --bam)     bam_path="$2";   shift 2 ;;
            --run)     run_origin="$2";  shift 2 ;;
            --notes)   notes="$2";       shift 2 ;;
            *)         print_error "Unknown option: $1"; return 1 ;;
        esac
    done

    if [[ -z "$sample_id" ]] || [[ -z "$bam_path" ]]; then
        print_error "Usage: pon_manager.sh add --sample SAMPLE_ID --bam /path/to/bam [--run RUN_ID] [--notes TEXT]"
        return 1
    fi

    init_registry

    if sample_exists "$sample_id"; then
        print_warning "Sample ${sample_id} already in registry. Use 'remove' first to re-add."
        return 1
    fi

    # Resolve to absolute path
    bam_path="$(realpath "$bam_path" 2>/dev/null || echo "$bam_path")"

    validate_bam "$bam_path" || return 1

    local date_added
    date_added=$(date +%Y-%m-%d)

    echo -e "${sample_id}\t${bam_path}\t${date_added}\t${run_origin}\tapproved\t${notes}" >> "$REGISTRY_FILE"
    print_success "Added ${sample_id} to registry (run: ${run_origin}, date: ${date_added})"

    local count
    count=$(count_approved)
    print_info "Total approved normals: ${count}"

    if [[ "$count" -lt 20 ]]; then
        print_warning "GATK recommends ≥20 normals for a robust PON (currently ${count})"
    fi
}

# ============================================================
# COMMAND: list
# ============================================================
cmd_list() {
    init_registry

    local count
    count=$(count_approved)

    echo ""
    echo -e "${BOLD}PON Registry: ${REGISTRY_FILE}${NC}"
    echo -e "${BOLD}Approved normals: ${count}${NC}"
    echo ""

    if [[ "$count" -eq 0 ]]; then
        print_info "No samples in registry yet. Use 'add' to register normal samples."
        return 0
    fi

    # Print formatted table
    echo -e "${BOLD}Sample ID          Status     Date Added  Run Origin       BAM Path${NC}"
    echo "─────────────────  ─────────  ──────────  ───────────────  ────────────────────"
    tail -n +2 "$REGISTRY_FILE" | while IFS=$'\t' read -r sid bam date run status notes; do
        local status_color
        case "$status" in
            approved) status_color="${GREEN}" ;;
            excluded) status_color="${RED}" ;;
            *)        status_color="${YELLOW}" ;;
        esac
        local bam_short
        bam_short=$(basename "$bam")
        printf "%-18s ${status_color}%-9s${NC}  %-10s  %-15s  %s\n" \
            "$sid" "$status" "$date" "$run" "$bam_short"
    done

    echo ""
    if [[ "$count" -lt 20 ]]; then
        print_warning "GATK recommends ≥20 normals for a robust PON (currently ${count})"
    else
        print_success "PON has sufficient normals (${count} ≥ 20)"
    fi
}

# ============================================================
# COMMAND: remove
# ============================================================
cmd_remove() {
    local sample_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sample)  sample_id="$2";  shift 2 ;;
            *)         print_error "Unknown option: $1"; return 1 ;;
        esac
    done

    if [[ -z "$sample_id" ]]; then
        print_error "Usage: pon_manager.sh remove --sample SAMPLE_ID"
        return 1
    fi

    init_registry

    if ! sample_exists "$sample_id"; then
        print_error "Sample ${sample_id} not found in registry."
        return 1
    fi

    # Mark as excluded instead of deleting (audit trail)
    sed -i "s/^${sample_id}\(.*\)approved/\1excluded/" "$REGISTRY_FILE" 2>/dev/null || \
        # macOS sed compatibility
        sed -i '' "s/^${sample_id}\(.*\)approved/${sample_id}\1excluded/" "$REGISTRY_FILE"

    print_success "Marked ${sample_id} as excluded"
    print_info "To permanently remove, edit ${REGISTRY_FILE} manually"
}

# ============================================================
# COMMAND: export — generate samplesheet for Nextflow pipeline
# ============================================================
cmd_export() {
    init_registry

    local output="${1:-pon_samplesheet.csv}"

    local count
    count=$(count_approved)

    if [[ "$count" -eq 0 ]]; then
        print_error "No approved samples in registry. Nothing to export."
        return 1
    fi

    # Generate CSV samplesheet
    echo "sample,bam" > "$output"
    tail -n +2 "$REGISTRY_FILE" | while IFS=$'\t' read -r sid bam date run status notes; do
        if [[ "$status" == "approved" ]]; then
            echo "${sid},${bam}" >> "$output"
        fi
    done

    print_success "Exported ${count} samples to ${output}"
    return 0
}

# ============================================================
# COMMAND: rebuild — export samplesheet and run pipeline
# ============================================================
cmd_rebuild() {
    local dry_run=false
    local params_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)     dry_run=true;      shift ;;
            --params-file) params_file="$2";  shift 2 ;;
            *)             print_error "Unknown option: $1"; return 1 ;;
        esac
    done

    init_registry

    local count
    count=$(count_approved)

    if [[ "$count" -lt 2 ]]; then
        print_error "Need at least 2 approved normals to build a PON (have ${count})"
        return 1
    fi

    if [[ "$count" -lt 20 ]]; then
        print_warning "Building PON with only ${count} normals (GATK recommends ≥20)"
        echo -n "    Continue anyway? [y/N] "
        read -r response
        if [[ ! "$response" =~ ^[Yy] ]]; then
            print_info "Aborted."
            return 0
        fi
    fi

    # Export samplesheet
    cmd_export "pon_samplesheet.csv" || return 1

    # Build nextflow command
    local nf_cmd="nextflow run ${PON_PIPELINE} \
        -profile ${NEXTFLOW_PROFILE} \
        --input pon_samplesheet.csv \
        --outdir ${PON_OUTPUT_DIR}"

    if [[ -n "$params_file" ]]; then
        nf_cmd="${nf_cmd} -params-file ${params_file}"
    fi

    echo ""
    print_info "Nextflow command:"
    echo "    ${nf_cmd}"
    echo ""

    if [[ "$dry_run" == true ]]; then
        print_info "Dry run — command not executed"
        return 0
    fi

    echo -n "Execute? [y/N] "
    read -r response
    if [[ "$response" =~ ^[Yy] ]]; then
        eval "$nf_cmd"
    else
        print_info "Aborted. You can run the command manually."
    fi
}

# ============================================================
# INTERACTIVE MODE
# ============================================================
interactive_menu() {
    print_header
    init_registry

    local running=true
    while [[ "$running" == true ]]; do

        local count
        count=$(count_approved)

        echo ""
        echo -e "${BOLD}─── Main Menu ─── ${NC}(${count} approved normals in registry)"
        echo ""
        echo "  1) List registered samples"
        echo "  2) Add a normal sample"
        echo "  3) Add samples from a Sarek run (batch)"
        echo "  4) Remove/exclude a sample"
        echo "  5) Rebuild PON"
        echo "  6) Export samplesheet"
        echo "  q) Quit"
        echo ""
        echo -n "  Select option: "
        read -r choice

        case "$choice" in
            1)
                cmd_list
                ;;
            2)
                interactive_add_single
                ;;
            3)
                interactive_add_batch
                ;;
            4)
                interactive_remove
                ;;
            5)
                interactive_rebuild
                ;;
            6)
                echo -n "  Output filename [pon_samplesheet.csv]: "
                read -r outfile
                outfile="${outfile:-pon_samplesheet.csv}"
                cmd_export "$outfile"
                ;;
            q|Q)
                running=false
                echo ""
                print_info "Bye!"
                ;;
            *)
                print_error "Invalid option: ${choice}"
                ;;
        esac
    done
}

# ─── Interactive: Add single sample ───
interactive_add_single() {
    echo ""
    echo -e "${BOLD}─── Add Normal Sample ───${NC}"
    echo ""

    echo -n "  Sample ID: "
    read -r sample_id
    if [[ -z "$sample_id" ]]; then
        print_error "Sample ID cannot be empty"
        return 0
    fi

    echo -n "  BAM path: "
    read -r bam_path
    if [[ -z "$bam_path" ]]; then
        print_error "BAM path cannot be empty"
        return 0
    fi

    echo -n "  Run origin [manual]: "
    read -r run_origin
    run_origin="${run_origin:-manual}"

    echo -n "  Notes (optional): "
    read -r notes

    cmd_add --sample "$sample_id" --bam "$bam_path" --run "$run_origin" --notes "$notes"
}

# ─── Interactive: Add batch from Sarek output ───
interactive_add_batch() {
    echo ""
    echo -e "${BOLD}─── Add Normals from Sarek Run ───${NC}"
    echo ""

    echo -n "  Sarek results directory: "
    read -r sarek_dir

    if [[ -z "$sarek_dir" ]] || [[ ! -d "$sarek_dir" ]]; then
        print_error "Directory not found: ${sarek_dir}"
        return 0
    fi

    echo -n "  Run ID (for tracking): "
    read -r run_id
    run_id="${run_id:-$(basename "$sarek_dir")}"

    # Search for recalibrated BAMs in standard Sarek output structure
    local recal_dir="${sarek_dir}/preprocessing/recalibrated"
    if [[ ! -d "$recal_dir" ]]; then
        recal_dir="${sarek_dir}/results/preprocessing/recalibrated"
    fi
    if [[ ! -d "$recal_dir" ]]; then
        print_warning "Could not find recalibrated BAMs directory."
        echo -n "  Provide path to BAM directory: "
        read -r recal_dir
    fi

    if [[ ! -d "$recal_dir" ]]; then
        print_error "Directory not found: ${recal_dir}"
        return 0
    fi

    # Find normal samples (matching _N pattern)
    echo ""
    print_info "Scanning for normal samples in: ${recal_dir}"
    echo ""

    local found_normals=()
    local found_bams=()
    local idx=0

    for sample_dir in "${recal_dir}"/*; do
        [[ ! -d "$sample_dir" ]] && continue
        local sample
        sample=$(basename "$sample_dir")

        # Match normal naming patterns: _N, _N01, _N1, etc.
        if [[ "$sample" =~ _N[0-9]*$ ]]; then
            local bam_file
            # Try common Sarek output patterns
            bam_file=$(find "$sample_dir" -name "*.recal.bam" -o -name "*.recal.cram" 2>/dev/null | head -1)

            if [[ -n "$bam_file" ]]; then
                idx=$((idx + 1))
                found_normals+=("$sample")
                found_bams+=("$bam_file")

                local already=""
                if sample_exists "$sample"; then
                    already=" ${YELLOW}(already in registry)${NC}"
                fi
                echo -e "  ${idx}) ${sample}${already}"
                echo "     ${bam_file}"
            fi
        fi
    done

    if [[ ${#found_normals[@]} -eq 0 ]]; then
        print_warning "No normal samples found (looking for *_N* pattern)"
        return 0
    fi

    echo ""
    echo -e "  ${BOLD}Found ${#found_normals[@]} normal samples${NC}"
    echo ""
    echo "  Options:"
    echo "    a) Add ALL samples listed above"
    echo "    s) Select specific samples (enter numbers separated by spaces)"
    echo "    c) Cancel"
    echo ""
    echo -n "  Choice: "
    read -r batch_choice

    local selected_indices=()

    case "$batch_choice" in
        a|A)
            for i in $(seq 0 $((${#found_normals[@]} - 1))); do
                selected_indices+=("$i")
            done
            ;;
        s|S)
            echo -n "  Enter sample numbers (space-separated, e.g. '1 3 5'): "
            read -r numbers
            for n in $numbers; do
                local idx_zero=$((n - 1))
                if [[ $idx_zero -ge 0 ]] && [[ $idx_zero -lt ${#found_normals[@]} ]]; then
                    selected_indices+=("$idx_zero")
                else
                    print_warning "Skipping invalid number: ${n}"
                fi
            done
            ;;
        c|C)
            print_info "Cancelled"
            return 0
            ;;
        *)
            print_error "Invalid choice"
            return 0
            ;;
    esac

    # Add selected samples
    local added=0
    for i in "${selected_indices[@]}"; do
        local sid="${found_normals[$i]}"
        local bam="${found_bams[$i]}"

        if sample_exists "$sid"; then
            print_warning "Skipping ${sid} (already in registry)"
            continue
        fi

        cmd_add --sample "$sid" --bam "$bam" --run "$run_id"
        added=$((added + 1))
    done

    echo ""
    print_success "Added ${added} samples from ${run_id}"
}

# ─── Interactive: Remove sample ───
interactive_remove() {
    echo ""
    echo -e "${BOLD}─── Remove/Exclude Sample ───${NC}"
    echo ""

    # Show current approved samples
    local samples=()
    local idx=0
    while IFS=$'\t' read -r sid bam date run status notes; do
        if [[ "$status" == "approved" ]]; then
            idx=$((idx + 1))
            samples+=("$sid")
            echo "  ${idx}) ${sid} (added: ${date}, run: ${run})"
        fi
    done < <(tail -n +2 "$REGISTRY_FILE")

    if [[ ${#samples[@]} -eq 0 ]]; then
        print_info "No approved samples to remove."
        return 0
    fi

    echo ""
    echo -n "  Enter number to exclude (or 'c' to cancel): "
    read -r choice

    if [[ "$choice" == "c" ]] || [[ "$choice" == "C" ]]; then
        return 0
    fi

    local idx_zero=$((choice - 1))
    if [[ $idx_zero -ge 0 ]] && [[ $idx_zero -lt ${#samples[@]} ]]; then
        local sid="${samples[$idx_zero]}"
        echo -n "  Exclude ${sid}? [y/N] "
        read -r confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
            cmd_remove --sample "$sid"
        fi
    else
        print_error "Invalid selection"
    fi
}

# ─── Interactive: Rebuild PON ───
interactive_rebuild() {
    echo ""
    echo -e "${BOLD}─── Rebuild Panel of Normals ───${NC}"
    echo ""

    local count
    count=$(count_approved)

    print_info "Approved normals: ${count}"

    if [[ "$count" -lt 2 ]]; then
        print_error "Need at least 2 normals to build a PON"
        return 0
    fi

    echo ""
    echo "  1) Run pipeline now"
    echo "  2) Dry run (show command only)"
    echo "  3) Export samplesheet only"
    echo "  c) Cancel"
    echo ""
    echo -n "  Choice: "
    read -r choice

    case "$choice" in
        1)
            echo -n "  Params file (leave empty for defaults): "
            read -r params_file
            if [[ -n "$params_file" ]]; then
                cmd_rebuild --params-file "$params_file"
            else
                cmd_rebuild
            fi
            ;;
        2)
            cmd_rebuild --dry-run
            ;;
        3)
            cmd_export "pon_samplesheet.csv"
            ;;
        c|C)
            return 0
            ;;
    esac
}

# ============================================================
# MAIN — Route to command or interactive mode
# ============================================================

main() {
    case "${1:-}" in
        add)      shift; cmd_add "$@" ;;
        list)     cmd_list ;;
        remove)   shift; cmd_remove "$@" ;;
        export)   shift; cmd_export "${1:-pon_samplesheet.csv}" ;;
        rebuild)  shift; cmd_rebuild "$@" ;;
        --help|-h)
            echo "Usage: pon_manager.sh [command] [options]"
            echo ""
            echo "Commands:"
            echo "  (none)     Interactive menu"
            echo "  add        Add a normal sample to registry"
            echo "  list       List registered samples"
            echo "  remove     Exclude a sample from registry"
            echo "  export     Generate samplesheet CSV"
            echo "  rebuild    Export samplesheet and run PON pipeline"
            echo ""
            echo "Options for 'add':"
            echo "  --sample ID    Sample identifier"
            echo "  --bam PATH     Path to recalibrated BAM file"
            echo "  --run ID       Run/batch origin (optional)"
            echo "  --notes TEXT   Free-text notes (optional)"
            echo ""
            echo "Options for 'rebuild':"
            echo "  --dry-run          Show command without executing"
            echo "  --params-file F    Nextflow params file for the PON pipeline"
            echo ""
            echo "Environment variables:"
            echo "  PON_REGISTRY     Path to registry TSV (default: pon_registry.tsv)"
            echo "  PON_PIPELINE     Nextflow pipeline to run (default: FlorPio/gatk-cnv-pon)"
            echo "  PON_OUTPUT_DIR   Output directory (default: pon_results)"
            echo "  NEXTFLOW_PROFILE Profile for Nextflow (default: docker)"
            ;;
        "")
            interactive_menu
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Run './pon_manager.sh --help' for usage"
            return 1
            ;;
    esac
}

main "$@"
