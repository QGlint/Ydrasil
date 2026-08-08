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

append_header_fields() {
    local prefix=$1 key
    shift
    for key in "$@"; do
        header+=",${prefix}${key,,}"
    done
}

append_record_fields() {
    local line=$1 key
    shift
    for key in "$@"; do
        row+=("$(field "$line" "$key")")
    done
}

header="program,cycles,insts,ipc,coremark_score,capacity_slots,productive_slots,lost_slots,slot_ipc"
control_keys=(DEP_TOKEN_ENTRY_CYCLES ORDER_TOKEN_ENTRY_CYCLES
              RESOURCE_ENTRY_CYCLES SELECTABLE_ENTRY_CYCLES RS_BANK_FULL
              RS_PAIR_BANK_LIMIT ROB_FULL LSU_CREDIT DIV_CREDIT SERIAL_GATE
              SELECT_WIDTH OPERAND_DEP_MISS RECOVERY RECOVERY_RESYNC)
local_control_keys=(ALU_ENTRY_CYCLES P0_ENTRY_CYCLES P1_ENTRY_CYCLES ALU_FULL
                    P0_FULL P1_FULL ALU_DUE_SELECT DTCM_DUE_SELECT
                    MDU_DUE_SELECT DTCM_LOCAL_WAKE MDU_LOCAL_WAKE
                    RESIDENT_WAKE_ENTRIES RESIDENT_DUE_SELECT)
rob_occ_keys=(O0 O1 O2 O3 O4 O5 O6 O7 O8 O9 O10 O11 O12 ACCOUNTED SAMPLE)
rs_occ_keys=(O0 O1 O2 O3 O4 O5 O6 O7 O8 O9 O10 ACCOUNTED SAMPLE)
pipe_flow_keys=(RS_ALLOC0 RS_ALLOC1 RS_ALLOC2 SELECT0 SELECT1 SELECT2
                OPERAND0 OPERAND1 OPERAND2 COMPLETE0 COMPLETE1 COMPLETE2 COMPLETE3
                COMPLETE4 RETIRE0 RETIRE1 RETIRE2 SAMPLE)
rob_head_keys=(EMPTY RETIRE1 RETIRE2 COMPLETE_VISIBLE NOT_ISSUED WAIT_ALU
               WAIT_LOAD WAIT_MDU WAIT_STORE WAIT_BRANCH WAIT_OTHER ACCOUNTED
               SAMPLE)
backend_loss_keys=(FLUSH OPERAND_BLOCK SINGLE_BUNDLE SELECT_REFILL RS_DEPENDENCY
                   RS_ORDER RS_RESOURCE RS_OTHER ROB_FULL RS_REFILL DECODE_REFILL
                   FRONTEND OTHER ACCOUNTED EXPECTED)
candidate_keys=(M0 M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 M11 M12 M13 M14 M15)
cycle_keys=(FLUSH MUL_HOLD DEPENDENCY LSU_STRUCT LSU_SERIALIZE PRODUCER_FULL WB
            CLINT MULTI NO_IF_VALID ISSUE OTHER ACCOUNTED SAMPLE_CYCLES)
other_slot_keys=(ROB_BLOCK RECOVERY_RESYNC RS_BANK_BLOCK ALU_BANK_BLOCK P0_BANK_BLOCK P1_BANK_BLOCK
                 RS_PAIR_LIMIT SELECT_REFILL RS_DEPENDENCY
                 RS_ORDER RS_RESOURCE RS_NO_CANDIDATE RS_EMPTY DECODE_BLOCK
                 UNCLASSIFIED ACCOUNTED EXPECTED)
bank_block_keys=(ALU_LOCAL_FULL ALU_CREDIT_STALE P0_LOCAL_FULL P0_CREDIT_STALE
                 P1_LOCAL_FULL P1_CREDIT_STALE UNCLASSIFIED ACCOUNTED EXPECTED)
