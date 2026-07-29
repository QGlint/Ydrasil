#!/usr/bin/env bash
set -euo pipefail

root=${1:-build/sim/hw}
out_dir=${2:-build/PPA}
csv="$out_dir/perf_stats.csv"
primary_csv="$out_dir/perf_primary_stats.csv"
summary="$out_dir/perf_stats_summary.log"
mkdir -p "$out_dir"

field() {
    local line=$1 key=$2
    if [[ $line =~ (^|[[:space:]])${key}=[[:space:]]*([0-9.]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[2]}"
    fi
    # Older logs do not contain every detail record.  A missing optional field
    # is an empty CSV cell, not a failed collection run.
    return 0
}

header="program,cycles,insts,ipc,scoreboard,lsu_struct,producer_full,multi,flush,no_if_valid,other,raw_only,waw_only,raw_waw,load_use,alu_use,pending_tail,pf_sb,pf_lsu,pf_lsu_sb,occ0,occ1,occ2,both_wait,wait_ready,both_ready,stb_lookup,stb_hit,coremark_score,capacity_slots,productive_slots,lost_slots,slot_ipc,loss_flush,loss_mul_hold,loss_scoreboard,loss_lsu_struct,loss_lsu_serialize,loss_producer_full,loss_wb,loss_clint,loss_multi,loss_no_if_valid,loss_issue,loss_other,issue_fence,slot1_replay,slot1_sb_replay,slot1_lsu_replay,serialize_wait,dq0,dq1,dq2,dq3,dq4,issue_dispatch,issue_dispatch_two,issue_raw_pair_admit,issue_select,issue_select_two,issue_bypass_older,issue_nonadj_pair,issue_bypass_consumed,issue_scheduled_bypass,issue_registered_wakeup,issue_registered_alu_wakeup,issue_registered_lsu_wakeup,issue_registered_mdu_wakeup,issue_reserved_bypass_plan,issue_reserved_bypass_issue,issue_reserved_bypass_cancel,issue_ingress_occ0,issue_ingress_occ1,issue_ingress_occ2,issue_ingress_credit_admit,issue_ingress_to_station,issue_full_station_refill,issue_admission_backpressure,issue_ingress_flush_drain,completion_latency"
echo "$header" > "$csv"

primary_fields=(POLICY ISSUE2 ISSUE1 FLUSH MUL_HOLD MULTI SCOREBOARD LSU_STRUCT
    PRODUCER_FULL WB CLINT SERIALIZE ISSUE_ADVANCE IF_CONTROL IF_PREDICT IF_FENCE IF_RESPONSE
    IF_LAUNCH IF_PENDING IF_OTHER ISSUE_REFILL DECODE_REFILL ISSUE_BLOCKED OTHER
    ACCOUNTED SAMPLE_CYCLES CLOSURE_ERRORS)
decode_fields=()
for mask in $(seq -w 1 31); do
    decode_fields+=("H$mask")
done
decode_fields+=(STALL_CYCLES EXACT_SUM CLOSURE_ERRORS)
pair_fields=(CANDIDATE ELIGIBLE REJECT_RAW REJECT_WAW REJECT_RESOURCE REJECT_SERIAL
    REJECT_CONTROL_MEMORY REJECT_LANE REJECT_OTHER ACCOUNTED CLOSURE_ERRORS)
slot_fields=(SLOT0_EXEC SLOT1_EXEC PAIR_EXEC SLOT1_NO_PAIR SLOT1_SCOREBOARD_REPLAY
    SLOT1_LSU_REPLAY PRODUCTIVE_SLOT_SUM PRODUCTIVE_SLOTS CLOSURE_ERRORS)

primary_header=(program cycles insts ipc)
for key in "${primary_fields[@]}"; do primary_header+=("primary_${key,,}"); done
for key in "${decode_fields[@]}"; do primary_header+=("decode_${key,,}"); done
for key in "${pair_fields[@]}"; do primary_header+=("pair_${key,,}"); done
for key in "${slot_fields[@]}"; do primary_header+=("slot_${key,,}"); done
(IFS=,; echo "${primary_header[*]}") > "$primary_csv"

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
    if [[ $log == "$root/hw.log" ]]; then
        program=$(basename "$root")
    else
        program=${log#"$root"/}
        program=${program%/hw.log}
    fi
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
    issue_window=$(grep '^PERF_ISSUE_WINDOW:' "$log" | tail -1 || true)
    primary=$(grep '^PERF_PRIMARY_CYCLE:' "$log" | tail -1 || true)
    decode_exact=$(grep '^PERF_DECODE_STALL_EXACT:' "$log" | tail -1 || true)
    pair_detail=$(grep '^PERF_PAIR_DETAIL:' "$log" | tail -1 || true)
    slot_detail=$(grep '^PERF_SLOT_DETAIL:' "$log" | tail -1 || true)
    coremark=$(grep '^CoreMark 1\.0 :' "$log" | tail -1 || true)
    score=
    if [[ $coremark =~ CoreMark[[:space:]]+1\.0[[:space:]]*:[[:space:]]*([0-9.]+) ]]; then
        score=${BASH_REMATCH[1]}
    fi
    row=("$program" "$(field "$metric" CYCLES)" "$(field "$metric" INSTS)"
        "$(field "$metric" IPC)" "$(field "$stall" SCOREBOARD)"
        "$(field "$stall" LSU_STRUCT)" "$(field "$acct" PRODUCER_FULL)"
        "$(field "$acct" MULTI)" "$(field "$acct" FLUSH)"
        "$(field "$acct" NO_IF_VALID)" "$(field "$acct" OTHER)"
        "$(field "$hazard" RAW_ONLY)" "$(field "$hazard" WAW_ONLY)"
        "$(field "$hazard" RAW_WAW)" "$(field "$sb" LOAD_USE)"
        "$(field "$sb" ALU_USE)" "$(field "$load" PENDING_TAIL)"
        "$(field "$cause" PF_SB)" "$(field "$cause" PF_LSU)"
        "$(field "$cause" PF_LSU_SB)" "$(field "$producer" OCC0)"
        "$(field "$producer" OCC1)" "$(field "$producer" OCC2)"
        "$(field "$producer" BOTH_WAIT)" "$(field "$producer" WAIT_READY)"
        "$(field "$producer" BOTH_READY)" "$(field "$stb" LOOKUP)"
        "$(field "$stb" HIT)" "$score"
        "$(field "$slots" CAPACITY_SLOTS)" "$(field "$slots" PRODUCTIVE_SLOTS)"
        "$(field "$slots" LOST_SLOTS)" "$(field "$slots" SLOT_IPC)"
        "$(field "$slot_loss" FLUSH)" "$(field "$slot_loss" MUL_HOLD)"
        "$(field "$slot_loss" SCOREBOARD)" "$(field "$slot_loss" LSU_STRUCT)"
        "$(field "$slot_loss" LSU_SERIALIZE)" "$(field "$slot_loss" PRODUCER_FULL)"
        "$(field "$slot_loss" WB)" "$(field "$slot_loss" CLINT)"
        "$(field "$slot_loss" MULTI)" "$(field "$slot_loss" NO_IF_VALID)"
        "$(field "$slot_loss" ISSUE)" "$(field "$slot_loss" OTHER)"
        "$(field "$issue_stage" FENCE)" "$(field "$issue_stage" SLOT1_REPLAY)"
        "$(field "$issue_stage" SLOT1_SB_REPLAY)" "$(field "$issue_stage" SLOT1_LSU_REPLAY)"
        "$(field "$issue_stage" SERIALIZE_WAIT)" "$(field "$issue_stage" DQ0)"
        "$(field "$issue_stage" DQ1)" "$(field "$issue_stage" DQ2)"
        "$(field "$issue_stage" DQ3)" "$(field "$issue_stage" DQ4)"
        "$(field "$issue_window" DISPATCH)" "$(field "$issue_window" DISPATCH_TWO)"
        "$(field "$issue_window" RAW_PAIR_ADMIT)" "$(field "$issue_window" SELECT)"
        "$(field "$issue_window" SELECT_TWO)" "$(field "$issue_window" BYPASS_OLDER)"
        "$(field "$issue_window" NONADJ_PAIR)" "$(field "$issue_window" BYPASS_CONSUMED)"
        "$(field "$issue_window" SCHEDULED_BYPASS)" "$(field "$issue_window" REGISTERED_WAKEUP)"
        "$(field "$issue_window" REGISTERED_ALU_WAKEUP)"
        "$(field "$issue_window" REGISTERED_LSU_WAKEUP)"
        "$(field "$issue_window" REGISTERED_MDU_WAKEUP)"
        "$(field "$issue_window" RESERVED_BYPASS_PLAN)"
        "$(field "$issue_window" RESERVED_BYPASS_ISSUE)"
        "$(field "$issue_window" RESERVED_BYPASS_CANCEL)"
        "$(field "$issue_window" INGRESS_OCC0)" \
        "$(field "$issue_window" INGRESS_OCC1)" \
        "$(field "$issue_window" INGRESS_OCC2)" \
        "$(field "$issue_window" INGRESS_CREDIT_ADMIT)" \
        "$(field "$issue_window" INGRESS_TO_STATION)" \
        "$(field "$issue_window" FULL_STATION_REFILL)" \
        "$(field "$issue_window" ADMISSION_BACKPRESSURE)" \
        "$(field "$issue_window" INGRESS_FLUSH_DRAIN)"
        "$(field "$issue_window" COMPLETION_LATENCY)")
    (IFS=,; echo "${row[*]}") >> "$csv"

    primary_row=("$program" "$(field "$metric" CYCLES)"
        "$(field "$metric" INSTS)" "$(field "$metric" IPC)")
    for key in "${primary_fields[@]}"; do
        primary_row+=("$(field "$primary" "$key")")
    done
    for key in "${decode_fields[@]}"; do
        primary_row+=("$(field "$decode_exact" "$key")")
    done
    for key in "${pair_fields[@]}"; do
        primary_row+=("$(field "$pair_detail" "$key")")
    done
    for key in "${slot_fields[@]}"; do
        primary_row+=("$(field "$slot_detail" "$key")")
    done
    (IFS=,; echo "${primary_row[*]}") >> "$primary_csv"
done

{
    echo "PPA performance statistics"
    echo "CSV: $csv"
    echo "Exclusive/detail CSV: $primary_csv"
    echo
    awk -F, 'NR==1 {next} {score=($29 == "" ? "-" : $29); printf "%-34s IPC=%-7s cycles=%-9s SB=%-8s LSU=%-7s PF=%-7s multi=%-7s score=%s\n", $1,$4,$2,$5,$6,$7,$8,score}' "$csv"
} > "$summary"

echo "[PPA] Performance CSV: $csv"
echo "[PPA] Exclusive/detail CSV: $primary_csv"
echo "[PPA] Performance summary: $summary"
python3 "$(dirname "$0")/analyze_bubbles.py" "$root" "$out_dir"
