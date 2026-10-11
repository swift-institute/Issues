#!/usr/bin/env bash
# usage: probe.sh <label> <directory> <seconds> <signature-regex> <command...>
# Runs one probe, records its log, and reports clean / signature / other failure.
# Always exits 0: a probe is a measurement, not a gate.
set -uo pipefail
label=$1 dir=$2 seconds=$3 signature=$4
shift 4
logs="${RUNNER_TEMP:-/tmp}/probe-logs"
mkdir -p "$logs"
log="$logs/$(echo "$label" | tr -c 'A-Za-z0-9.-' '_').log"
start=$(date +%s)
(cd "$dir" && timeout "$seconds" "$@") > "$log" 2>&1
status=$?
elapsed=$(( $(date +%s) - start ))
if [ "$status" -eq 0 ]; then
  verdict="clean"
elif [ "$status" -eq 124 ]; then
  verdict="timed out after ${seconds}s"
elif grep -Eq "$signature" "$log"; then
  verdict="signature found"
else
  verdict="failed without the signature"
fi
{
  echo "### $label"
  echo "exit $status, ${elapsed}s: **$verdict**"
  echo '```'
  grep -E "$signature|error:|Assertion|Build complete" "$log" | sort | uniq -c | sort -rn | head -15
  echo '```'
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
echo "$label: exit $status, $verdict"
exit 0
