#!/usr/bin/env bash

set -u

ppa_log=$1
baremetal_dir=$2
rtthread_dir=$3
shift 3
profiles=("$@")

mkdir -p "$(dirname "$ppa_log")"
tmp_log=$(mktemp "${ppa_log}.tmp.XXXXXX")
cleanup() {
    rm -f "$tmp_log"
}
trap cleanup EXIT

# Keep the original bare-metal report and replace only the RT-Thread section.
if [[ -f "$ppa_log" ]]; then
    awk '/^\[RTTHREAD COREMARK\]/{skip=1} !skip{print}' "$ppa_log" > "$tmp_log"
fi

echo "[RTTHREAD COREMARK] COMPARED_TO=baremetal FPU=0 ITERATIONS=1" >> "$tmp_log"

passed=0
failed=0
skipped=0

field() {
    local key=$1
    local file=$2
    sed -n "s/.*[[:space:]]${key}=\([^[:space:]]*\).*/\1/p" "$file" | tail -1
}

number_or_empty() {
    [[ "$1" =~ ^[+-]?[0-9]+([.][0-9]+)?$ ]]
}

delta_int() {
    awk -v r="$1" -v b="$2" 'BEGIN {printf "%+.0f", r-b}'
}

delta_float() {
    awk -v r="$1" -v b="$2" 'BEGIN {printf "%+.6f", r-b}'
}

for profile in "${profiles[@]}"; do
    rt_status="${rtthread_dir}/${profile}.status"
    bare_status="${baremetal_dir}/${profile}.status"

    if [[ ! -f "$rt_status" ]]; then
        echo "[RTTHREAD COREMARK] [${profile}] [FAIL] missing status" >> "$tmp_log"
        failed=$((failed + 1))
        continue
    fi

    rt_line=$(cat "$rt_status")
    result=FAIL
    if grep -q '\[PASS\]' <<<"$rt_line"; then
        result=PASS
        passed=$((passed + 1))
    elif grep -q '\[SKIP\]' <<<"$rt_line"; then
        result=SKIP
        skipped=$((skipped + 1))
    else
        failed=$((failed + 1))
    fi

    rt_cycles=$(field cycles "$rt_status")
    rt_insts=$(field insts "$rt_status")
    rt_ipc=$(field ipc "$rt_status")
    rt_score=$(field score "$rt_status")
    bare_cycles=$(field cycles "$bare_status")
    bare_ipc=$(field ipc "$bare_status")
    bare_score=$(field score "$bare_status")

    suffix=""
    if [[ -f "$bare_status" ]] && number_or_empty "$rt_cycles" && number_or_empty "$bare_cycles"; then
        suffix+=" delta_cycles=$(delta_int "$rt_cycles" "$bare_cycles")"
    else
        suffix+=" delta_cycles=N/A"
    fi
    if [[ -f "$bare_status" ]] && number_or_empty "$rt_ipc" && number_or_empty "$bare_ipc"; then
        suffix+=" delta_ipc=$(delta_float "$rt_ipc" "$bare_ipc")"
    else
        suffix+=" delta_ipc=N/A"
    fi
    if [[ -f "$bare_status" ]] && number_or_empty "$rt_score" && number_or_empty "$bare_score"; then
        suffix+=" delta_score=$(delta_float "$rt_score" "$bare_score")"
    else
        suffix+=" delta_score=N/A"
    fi

    echo "[RTTHREAD COREMARK] [${profile}] [${result}] cycles=${rt_cycles:-N/A} insts=${rt_insts:-N/A} ipc=${rt_ipc:-N/A} score=${rt_score:-N/A}${suffix}" >> "$tmp_log"
done

overall=PASS
if [[ "$failed" -ne 0 ]]; then
    overall=FAIL
fi
echo "[RTTHREAD COREMARK] CORRECTNESS=${overall} passed=${passed} skipped=${skipped} total=${#profiles[@]}" >> "$tmp_log"
mv "$tmp_log" "$ppa_log"
trap - EXIT

echo "[RTTHREAD COREMARK] Report: $ppa_log"
exit "$failed"
