# Normalize legacy RV test status records that were split after the cycle count.

function flush_pending(    continuation, actual_cycle) {
    if (pending == "")
        return 0

    continuation = $0
    if (continuation ~ /^[0-9]+[[:space:]]+\|[[:space:]]+Insts:/) {
        actual_cycle = continuation
        sub(/[[:space:]].*$/, "", actual_cycle)
        if (actual_cycle == expected_cycle) {
            sub(/^[0-9]+[[:space:]]+/, "", continuation)
            print pending " " continuation
            pending = ""
            expected_cycle = ""
            return 1
        }
    }

    print pending
    pending = ""
    expected_cycle = ""
    return 0
}

{
    if (pending != "" && flush_pending())
        next

    if ($0 ~ /^\[[^]]+\][[:space:]]+\[Cycles:[[:space:]][0-9]+$/) {
        pending = $0
        expected_cycle = $0
        sub(/^.*\[Cycles:[[:space:]]*/, "", expected_cycle)
        next
    }

    print
}

END {
    if (pending != "")
        print pending
}
