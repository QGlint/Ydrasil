#!/usr/bin/env bash
set -euo pipefail

root=${1:-build/sim/hw}
out_dir=${2:-build/PPA}
csv="$out_dir/perf_stats.csv"
summary="$out_dir/perf_stats_summary.log"
mkdir -p "$out_dir"

field() {
    local line=$1 key=$2
    if [[ $line =~ (^|[[:space:]])${key}=[[:space:]]*([0-9.]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[2]}"
    fi
}

header="program,cycles,insts,ipc,scoreboard,lsu_struct,producer_full,multi,flush,no_if_valid,other,raw_only,waw_only,raw_waw,load_use,alu_use,pending_tail,pf_sb,pf_lsu,pf_lsu_sb,occ0,occ1,occ2,both_wait,wait_ready,both_ready,stb_lookup,stb_hit,coremark_score,capacity_slots,productive_slots,lost_slots,slot_ipc,loss_flush,loss_mul_hold,loss_scoreboard,loss_lsu_struct,loss_lsu_serialize,loss_producer_full,loss_wb,loss_clint,loss_multi,loss_no_if_valid,loss_issue,loss_other,issue_fence,slot1_replay,slot1_sb_replay,slot1_lsu_replay,serialize_wait,dq0,dq1,dq2,dq3,dq4"
echo "$header" > "$csv"

mapfile -t logs < <(find "$root" -type f -name hw.log \( \
    -path '*/coe_loop5/hw.log' -o -path '*/coe_loop_lina/hw.log' -o \
    -path '*/coremark/hw.log' -o \
    -path '*/coremark-opt/*/hw.log' -o \
    -path '*/sort/*/hw.log' -o -path '*/sort-opt/*/*/hw.log' -o -path '*/boundary/*/hw.log' -o \
    -path '*/boundary-opt/*/*/hw.log' -o \
    -path '*/ydrasil-tests/*/hw.log' -o \
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
    stb=$(grep '^PERF_LSU_STB:' "$log" | tail -1 || true)
    slots=$(grep '^PERF_SLOT_ACCOUNT:' "$log" | tail -1 || true)
    slot_loss=$(grep '^PERF_SLOT_LOSS:' "$log" | tail -1 || true)
    issue_stage=$(grep '^PERF_ISSUE_STAGE:' "$log" | tail -1 || true)
    coremark=$(grep '^CoreMark 1\.0 :' "$log" | tail -1 || true)
    score=
    if [[ $coremark =~ CoreMark[[:space:]]+1\.0[[:space:]]*:[[:space:]]*([0-9.]+) ]]; then
        score=${BASH_REMATCH[1]}
    fi
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
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
        "$(field "$producer" BOTH_READY)" "$(field "$stb" LOOKUP)" \
        "$(field "$stb" HIT)" "$score" \
        "$(field "$slots" CAPACITY_SLOTS)" "$(field "$slots" PRODUCTIVE_SLOTS)" \
        "$(field "$slots" LOST_SLOTS)" "$(field "$slots" SLOT_IPC)" \
        "$(field "$slot_loss" FLUSH)" "$(field "$slot_loss" MUL_HOLD)" \
        "$(field "$slot_loss" SCOREBOARD)" "$(field "$slot_loss" LSU_STRUCT)" \
        "$(field "$slot_loss" LSU_SERIALIZE)" "$(field "$slot_loss" PRODUCER_FULL)" \
        "$(field "$slot_loss" WB)" "$(field "$slot_loss" CLINT)" \
        "$(field "$slot_loss" MULTI)" "$(field "$slot_loss" NO_IF_VALID)" \
        "$(field "$slot_loss" ISSUE)" "$(field "$slot_loss" OTHER)" \
        "$(field "$issue_stage" FENCE)" "$(field "$issue_stage" SLOT1_REPLAY)" \
        "$(field "$issue_stage" SLOT1_SB_REPLAY)" "$(field "$issue_stage" SLOT1_LSU_REPLAY)" \
        "$(field "$issue_stage" SERIALIZE_WAIT)" "$(field "$issue_stage" DQ0)" \
        "$(field "$issue_stage" DQ1)" "$(field "$issue_stage" DQ2)" \
        "$(field "$issue_stage" DQ3)" "$(field "$issue_stage" DQ4)" >> "$csv"
done

{
    echo "PPA performance statistics"
    echo "CSV: $csv"
    echo
    awk -F, 'NR==1 {next} {score=($29 == "" ? "-" : $29); printf "%-34s IPC=%-7s cycles=%-9s SB=%-8s LSU=%-7s PF=%-7s multi=%-7s score=%s\n", $1,$4,$2,$5,$6,$7,$8,score}' "$csv"
} > "$summary"

echo "[PPA] Performance CSV: $csv"
echo "[PPA] Performance summary: $summary"
python3 "$(dirname "$0")/analyze_bubbles.py" "$root" "$out_dir"
