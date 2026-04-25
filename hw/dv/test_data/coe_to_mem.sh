#!/usr/bin/env bash
set -euo pipefail

# Convert all .coe files in SRC_DIR to one-hex-per-line .mem files in DST_DIR.
# Usage:
#   ./coe_to_mem.sh [SRC_DIR] [DST_DIR]
# Defaults:
#   SRC_DIR=hw/dv/test_data/coe
#   DST_DIR=hw/dv/test_data/mem

SRC_DIR="${1:-hw/dv/test_data/coe}"
DST_DIR="${2:-hw/dv/test_data/mem}"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Error: source directory not found: $SRC_DIR" >&2
  exit 1
fi

mkdir -p "$DST_DIR"

shopt -s nullglob
coe_files=("$SRC_DIR"/*.coe)

if (( ${#coe_files[@]} == 0 )); then
  echo "No .coe files found in $SRC_DIR"
  exit 0
fi

for coe_file in "${coe_files[@]}"; do
  base_name="$(basename "$coe_file" .coe)"
  mem_file="$DST_DIR/${base_name}.mem"

  awk '
    BEGIN {
      in_vec = 0
    }
    {
      line = $0
      sub(/^[ \t\r\n]+/, "", line)
      sub(/[ \t\r\n]+$/, "", line)

      if (line == "" || line ~ /^;/) {
        next
      }

      low = tolower(line)

      if (index(low, "memory_initialization_vector") > 0) {
        in_vec = 1
        # Handle inline values after '=' on the same line.
        eq = index(line, "=")
        if (eq > 0) {
          line = substr(line, eq + 1)
        } else {
          next
        }
      } else if (!in_vec) {
        next
      }

      gsub(/[;,]/, " ", line)
      n = split(line, tok, /[ \t]+/)
      for (i = 1; i <= n; i++) {
        t = tok[i]
        if (t == "") {
          continue
        }
        if (tolower(t) == "memory_initialization_vector") {
          continue
        }
        if (t ~ /^[0-9a-fA-F]+$/) {
          print tolower(t)
        }
      }
    }
  ' "$coe_file" > "$mem_file"

  echo "Converted: $coe_file -> $mem_file"
done

echo "Done. Generated ${#coe_files[@]} .mem files in $DST_DIR"
