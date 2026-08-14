#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: verif/tools/sweep_coremark_swopt.sh [options]

Build and run distinct CoreMark compiler configurations in parallel per round.
Each case is simulated once because RTL simulation is deterministic.
The default matrix spans every meaningful combination of the declared
COREMARK_SWOPT groups while keeping 8-byte alignment fixed.
The script reuses a prebuilt Verilator model and injects each case's ITCM/DTCM
images through sim_compare. Spike comparison and Verilator compilation are not
run.

Options:
  --parallel N     Cases to build and inject in parallel per round
                   (default: 20, maximum: 40)
  --extra-cases F  Tab-separated case name and additional CFLAGS. Scan these
                   cases on the current default SWOPT baseline instead of the
                   full declared-group matrix.
  --prefix-cflags F  CFLAGS prepended to every --extra-cases entry. This is
                     useful for screening single deltas on a measured stack.
  --exclude-cases L  Comma-separated --extra-cases names to omit.
  --rounds N       Number of rounds to run (default: all remaining cases)
  --resume         Continue an interrupted sweep in --out-dir from its next
                   unrecorded case
  --obj-dir DIR    Prebuilt ydrasil_core_tb directory
                   (default: build/ydrasil_core_tb-coremark)
  --out-dir DIR    Empty output directory (default: build/coremark-swopt-sweep/<UTC>-<git>)
  --timeout N      C++/SV timeout in cycles (default: 2000000)
  --help           Show this help
EOF
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
checker="$repo_root/verif/tools/check_coremark_swopt.py"
rounds=0
parallel=20
timeout=2000000
obj_dir="$repo_root/build/ydrasil_core_tb-coremark"
out_dir=
resume=0
extra_cases_file=
prefix_cflags=
exclude_cases=