p0_full_keys=(DEPENDENCY ORDER RESOURCE READY_RELEASE NO_CANDIDATE ACCOUNTED EXPECTED)
slot_reason_keys=(EXECUTED FLUSH MUL_HOLD MULTI_CAUSE DEPENDENCY LSU_STRUCT
                  PRODUCER_FULL WB CLINT LSU_SERIALIZE NO_IF_VALID ISSUE OTHER
                  ACCOUNTED EXPECTED)
noif_slot_keys=(CONTROL_REDIRECT PREDICT_REDIRECT FENCE_REFILL MEM_RESPONSE
                FETCH_LAUNCH PENDING_REDIRECT OTHER ACCOUNTED EXPECTED)
issue_slot_keys=(DEPENDENCY LSU_STRUCT LSU_SERIALIZE SINGLE_LANE NO_EXECUTE
                 ACCOUNTED EXPECTED)
branch_keys=(BRANCHES HITS PRED_TAKEN MISPRED ACC)
frontend_keys=(PRED_TAKEN_REDIRECT CORRECT_TAKEN_REDIRECT PRED_TAKEN_BUBBLE
               WRONG_DIR_FLUSH BTB_MISS_TAKEN)
append_header_fields control_ "${control_keys[@]}"
append_header_fields local_ "${local_control_keys[@]}"
append_header_fields rob_occ_ "${rob_occ_keys[@]}"
append_header_fields rs_occ_ "${rs_occ_keys[@]}"
append_header_fields flow_ "${pipe_flow_keys[@]}"
append_header_fields head_ "${rob_head_keys[@]}"
append_header_fields backend_loss_ "${backend_loss_keys[@]}"
append_header_fields candidate_ "${candidate_keys[@]}"
append_header_fields cycle_ "${cycle_keys[@]}"
append_header_fields other_slot_ "${other_slot_keys[@]}"
append_header_fields bank_block_ "${bank_block_keys[@]}"
append_header_fields p0_full_ "${p0_full_keys[@]}"
append_header_fields slot_reason_ "${slot_reason_keys[@]}"
append_header_fields noif_slot_ "${noif_slot_keys[@]}"
append_header_fields issue_slot_ "${issue_slot_keys[@]}"
append_header_fields branch_ "${branch_keys[@]}"
append_header_fields frontend_ "${frontend_keys[@]}"
echo "$header" > "$csv"
{
    echo "PPA performance statistics"
    echo "CSV: $csv"
    echo
} > "$summary"

mapfile -t logs < <(find "$root" -type f -name hw.log \( \
    -path '*/coremark/hw.log' -o \
    -path '*/coremark-opt/*/hw.log' -o \
    -path '*/sort/*/hw.log' -o -path '*/sort-opt/*/*/hw.log' -o -path '*/boundary/*/hw.log' -o \
    -path '*/boundary-opt/*/*/hw.log' -o \
    -path '*/ydrasil-tests/*/hw.log' -o \
    -path '*/rv32ui/*/hw.log' -o -path '*/rv32um/*/hw.log' -o \
    -path '*/rv32uz*/*/hw.log' -o -path '*/rv32mi/*/hw.log' \) | sort)

