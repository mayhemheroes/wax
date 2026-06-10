#!/usr/bin/env bash
# wax/mayhem/test.sh — GOLDEN / known-answer oracle for the WAX transpiler (waxc).
#
# wax ships NO unit-test suite (test-waxc.sh just runs waxc under valgrind for a manual smoke; the
# Makefile has no test target). It DOES ship a set of deterministic example programs under examples/.
# We turn the deterministic ones into a known-answer functional oracle by transpiling each to a
# target language and DIFFing the generated source against a committed golden file.
#
#   * mayhem/build.sh built /mayhem/waxc-tests with the project's NORMAL flags (NO sanitizer), so the
#     oracle exercises the real shipped transpiler behavior. This script only RUNS that binary — it
#     never compiles (PATCH grading: patch -> build.sh -> test.sh).
#   * For each case it runs `waxc <example> --<lang> <out>` and diffs the generated source against
#     mayhem/testdata/golden/<name>.out. The goldens were captured once from the normal-flags binary
#     and verified byte-stable across repeated runs (after the two normalizations below).
#
# TWO normalizations make the transpiler output deterministic and host-independent — applied IDENTICALLY
# when capturing the golden and when checking, so they never weaken the oracle (they only strip
# environment noise, not transpiled logic):
#   1. Fixed output basename. waxc derives the emitted MODULE NAME from the output file's basename, so
#      we always write to "<work>/module.<ext>" — the module name is the constant "module" regardless
#      of the example, keeping the header stable.
#   2. Strip the one "Compiled by WAXC (Version <__DATE__>)" banner line. Every backend stamps the C
#      compile date (__DATE__) into a single header comment; that line — and ONLY that line — is removed
#      from both golden and actual output. Everything else (the entire emitted program) is asserted.
#
# This is a PATCH-grade, anti-reward-hack oracle by construction: it asserts the EXACT transpiled
# OUTPUT — the full generated C / Python source for each example — not merely "exited 0". A no-op /
# exit(0) "patch", or any change that breaks the tokenizer / syntax tree / a code generator so an
# example stops transpiling to its correct output, FAILS the diff.
set -uo pipefail

# clang/gcc reject SOURCE_DATE_EPOCH='' (empty); must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"

# SRC is /mayhem in the commit image; default to this checkout's repo root so the suite also runs
# straight from a developer checkout (mayhem/ is one level below the repo root).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${SRC:=$(cd "$HERE/.." && pwd)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# The normal-flags oracle binary that build.sh produced.
BIN="$SRC/waxc-tests"
[ -x "$BIN" ] || { echo "missing $BIN — run mayhem/build.sh first" >&2; emit_ctrf "wax-golden" 0 1; exit 2; }

GOLDEN="$SRC/mayhem/testdata/golden"
[ -d "$GOLDEN" ] || { echo "missing golden dir $GOLDEN — wrong tree?" >&2; emit_ctrf "wax-golden" 0 1; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0; failed=0

# run_case <name> <example> <flag> <ext>
# Transpiles examples/<example>.wax with <flag> (e.g. --c) to a fixed-basename output, strips the
# __DATE__ banner, and diffs against mayhem/testdata/golden/<name>.out. MUST exit 0 AND match.
run_case() {
  local name="$1" ex="$2" flag="$3" ext="$4"
  local gold="$GOLDEN/$name.out" got="$WORK/$name.out" rc
  if [ ! -f "$gold" ]; then
    echo "FAIL $name: missing golden $gold" >&2; failed=$((failed+1)); return
  fi
  if [ ! -f "$SRC/examples/$ex.wax" ]; then
    echo "FAIL $name: missing example examples/$ex.wax" >&2; failed=$((failed+1)); return
  fi
  # Fixed basename "module.<ext>" → stable emitted module name (normalization #1).
  "$BIN" --silent "$SRC/examples/$ex.wax" "$flag" "$WORK/module.$ext" >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL $name: waxc $ex $flag exited $rc (expected 0)" >&2
    failed=$((failed+1)); return
  fi
  # Strip the __DATE__ banner line (normalization #2), then diff the full generated source.
  grep -v 'Compiled by WAXC' "$WORK/module.$ext" > "$got"
  if diff -u "$gold" "$got" > "$WORK/$name.diff" 2>&1; then
    echo "PASS $name"; passed=$((passed+1))
  else
    echo "FAIL $name: transpiled output differs from golden" >&2
    head -20 "$WORK/$name.diff" | sed 's/^/    /' >&2
    failed=$((failed+1))
  fi
}

# Deterministic example programs transpiled to two backends — each diff asserts the FULL generated
# source, exercising the tokenizer + syntax tree (parser.c) and a specific code generator (to_c.c /
# to_py.c). A diverse spread of language features: hello (I/O), fib (recursion), quicksort (arrays +
# recursion), nqueens (backtracking + 2D arrays), turing (structs + simulation loop).
run_case helloworld_c  helloworld --c  c    # to_c   : printing / std preamble
run_case fib_c         fib        --c  c    # to_c   : recursion
run_case quicksort_c   quicksort  --c  c    # to_c   : arrays + recursion
run_case nqueens_c     nqueens    --c  c    # to_c   : backtracking
run_case turing_c      turing     --c  c    # to_c   : structs + simulation
run_case helloworld_py helloworld --py py   # to_py  : printing
run_case fib_py        fib        --py py   # to_py  : recursion
run_case nqueens_py    nqueens    --py py   # to_py  : backtracking

emit_ctrf "wax-golden" "$passed" "$failed"
