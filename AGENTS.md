# mexitk Instructions

A MATLAB to ITK bridge: a MEX interface letting MATLAB call ITK
(Insight Segmentation and Registration Toolkit) image filters.
Standalone, BSD-3-Clause, owned by Seyed Yahya Shirazi (SCCN, INC, UC San Diego).

## Project Context

**Purpose:** A maintained, buildable replacement for **MATITK**
(Vincent Chu and Ghassan Hamarneh, Simon Fraser University, 2005-2006),
which is abandoned, has no public source, no licence, and no Apple Silicon build.
`mexitk` is a clean-room reimplementation of MATITK's *calling convention*,
not a port of its code; no MATITK source was available or used.

**Why it exists:** MATITK ships Intel-only MEX binaries with no `mexmaca64`,
and MEX files cannot run under Rosetta (they must match MATLAB's architecture).
So MRI segmentation in [NFT](https://github.com/sccn/NFT) is dead on Apple Silicon,
the only Mac platform MathWorks supports from R2026a onward.
Rewriting on MATLAB's Image Processing Toolbox was considered and rejected:
its equivalents are *different algorithms* and would change segmentation output.
Keeping ITK keeps the algorithms.

**Tech stack:** C++17, ITK 5.4+, CMake (>= 3.16, works under 4.4),
MATLAB MEX via the **C MEX API with `-R2018a`** (not the C++ MEX API).
Tests are `matlab.unittest`.

## Architecture Map

```
src/
├── mexitk.cpp          # mexFunction entry: arg parsing, validation, dispatch, diagnostics
├── mexitk_common.h     # pixel-type dispatch + mxArray <-> itk::Image bridge (zero-copy import)
├── opcode.h/.cpp       # the opcode registry; RegisterBuiltinOpcodes() is the one list
└── opcodes/            # 30 files for 32 opcodes: one file per opcode, except
                        # fdg.cpp (FDG + FGA) and fdm.cpp (FDM + FDMV), each a
                        # deliberate shared pair, not an accident
matlab/                 # built MEX lands here; run_mexitk_tests.m
tests/                  # matlab.unittest suites + committed reference fixtures
tools/
├── capture_reference/  # the harness that captured fixtures from the 2006 binary
└── measure_deviation.m # re-measure agreement with the reference after an ITK upgrade
docs/                   # COMPATIBILITY.md (the honest record), ITK mapping, opcode registry
```

**The registry, not codegen.** The original was generated from ITK's examples by a Perl script.
Here, each opcode is a small class implementing `Opcode`
(name, category, parameters, validation status, templated `Run`),
plus one line in `RegisterBuiltinOpcodes()`.
Registration is explicit, never via static initialisers:
static self-registration breaks the moment objects live in a static library
that the linker may drop, and it makes listing order depend on link order.

The registry is the single source of truth for dispatch, parameter validation,
the `mexitk('?')` listing, and the published validation status,
so documented status cannot drift from what the code claims.

## [CRITICAL] Core Principles

### Honesty about validation is the product

30 of 40 opcodes are implemented, and they are not equally trustworthy:
1 is validated, 2 have a measured bounded deviation, and the other 27 are
smoke-tested with no reference capture.
The status ladder is load-bearing and appears in the code, in `mexitk('?')`, and in the README:

- **validated** = bit-identical to the original, asserted against a stored fixture.
- **bounded deviation** = compared and does *not* match; the difference is measured and bounded.
- **smoke-tested** = runs, no reference.
- **untested** = never run against a reference.

Never conflate these. A README implying 30 validated filters when only 1 is validated is a lie.
If an opcode cannot be faithfully reproduced on modern ITK,
mark it unsupported rather than shipping something subtly different under the same name.

### [FUNDAMENTAL] Never tune a tolerance to make a test pass

The entire justification for this project is that the algorithms stay identical.
A tolerance chosen to go green is worthless and destroys that justification.
Where a test asserts a deviation bound, the number is **measured**, recorded in the test,
and documented in `docs/COMPATIBILITY.md`.
If a bound starts failing, agreement with the original moved:
investigate and update the docs. Do not raise the number.
Re-measure with `tools/measure_deviation.m`.

### No mocks; real data only

Tests run against fixtures captured from the real MATITK binary
(`MATITK v.2.4.04 Aug 18 2006`, md5 `c7d1432080e9edc6795a38717f5ab628`).
Fixtures are **committed** because regenerating them requires that Intel-Linux-only binary.
The reference input is MATLAB's built-in `load mri`, so no imaging data is redistributed.

### Reproduce the original's quirks on purpose

Deviating only happens in two directions: accept strictly more, or refuse to reproduce a defect.
Every deviation is enumerated, numbered, and justified in `docs/COMPATIBILITY.md`
(rows 1-12 as of this writing) — read it rather than this summary. A few
illustrative examples: `SWS` overthresholding errors instead of segfaulting
MATLAB; non-finite or wildly out-of-range filter results export as a defined
saturated/zero value on integral pixel types instead of an undefined-behaviour
cast; `FBL` rejects non-positive `domainSigma`/`rangeSigma` rather than
silently producing `NaN` output.

Quirks that ARE reproduced (do not "fix" these):
`FOMT` returns N outputs for N thresholds and drops the top Otsu class;
`nargout` must equal N; spacing (arg 6) is accepted and ignored;
`SWS` accepts and ignores seeds.

## Known traps (paid for once already)

- **ITK module pruning is a correctness requirement.** Resolving ITK without `COMPONENTS`
  pulls in `ITKVtkGlue`, and VTK's static destructors crash MATLAB on exit
  even when the filter returned a correct result. Keep `MEXITK_ITK_COMPONENTS` minimal.
- **Apple's linker.** CMake's `FindMatlab` adds `-Wl,-U,_mexCreateMexFunction`;
  `ld-prime` (default since Xcode 15 on arm64) ignores it and fails to link.
  `-Wl,-ld_classic` is the current fix and is itself deprecated; revisit when MathWorks updates FindMatlab.
- **`SetReturnBinMidpoint` looks like the fix for `FOMT` and is not.** ITK 2.4 semantics suggest
  midpoint; setting it makes every exact case diverge. Left explicit with a comment. Do not change it.
- **MATLAB `-batch` cd's to the script's directory**, so `addpath` explicitly.
  Script filenames cannot start with a digit.

## Development Workflow

1. **Check context:** `.context/plan.md` (tasks), `.context/research.md` (build strategy findings),
   `.context/ideas.md`, `.context/scratch_history.md` (dead ends), `.context/decisions/` (ADRs).
2. **Branch:** `gh issue develop <issue-number>`.
3. **Build:** `cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j`.
   Set `MATLAB_ROOT_DIR` if MATLAB is in a non-standard location.
4. **Test:** `matlab -batch "addpath('matlab'); exit(run_mexitk_tests('.'))"`.
5. **Commit:** atomic, <50 chars, no emojis, **no AI attribution**.
6. **PR + review:** `gh pr create`, then `/review-pr`. Do not merge until CI is green.

## [NEVER DO THIS]

- Never loosen a tolerance to make a test pass
- Never claim an opcode is validated without a fixture asserting it
- Never use mocks, stubs, or fake data in tests
- Never add an ITK module that no opcode needs
- Never commit secrets or credentials
- Never leave empty catch blocks or silent failures
- Never add TODO without a linked issue
- Never use emojis in commits, PRs, or code
- Never expose internal cluster paths or hostnames in this public repo

## [REFERENCE] Rules & Context

Rules (`.rules/`): `testing.md`, `git.md`, `code_review.md`, `documentation.md`,
`self_improve.md`, `ci_cd.md`, `serena_mcp.md`.

Context (`.context/`): `plan.md`, `research.md`, `ideas.md`, `scratch_history.md`, `decisions/`.

Docs (`docs/`): `COMPATIBILITY.md` (the honest record of agreement with the original),
`itk_opcode_mapping.md` (all 40 opcodes mapped to modern ITK), `matitk_opcode_registry.txt`
(the original binary's own parameter dump; authoritative for parameter names and order).

---
Preserve the algorithms. Prove the agreement. Say exactly what is and is not verified.
