#!/usr/bin/env bash
# wax/mayhem/build.sh — build the WAX transpiler (waxc) as the fuzz target, plus a clean
# normal-flags build of the same binary for wax's golden-output test suite (mayhem/test.sh).
#
# wax is a single-binary C transpiler: src/waxc.c #includes the whole front end — the large
# dedicated src/parser.c (~98KB: tokenizer, preprocessor, S-expression / wax-language syntax tree,
# type/semantic analysis) — and every code generator (src/to_c.c, to_py.c, to_wat.c, …). The CLI
# reads a .wax source FILE and transpiles it to a target language. The Mayhem target is FILE-INPUT
# (CLI): the fuzz bytes are handed to /mayhem/waxc as a .wax source file (transpiled to C), exercising
# the entire tokenize → preprocess → syntax_tree → compile pipeline in parser.c. There is NO libFuzzer
# harness — the transpiler binary IS the natural fuzz surface, exactly like the lacc/my_basic
# file-input templates (so no *-standalone reproducer either: the file-input target already crashes
# naturally on a single input file).
#
# build.sh produces TWO binaries from the same single-file amalgamation (src/waxc.c):
#   (1) /mayhem/waxc        — SANITIZED fuzz target (ASan+UBSan halting, by default)
#   (2) /mayhem/waxc-tests  — NORMAL-flags oracle binary for mayhem/test.sh's golden suite (no
#                             sanitizers, so the oracle exercises real shipped transpiler behavior).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the base ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit
# empty value (--build-arg SANITIZER_FLAGS=) is honored → no-sanitizer build (the transpiler's
# natural crash). The build links only -lm (libc math, used by the wax std preamble emitters), which
# is present without the sanitizer runtime, so the empty-sanitizer build links cleanly.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS CC MAYHEM_JOBS

cd "$SRC"

# wax's Makefile builds with `-O3 -std=c99 -pedantic -Wall`. We keep -std=c99 (the dialect waxc is
# written in) and silence the project's own clean-build warnings (-w) so the build stays quiet; they
# don't affect transpiler behavior. src/waxc.c is an amalgamation (#includes parser.c + every to_*.c),
# so a single compile of waxc.c builds the whole transpiler.
BASE_CFLAGS="-std=c99 -w"

# No benign-UB relaxation: every shipped example transpiles to C under halting ASan+UBSan with NO
# sanitizer output (smoke-tested: helloworld/fib/quicksort/nqueens/turing → exit 0, clean). The
# UBSan findings wax does surface (e.g. an out-of-bounds index in the syntax-tree stack on some
# inputs) are REAL defects we WANT the fuzzer to catch — so ASan + all of UBSan stay ON and HALTING.

# ---------------------------------------------------------------------------
# (1) FUZZ build — waxc compiled WITH $SANITIZER_FLAGS so the fuzzed code (the whole transpiler,
#     parser.c + every code generator) is instrumented. File-input Mayhem target → /mayhem/waxc.
# ---------------------------------------------------------------------------
$CC $SANITIZER_FLAGS $BASE_CFLAGS src/waxc.c -o /mayhem/waxc -lm

# ---------------------------------------------------------------------------
# (2) TEST-ORACLE build — the SAME amalgamation with the project's NORMAL flags (no sanitizer), for
#     mayhem/test.sh's golden-output suite. A clean, independent build so the oracle reflects real
#     shipped transpiler behavior; test.sh only RUNS this binary (it never compiles).
# ---------------------------------------------------------------------------
$CC -O3 $BASE_CFLAGS src/waxc.c -o /mayhem/waxc-tests -lm

echo "build.sh: built /mayhem/waxc (sanitized fuzz target) and /mayhem/waxc-tests (test oracle)"
ls -l /mayhem/waxc /mayhem/waxc-tests
