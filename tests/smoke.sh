#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
STATE_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$STATE_DIR"
}
trap cleanup EXIT

if ! perl -MTerm::ReadKey -e 1 >/dev/null 2>&1; then
  echo "SKIP: Term::ReadKey not installed."
  exit 0
fi

run_session() {
  local input="$1"
  env TERM=dumb 5ESS_STATE_DIR="$STATE_DIR" 5ESS_SEED=1 perl "$ROOT_DIR/5ESS.pl" <<< "$input"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  echo "$haystack" | grep -Fq "$needle"
}

out=$(run_session $'5\nalpha\npw\nADMIN\nQUIT\n')
assert_contains "$out" "RESULT: OK - NEW CLERK CREATED"

out=$(run_session $'5\nbeta\npw\nTECH\nQUIT\n')
assert_contains "$out" "RESULT: OK - NEW CLERK CREATED"

out=$(run_session $'\nalpha\npw\nREQ:AUTH,CLRK="beta";\nRCV:OPEN,TKT="T1";\nRCV:ADD,TERM=1001;\nRCV:ADD,PAIR=CP1;\nRCV:ADD,COS=POTS;\nRCV:ADD,LINETYPE=1FR;\nRCV:ADD,CLASS=RES;\nRCV:CHECK;\nRCV:COMMIT;\nALM:LIST;\nQUIT\n')
assert_contains "$out" "RESULT: OK - AUTH GRANTED BY beta"
assert_contains "$out" "RESULT: OK - VALIDATION OK"
assert_contains "$out" "RESULT: OK - RCV COMMIT T1"
assert_contains "$out" "SEQ=00001"
assert_contains "$out" "SEQ=00002"

out=$(run_session $'4\nalpha\npw\nSCC:SUBMIT,JOB="TEST",PARM="RUN";\nSCC:STAT;\nSCC:OUT,JOBID=1;\nQUIT\n')
assert_contains "$out" "RESULT: OK - JOB 1 QUEUED"
assert_contains "$out" "RESULT: OK - SCC STATUS"
assert_contains "$out" "RESULT: OK - SCC OUTPUT"

printf "Smoke tests passed.\n"
