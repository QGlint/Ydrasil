#!/usr/bin/env bash
set -euo pipefail

root=${1:-build/sim/hw}
out_dir=${2:-build/PPA}
csv="$out_dir/perf_stats.csv"
summary="$out_dir/perf_stats_summary.log"
mkdir -p "$out_dir"

field() {
    local line=$1 key=$2
    sed -n "s/.*${key}= *\([0-9.]*\).*/\1/p" <<<"$line"
}

header="program,cycles,insts,ipc,scoreboard,lsu_struct,producer_full,multi,flush,no_if_valid,other,raw_only,waw_only,raw_waw,load_use,alu_use,pending_tail,pf_sb,pf_lsu,pf_lsu_sb,occ0,occ1,occ2,both_wait,wait_ready,both_ready,hot_lookup,hot_hit"
echo "$header" > "$csv"

mapfile -t logs < <(find "$root" -type f -name hw.log \( \
    -path '*/coe_loop5/hw.log' -o -path '*/coremark/hw.log' -o \
    -path '*/sort/*/hw.log' -o -path '*/boundary/*/hw.log' -o \
    -path '*/rv32ui/*/hw.log' -o -path '*/rv32um/*/hw.log' -o \
    -path '*/rv32uz*/*/hw.log' -o -path '*/rv32mi/*/hw.log' \) | sort)

for log in "${logs[@]}"; do
    grep -q '^PERF_CYCLE_ACCOUNT:' "$log" || continue
    program=${log#"$root"/}
    program=${program%/hw.log}
    metric=$(grep '^PERF_METRIC:' "$log" | tail -1)
    stall=$(grep '^PERF_STALL:' "$log" | tail -1)
    sb=$(grep '^PERF_SCOREBOARD_DETAIL:' "$log" | tail -1)
    load=$(grep '^PERF_LOAD_DETAIL:' "$log" | tail -1)
    acct=$(grep '^PERF_CYCLE_ACCOUNT:' "$log" | tail -1)
    hazard=$(grep '^PERF_HAZARD_ACCOUNT:' "$log" | tail -1)
    cause=$(grep '^PERF_CAUSE_HIST:' "$log" | tail -1 || true)
    producer=$(grep '^PERF_PRODUCER_STATE:' "$log" | tail -1 || true)
    hot=$(grep '^PERF_LSU_HOT:' "$log" | tail -1)
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$program" "$(field "$metric" CYCLES)" "$(field "$metric" INSTS)" \
        "$(field "$metric" IPC)" "$(field "$stall" SCOREBOARD)" \
        "$(field "$stall" LSU_STRUCT)" "$(field "$acct" PRODUCER_FULL)" \
        "$(field "$acct" MULTI)" "$(field "$acct" FLUSH)" \
        "$(field "$acct" NO_IF_VALID)" "$(field "$acct" OTHER)" \
        "$(field "$hazard" RAW_ONLY)" "$(field "$hazard" WAW_ONLY)" \
        "$(field "$hazard" RAW_WAW)" "$(field "$sb" LOAD_USE)" \
        "$(field "$sb" ALU_USE)" "$(field "$load" PENDING_TAIL)" \
        "$(field "$cause" PF_SB)" "$(field "$cause" PF_LSU)" \
        "$(field "$cause" PF_LSU_SB)" "$(field "$producer" OCC0)" \
        "$(field "$producer" OCC1)" "$(field "$producer" OCC2)" \
        "$(field "$producer" BOTH_WAIT)" "$(field "$producer" WAIT_READY)" \
        "$(field "$producer" BOTH_READY)" "$(field "$hot" LOOKUP)" \
        "$(field "$hot" HIT)" >> "$csv"
done

{
    echo "PPA performance statistics"
    echo "CSV: $csv"
    echo
    awk -F, 'NR==1 {next} {printf "%-34s IPC=%-7s cycles=%-9s SB=%-8s LSU=%-7s PF=%-7s multi=%-7s\n", $1,$4,$2,$5,$6,$7,$8}' "$csv"
} > "$summary"

echo "[PPA] Performance CSV: $csv"
echo "[PPA] Performance summary: $summary"