while (($#)); do
    case "$1" in
        --rounds)
            [[ $# -ge 2 && $2 =~ ^[1-9][0-9]*$ ]] || {
                echo "--rounds requires a positive integer" >&2
                exit 2
            }
            rounds=$2
            shift 2
            ;;
        --parallel)
            [[ $# -ge 2 && $2 =~ ^[1-9][0-9]*$ && $2 -le 40 ]] || {
                echo "--parallel requires an integer from 1 to 40" >&2
                exit 2
            }
            parallel=$2
            shift 2
            ;;
        --extra-cases)
            [[ $# -ge 2 ]] || { echo "--extra-cases requires a file" >&2; exit 2; }
            extra_cases_file=$2
            shift 2
            ;;
        --prefix-cflags)
            [[ $# -ge 2 ]] || { echo "--prefix-cflags requires CFLAGS" >&2; exit 2; }
            prefix_cflags=$2
            shift 2
            ;;
        --exclude-cases)
            [[ $# -ge 2 ]] || { echo "--exclude-cases requires case names" >&2; exit 2; }
            exclude_cases=$2
            shift 2
            ;;
        --resume)
            resume=1
            shift
            ;;
        --obj-dir)
            [[ $# -ge 2 ]] || { echo "--obj-dir requires a value" >&2; exit 2; }
            obj_dir=$2
            shift 2
            ;;
        --out-dir)
            [[ $# -ge 2 ]] || { echo "--out-dir requires a value" >&2; exit 2; }
            out_dir=$2
            shift 2
            ;;
        --timeout)
            [[ $# -ge 2 && $2 =~ ^[1-9][0-9]*$ ]] || {
                echo "--timeout requires a positive integer" >&2
                exit 2
            }
            timeout=$2
            shift 2
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
if [[ ! -f $checker ]]; then
    echo "CoreMark sweep checker not found: $checker" >&2
    exit 2
fi
if [[ $obj_dir != /* ]]; then
    obj_dir="$repo_root/$obj_dir"
fi
if [[ -n $extra_cases_file && $extra_cases_file != /* ]]; then
    extra_cases_file="$repo_root/$extra_cases_file"
fi
if [[ ! -x $obj_dir/ydrasil_core_tb ]]; then
    echo "prebuilt Verilator model not found: $obj_dir/ydrasil_core_tb" >&2
    echo "build it once with: make coremark_sim COREMARK_SIM_COMPARE=none" >&2
    exit 2
fi

git_head=$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
if [[ -z $out_dir ]]; then
    out_dir="$repo_root/build/coremark-swopt-sweep/$(date -u +%Y%m%dT%H%M%SZ)-$git_head"
elif [[ $out_dir != /* ]]; then
    out_dir="$repo_root/$out_dir"
fi
if [[ $out_dir == *' '* ]]; then
    echo "output directory cannot contain spaces" >&2
    exit 2
fi
if [[ -e $out_dir && $resume -eq 0 ]]; then
    echo "refusing to reuse output directory: $out_dir" >&2
    exit 2
fi
if [[ $resume -eq 1 && ! -d $out_dir ]]; then
    echo "--resume requires an existing --out-dir" >&2
    exit 2
fi

# The binary groups form all subsets;
# tuning and branch-cost groups are categorical because combining alternatives
# is not a meaningful compiler configuration.
base_groups=(
    inline register loop_shape control_shape tree_shape unroll_all
    no_strict_alias lto
)
tune_groups=(none mtune_s7 mtune_ydrasil)
branch_groups=(none branch_cost_1 branch_cost_2 branch_cost_3 branch_cost_5)
case_ids=()
declare -A case_groups
declare -A case_extras
declare -A excluded_case_ids
if [[ -n $exclude_cases ]]; then
    IFS=',' read -r -a excluded_names <<< "$exclude_cases"
    for case_id in "${excluded_names[@]}"; do
        [[ $case_id =~ ^[A-Za-z0-9_.-]+$ ]] || {
            echo "invalid excluded case name: $case_id" >&2
            exit 2
        }
        excluded_case_ids[$case_id]=1
    done
fi
if [[ -n $extra_cases_file ]]; then
    [[ -f $extra_cases_file ]] || { echo "extra case file not found: $extra_cases_file" >&2; exit 2; }
    baseline_groups='inline register loop_shape control_shape tree_shape unroll_all branch_cost_1'
    while IFS=$'\t' read -r case_id extra || [[ -n ${case_id:-} ]]; do
        [[ -z ${case_id:-} || $case_id == \#* ]] && continue
        [[ -v "excluded_case_ids[$case_id]" ]] && continue
        [[ $case_id =~ ^[A-Za-z0-9_.-]+$ ]] || {
            echo "invalid extra case name: $case_id" >&2
            exit 2
        }
        [[ ! -v "case_groups[$case_id]" ]] || {
            echo "duplicate extra case name: $case_id" >&2
            exit 2
        }
        case_ids+=("$case_id")
        case_groups[$case_id]=$baseline_groups
        case_extras[$case_id]="$prefix_cflags${prefix_cflags:+${extra:+ }}${extra:-}"
    done < "$extra_cases_file"
    ((${#case_ids[@]})) || { echo "no extra cases found: $extra_cases_file" >&2; exit 2; }
else
    for ((mask = 0; mask < (1 << ${#base_groups[@]}); mask++)); do
        selected=()
        for index in "${!base_groups[@]}"; do
            if ((mask & (1 << index))); then
                selected+=("${base_groups[$index]}")
            fi
        done
        for tune in "${tune_groups[@]}"; do
            for branch in "${branch_groups[@]}"; do
                case_id=$(printf 'g%03d-t%s-b%s' "$mask" "${tune#mtune_}" "${branch#branch_cost_}")
                group_set="${selected[*]}"
                [[ $tune == none ]] || group_set+=" $tune"
                [[ $branch == none ]] || group_set+=" $branch"
                case_ids+=("$case_id")
                case_groups[$case_id]=$group_set
                case_extras[$case_id]=''
            done
        done
    done
fi

summary="$out_dir/summary.tsv"
ranked="$out_dir/ranked.tsv"
case_start=0
round_index=1
if ((resume)); then
    [[ -f $summary ]] || { echo "missing resume summary: $summary" >&2; exit 2; }
    recorded_cases=$(awk 'NR > 1 { count++ } END { print count + 0 }' "$summary")
    if ((recorded_cases > ${#case_ids[@]})); then
        echo "resume summary exceeds the sweep matrix" >&2
        exit 2
    fi
    case_start=$recorded_cases
    last_round=$(awk -F '\t' 'NR > 1 { value = $1 } END { print value }' "$summary")
    if [[ $last_round =~ ^round-([0-9]+)$ ]]; then
        round_index=$((10#${BASH_REMATCH[1]} + 1))
    fi
    echo "[COREMARK SWOPT] resuming after $recorded_cases recorded cases"
else
    mkdir -p "$out_dir"/{images,runs,logs,verilator-log}
    printf 'round\tcase\tstage\tstatus\tcycles\tinsts\tipc\titcm_bytes\tgroups\textra_cflags\n' > "$summary"
    printf 'case\tgroups\n' > "$out_dir/cases.tsv"
    for case_id in "${case_ids[@]}"; do
        printf '%s\t%s\n' "$case_id" "${case_groups[$case_id]}" >> "$out_dir/cases.tsv"
    done
printf '%s\n' "$git_head" > "$out_dir/git_head.txt"
    if [[ -n $extra_cases_file ]]; then
        cp "$extra_cases_file" "$out_dir/extra_cases.tsv"
    fi
fi

remaining_cases=$(( ${#case_ids[@]} - case_start ))
max_rounds=$(( (remaining_cases + parallel - 1) / parallel ))
if ((rounds == 0)); then
    rounds=$max_rounds
fi
if ((rounds > max_rounds)); then
    echo "--rounds=$rounds exceeds the $max_rounds available remaining rounds" >&2
    exit 2
fi

build_case() {
    local round=$1
    local case_id=$2
    local image_dir="$out_dir/images/$round/$case_id"
    local log="$out_dir/logs/$round/$case_id.build.log"
    local status="$out_dir/logs/$round/$case_id.build.status"
    local group_set=${case_groups[$case_id]}
    local extra=${case_extras[$case_id]}

    mkdir -p "$(dirname "$log")"
    if make --no-print-directory coremark \
        COREMARK_OUT="$image_dir" \
        COREMARK_SWOPT_GROUPS="$group_set" \
        COREMARK_SWOPT_CFLAGS_branch_cost_1="-mbranch-cost=1 $extra" \
        >"$log" 2>&1; then
        printf 'PASS\n' > "$status"
    else
        printf 'FAIL\n' > "$status"
    fi
}

run_case() {
    local round=$1
    local case_id=$2
    local image_dir="$out_dir/images/$round/$case_id"
    local run_dir="$out_dir/runs/$round/$case_id"
    local log="$out_dir/logs/$round/$case_id.run.log"
    local status="$out_dir/logs/$round/$case_id.run.status"

    mkdir -p "$run_dir" "$out_dir/verilator-log/$round/$case_id"
    if [[ ! -s $image_dir/coremark.itcm || ! -s $image_dir/coremark.dtcm ]]; then
        printf 'SKIP\n' > "$status"
        return
    fi
    if make --no-print-directory sim_compare \
        SIM_COMPARE=none \
        OBJ_DIR="$obj_dir" \
        LOG_DIR="$out_dir/verilator-log/$round/$case_id" \
        WAVE_DIR="$out_dir/verilator-log/$round/$case_id/wave" \
        COMPARE_NAME="coremark-swopt/$round/$case_id" \
        COMPARE_ELF="$image_dir/coremark.elf" \
        COMPARE_ITCM="$image_dir/coremark.itcm" \
        COMPARE_DTCM="$image_dir/coremark.dtcm" \
        COMPARE_OUT_DIR="$run_dir/compare" \
        COMPARE_HW_OUT_DIR="$run_dir" \
        COMPARE_HW_LOG="$run_dir/hw.log" \
        COMPARE_HW_CSV="$run_dir/hw.csv" \
        COMPARE_SPIKE_LOG="$run_dir/spike-unused.log" \
        COMPARE_SPIKE_CSV="$run_dir/spike-unused.csv" \
        COMPARE_SIM_EXTRA_DEFINES="+no_finish_on_tohost +cpp_timeout=$timeout +sv_timeout=$timeout" \
        >"$log" 2>&1; then
        printf 'PASS\n' > "$status"
    else
        printf 'FAIL\n' > "$status"
    fi
}

record_case() {
    local round=$1
    local case_id=$2
    local image_dir="$out_dir/images/$round/$case_id"
    local run_dir="$out_dir/runs/$round/$case_id"
    local build_status run_status status metric cycles insts ipc itcm_bytes
    build_status=$(<"$out_dir/logs/$round/$case_id.build.status")
    run_status=$(<"$out_dir/logs/$round/$case_id.run.status")
    status=FAIL
    if [[ $build_status == PASS && $run_status == PASS ]] && \
       grep -q 'Correct operation validated' "$run_dir/hw.log" && \
       grep -q 'COREMARK DONE' "$run_dir/hw.log"; then
        status=PASS
    fi
    metric=$(sed -n 's/^PERF_METRIC: CYCLES= *\([0-9]*\).*INSTS= *\([0-9]*\).*IPC= *\([0-9.]*\).*/\1\t\2\t\3/p' "$run_dir/hw.log" 2>/dev/null | tail -1)
    if [[ -n $metric ]]; then
        IFS=$'\t' read -r cycles insts ipc <<< "$metric"
    else
        cycles=N/A
        insts=N/A
        ipc=N/A
    fi
    itcm_bytes=$(wc -c < "$image_dir/coremark_itcm.bin" 2>/dev/null || printf N/A)
    printf '%s\t%s\tbuild+inject\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$round" "$case_id" "$status" "$cycles" "$insts" "$ipc" "$itcm_bytes" \
        "${case_groups[$case_id]}" "${case_extras[$case_id]}" >> "$summary"
}

for ((rounds_run = 0; rounds_run < rounds; rounds_run++, round_index++)); do
    round=$(printf 'round-%03d' "$round_index")
    round_cases=( "${case_ids[@]:case_start:parallel}" )
    case_start=$((case_start + ${#round_cases[@]}))
    echo "[COREMARK SWOPT] $round: building ${#round_cases[@]} cases"
    build_pids=()
    for case_id in "${round_cases[@]}"; do
        build_case "$round" "$case_id" &
        build_pids+=("$!")
    done
    for pid in "${build_pids[@]}"; do wait "$pid"; done

    echo "[COREMARK SWOPT] $round: injecting ${#round_cases[@]} images without Spike"
    run_pids=()
    for case_id in "${round_cases[@]}"; do
        run_case "$round" "$case_id" &
        run_pids+=("$!")
    done
    for pid in "${run_pids[@]}"; do wait "$pid"; done
    for case_id in "${round_cases[@]}"; do record_case "$round" "$case_id"; done
    if ! "$checker" "$out_dir" --quiet; then
        echo "[COREMARK SWOPT] validation warnings: $out_dir/validation.tsv" >&2
    fi
done

"$checker" "$out_dir"

echo "[COREMARK SWOPT] Samples: $summary"
echo "[COREMARK SWOPT] Ranked: $ranked"
echo "[COREMARK SWOPT] Cases: $out_dir/cases.tsv"
column -ts $'\t' "$ranked"
