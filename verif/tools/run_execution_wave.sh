#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: verif/tools/run_execution_wave.sh [options]

Build the current RTL in an isolated directory, run the compact CoreMark
execution-wave probe, and analyze 15 representative high-bubble windows.

Options:
  --out-dir DIR       Run directory (default: build/execution-wave/<UTC>-<git>)
  --samples N         Number of non-overlapping windows (default: 15)
  --window N          Analysis window width in cycles (default: 32)
  --skip-software     Reuse build/app/coremark images instead of rebuilding
  --help              Show this help
EOF
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
sample_count=15
window_cycles=32
out_dir=
skip_software=0

while (($#)); do
    case "$1" in
        --out-dir)
            [[ $# -ge 2 ]] || { echo "--out-dir requires a value" >&2; exit 2; }
            out_dir=$2
            shift 2
            ;;
        --samples)
            [[ $# -ge 2 && $2 =~ ^[1-9][0-9]*$ ]] || {
                echo "--samples requires a positive integer" >&2; exit 2;
            }
            sample_count=$2
            shift 2
            ;;
        --window)
            [[ $# -ge 2 && $2 =~ ^[1-9][0-9]*$ ]] || {
                echo "--window requires a positive integer" >&2; exit 2;
            }
            window_cycles=$2
            shift 2
            ;;
        --skip-software)
            skip_software=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

cd "$repo_root"
git_head=$(git rev-parse HEAD 2>/dev/null || echo unknown)
git_short=${git_head:0:12}
if [[ -z $out_dir ]]; then
    out_dir="$repo_root/build/execution-wave/$(date -u +%Y%m%dT%H%M%SZ)-$git_short"
elif [[ $out_dir != /* ]]; then
    out_dir="$repo_root/$out_dir"
fi

if [[ $out_dir == *' '* ]]; then
    echo "run directory cannot contain spaces because the repository Makefiles pass image paths as plusargs" >&2
    exit 2
fi

if [[ -e $out_dir ]]; then
    echo "refusing to reuse run directory: $out_dir" >&2
    exit 2
fi

mkdir -p "$out_dir"/{analysis,image,log,obj,wave,provenance}
image_dir="$out_dir/image"
obj_dir="$out_dir/obj"
log_dir="$out_dir/log"
wave_dir="$out_dir/wave"
provenance_dir="$out_dir/provenance"
probe_csv="$out_dir/execution_wave.csv"
metadata_json="$out_dir/execution_wave.metadata.json"
flist="$obj_dir/flist/ydrasil_core_verilator.f"
tb_source="$repo_root/hw/ip/ydrasil_core/dv/ydrasil_core_tb.sv"
runner_source="$repo_root/verif/tools/run_execution_wave.sh"
analyzer_source="$repo_root/verif/tools/analyze_execution_wave.py"
itcm_width=${EXECUTION_WAVE_ITCM_WIDTH:-15}

exec > >(tee "$out_dir/run.log") 2>&1

# Run the captured analyzer bytes so a concurrent worktree edit cannot change
# the report after the RTL/source fingerprints have been recorded.
cp "$runner_source" "$provenance_dir/run_execution_wave.sh"
cp "$analyzer_source" "$provenance_dir/analyze_execution_wave.py"
cp "$tb_source" "$out_dir/ydrasil_core_tb.sv"
runner_sha256=$(sha256sum "$provenance_dir/run_execution_wave.sh" | awk '{print $1}')
analyzer_sha256=$(sha256sum "$provenance_dir/analyze_execution_wave.py" | awk '{print $1}')

printf '%s\n' "$git_head" > "$provenance_dir/git_head.txt"
git status --porcelain=v1 --untracked-files=all > "$provenance_dir/git_status.txt"
git diff --binary HEAD > "$provenance_dir/worktree.patch"
git submodule status --recursive > "$provenance_dir/submodules.txt"
verilator --version > "$provenance_dir/verilator_version.txt"
bender --version > "$provenance_dir/bender_version.txt"

if ((skip_software)); then
    source_image_dir="$repo_root/build/app/coremark"
    for image in coremark.elf coremark.itcm coremark.dtcm; do
        [[ -s $source_image_dir/$image ]] || {
            echo "missing reusable CoreMark image: $source_image_dir/$image" >&2
            exit 2
        }
        cp "$source_image_dir/$image" "$image_dir/$image"
    done
else
    make coremark COREMARK_OUT="$image_dir"
fi

riscv_nm="$repo_root/tools/riscv/bin/riscv64-unknown-elf-nm"
[[ -x $riscv_nm ]] || { echo "RISC-V nm is missing: $riscv_nm" >&2; exit 2; }
measure_start_pc=$(
    "$riscv_nm" -n "$image_dir/coremark.elf" |
        awk '$3 == "start_time" {print $1; exit}'
)
measure_stop_pc=$(
    "$riscv_nm" -n "$image_dir/coremark.elf" |
        awk '$3 == "stop_time" {print $1; exit}'
)
[[ $measure_start_pc =~ ^[0-9a-fA-F]+$ &&
   $measure_stop_pc =~ ^[0-9a-fA-F]+$ ]] || {
    echo "unable to resolve CoreMark start_time/stop_time PCs" >&2
    exit 2
}

make comp \
    VERILATOR_TRACE=0 VERILATOR_COVERAGE=0 \
    ITCM_ADDR_WIDTH_OVERRIDE="$itcm_width" \
    OBJ_DIR="$obj_dir" LOG_DIR="$log_dir" WAVE_DIR="$wave_dir"

[[ -s $obj_dir/ydrasil_core_tb ]] || { echo "simulation model missing" >&2; exit 2; }
[[ -s $flist ]] || { echo "compiled source list missing" >&2; exit 2; }
grep -Fq "$obj_dir/rtl_override/ydrasil_pkg.sv" "$flist" || {
    echo "compiled flist does not use the isolated package override" >&2
    exit 2
}
grep -Fq "ITCM_ADDR_WIDTH = $itcm_width;" \
    "$obj_dir/rtl_override/ydrasil_pkg.sv" || {
    echo "ITCM width override was not applied" >&2
    exit 2
}

write_source_manifest() {
    local output=$1 source normalized digest
    : > "$output"
    while IFS= read -r source; do
        [[ $source == /* && -f $source ]] || continue
        if [[ $source == "$obj_dir/rtl_override/"* ]]; then
            normalized="@rtl_override/${source##*/}"
        elif [[ $source == "$repo_root/"* ]]; then
            normalized=${source#"$repo_root/"}
        else
            normalized=$source
        fi
        digest=$(sha256sum "$source" | awk '{print $1}')
        printf '%s  %s\n' "$digest" "$normalized" >> "$output"
    done < "$flist"
    sort -o "$output" "$output"
}

write_source_manifest "$provenance_dir/rtl_sources.before.tsv"
rtl_sha256=$(sha256sum "$provenance_dir/rtl_sources.before.tsv" | awk '{print $1}')
probe_sha256=$(sha256sum "$out_dir/ydrasil_core_tb.sv" | awk '{print $1}')

make sim \
    VERILATOR_TRACE=0 VERILATOR_COVERAGE=0 LOG_OUTPUT=1 \
    ITCM_ADDR_WIDTH_OVERRIDE="$itcm_width" \
    OBJ_DIR="$obj_dir" LOG_DIR="$log_dir" WAVE_DIR="$wave_dir" \
    ITCM_FILE="$image_dir/coremark.itcm" \
    DTCM_FILE="$image_dir/coremark.dtcm" \
    SIM_EXTRA_DEFINES="+no_finish_on_tohost +cpp_timeout=10000000 +sv_timeout=10000000 +execution_wave=$probe_csv +execution_wave_measure_start_pc=$measure_start_pc +execution_wave_measure_stop_pc=$measure_stop_pc"

sim_log="$log_dir/ydrasil_core_tb.ver.sim.log"
[[ -s $sim_log && -s $probe_csv ]] || {
    echo "simulation did not produce both its log and probe CSV" >&2
    exit 2
}
for marker in \
    "Trace is disabled." \
    "Loading memory from $image_dir/coremark.itcm" \
    "Loading memory from $image_dir/coremark.dtcm" \
    "Correct operation validated." \
    "COREMARK DONE" \
    "PERF_METRIC:" \
    "Simulation finished"; do
    grep -Fq "$marker" "$sim_log" || {
        echo "simulation log is missing marker: $marker" >&2
        exit 2
    }
done
if grep -Fq "Errors detected" "$sim_log"; then
    echo "simulation reported errors" >&2
    exit 2
fi

write_source_manifest "$provenance_dir/rtl_sources.after.tsv"
cmp "$provenance_dir/rtl_sources.before.tsv" \
    "$provenance_dir/rtl_sources.after.tsv" || {
    echo "compiled source changed while the probe was running" >&2
    exit 2
}

csv_sha256=$(sha256sum "$probe_csv" | awk '{print $1}')
model_sha256=$(sha256sum "$obj_dir/ydrasil_core_tb" | awk '{print $1}')
elf_sha256=$(sha256sum "$image_dir/coremark.elf" | awk '{print $1}')
itcm_sha256=$(sha256sum "$image_dir/coremark.itcm" | awk '{print $1}')
dtcm_sha256=$(sha256sum "$image_dir/coremark.dtcm" | awk '{print $1}')
generated_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
    --arg schema "ydrasil.execution_wave.v2" \
    --arg design "Ydrasil" \
    --arg test_name "coremark" \
    --arg simulator "$(verilator --version)" \
    --arg probe_instance "ydrasil_core_tb" \
    --arg generated_utc "$generated_utc" \
    --arg git_head "$git_head" \
    --arg rtl_sha256 "$rtl_sha256" \
    --arg probe_sha256 "$probe_sha256" \
    --arg probe_file "ydrasil_core_tb.sv" \
    --arg runner_sha256 "$runner_sha256" \
    --arg analyzer_sha256 "$analyzer_sha256" \
    --arg csv_sha256 "$csv_sha256" \
    --arg model_sha256 "$model_sha256" \
    --arg elf_sha256 "$elf_sha256" \
    --arg itcm_sha256 "$itcm_sha256" \
    --arg dtcm_sha256 "$dtcm_sha256" \
    --arg benchmark_start_pc "0x$measure_start_pc" \
    --arg benchmark_stop_pc "0x$measure_stop_pc" \
    --arg source_manifest "provenance/rtl_sources.before.tsv" \
    --arg git_status "$(cat "$provenance_dir/git_status.txt")" \
    --argjson issue_width 2 \
    --argjson rob_depth 12 \
    '{schema:$schema, design:$design, test_name:$test_name,
      simulator:$simulator, probe_instance:$probe_instance,
      generated_utc:$generated_utc, git_head:$git_head,
      git_status:$git_status, rtl_sha256:$rtl_sha256,
      probe_sha256:$probe_sha256, csv_sha256:$csv_sha256,
      probe_file:$probe_file,
      runner_sha256:$runner_sha256, analyzer_sha256:$analyzer_sha256,
      model_sha256:$model_sha256, elf_sha256:$elf_sha256,
      itcm_sha256:$itcm_sha256, dtcm_sha256:$dtcm_sha256,
      benchmark_start_pc:$benchmark_start_pc,
      benchmark_stop_pc:$benchmark_stop_pc,
      source_manifest:$source_manifest, issue_width:$issue_width,
      rob_depth:$rob_depth}' > "$metadata_json"

python3 "$provenance_dir/analyze_execution_wave.py" \
    "$probe_csv" \
    --metadata "$metadata_json" \
    --expect-rtl-sha256 "$rtl_sha256" \
    --expect-probe-sha256 "$probe_sha256" \
    --output-dir "$out_dir/analysis" \
    --samples "$sample_count" \
    --window-cycles "$window_cycles"

echo "Execution-wave analysis: $out_dir/analysis/execution_bubble_report.md"
echo "Compact waveform: $out_dir/analysis/execution_bubble_samples.vcd"