for log in "${logs[@]}"; do
    grep -q '^PERF_CONTROL_DECOUPLE:' "$log" || continue
    program=${log#"$root"/}
    program=${program%/hw.log}
    metric=$(grep '^PERF_METRIC:' "$log" | tail -1)
    acct=$(grep '^PERF_CYCLE_ACCOUNT:' "$log" | tail -1)
    slots=$(grep '^PERF_SLOT_ACCOUNT:' "$log" | tail -1 || true)
    control=$(grep '^PERF_CONTROL_DECOUPLE:' "$log" | tail -1)
    local_control=$(grep '^PERF_LOCAL_CONTROL:' "$log" | tail -1 || true)
    rob_occ=$(grep '^PERF_ROB_OCCUPANCY:' "$log" | tail -1 || true)
    rs_occ=$(grep '^PERF_RS_OCCUPANCY:' "$log" | tail -1 || true)
    pipe_flow=$(grep '^PERF_PIPE_FLOW:' "$log" | tail -1 || true)
    rob_head=$(grep '^PERF_ROB_HEAD_STATE:' "$log" | tail -1 || true)
    backend_loss=$(grep '^PERF_BACKEND_LOSS:' "$log" | tail -1 || true)
    candidates=$(grep '^PERF_SELECT_CANDIDATES:' "$log" | tail -1 || true)
    branch=$(grep '^PERF_BRANCH:' "$log" | tail -1 || true)
    frontend=$(grep '^PERF_FRONTEND:' "$log" | tail -1 || true)
    other_slot=$(grep '^PERF_OTHER_SLOT_DETAIL:' "$log" | tail -1 || true)
    bank_block=$(grep '^PERF_BANK_BLOCK_DETAIL:' "$log" | tail -1 || true)
    p0_full=$(grep '^PERF_P0_FULL_DETAIL:' "$log" | tail -1 || true)
    slot_reason=$(grep '^PERF_SLOT_REASON:' "$log" | tail -1 || true)
    noif_slot=$(grep '^PERF_NOIF_SLOT_DETAIL:' "$log" | tail -1 || true)
    issue_slot=$(grep '^PERF_ISSUE_SLOT_DETAIL:' "$log" | tail -1 || true)
    coremark=$(grep '^CoreMark 1\.0 :' "$log" | tail -1 || true)
    score=
    if [[ $coremark =~ CoreMark[[:space:]]+1\.0[[:space:]]*:[[:space:]]*([0-9.]+) ]]; then
        score=${BASH_REMATCH[1]}
    fi
    row=(
        "$program" "$(field "$metric" CYCLES)" "$(field "$metric" INSTS)"
        "$(field "$metric" IPC)" "$score"
        "$(field "$slots" CAPACITY_SLOTS)" "$(field "$slots" PRODUCTIVE_SLOTS)"
        "$(field "$slots" LOST_SLOTS)" "$(field "$slots" SLOT_IPC)"
    )
    append_record_fields "$control" "${control_keys[@]}"
    append_record_fields "$local_control" "${local_control_keys[@]}"
    append_record_fields "$rob_occ" "${rob_occ_keys[@]}"
    append_record_fields "$rs_occ" "${rs_occ_keys[@]}"
    append_record_fields "$pipe_flow" "${pipe_flow_keys[@]}"
    append_record_fields "$rob_head" "${rob_head_keys[@]}"
    append_record_fields "$backend_loss" "${backend_loss_keys[@]}"
    append_record_fields "$candidates" "${candidate_keys[@]}"
    append_record_fields "$acct" "${cycle_keys[@]}"
    append_record_fields "$other_slot" "${other_slot_keys[@]}"
    append_record_fields "$bank_block" "${bank_block_keys[@]}"
    append_record_fields "$p0_full" "${p0_full_keys[@]}"
    append_record_fields "$slot_reason" "${slot_reason_keys[@]}"
    append_record_fields "$noif_slot" "${noif_slot_keys[@]}"
    append_record_fields "$issue_slot" "${issue_slot_keys[@]}"
    append_record_fields "$branch" "${branch_keys[@]}"
    append_record_fields "$frontend" "${frontend_keys[@]}"
    (IFS=,; echo "${row[*]}") >> "$csv"
    printf '%-40s IPC=%-7s cycles=%-9s dep_token=%-9s order=%-9s resource=%-9s bank_full=%-8s rob_full=%-8s score=%s\n' \
        "$program" "$(field "$metric" IPC)" "$(field "$metric" CYCLES)" \
        "$(field "$control" DEP_TOKEN_ENTRY_CYCLES)" \
        "$(field "$control" ORDER_TOKEN_ENTRY_CYCLES)" \
        "$(field "$control" RESOURCE_ENTRY_CYCLES)" \
        "$(field "$control" RS_BANK_FULL)" "$(field "$control" ROB_FULL)" \
        "${score:--}" >> "$summary"
done

echo "[PPA] Performance CSV: $csv"
echo "[PPA] Performance summary: $summary"
python3 "$(dirname "$0")/analyze_bubbles.py" "$root" "$out_dir"
