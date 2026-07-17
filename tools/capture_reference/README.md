# Reference-capture harness

This directory holds the harness that captured the reference fixtures
committed under `tests/fixtures/` by exercising the original 2006
`matitk.mexa64` binary (MATITK v.2.4.04, built on ITK 2.4). The scripts
run each opcode mexitk reimplements (`FCA`, `FOMT`, `SWS`) across a range
of parameters and input types, and save the exact inputs/outputs/console
text as `.mat` fixtures so mexitk's own tests can compare against them.

## Do you need to run this?

Almost certainly not. `matitk.mexa64` is an Intel-Linux-only (`glnxa64`)
MEX binary from 2006 with no public source available, so most contributors
can never run this harness — and don't need to. The fixtures it produced
are already committed under `tests/fixtures/`, and mexitk's test suite
(`tests/t*Reference.m`) compares mexitk's own output against those
committed fixtures directly, without needing the original binary. Only
re-run this harness if you have your own copy of the original binary and
need to add or regenerate a fixture.

## How to run it

Set `MATITK_DIR` to the directory containing `matitk.mexa64` and invoke a
script with `matlab -batch`. Every script goes through
`refcap_config.m`, which reads:

- `MATITK_DIR` (required) — directory containing `matitk.mexa64`. The
  scripts error out with a clear message if this is unset or points at a
  nonexistent directory.
- `MEXITK_REFCAP_OUT` (optional) — output root for captured fixtures and
  logs. Defaults to a `mexitk-refcap/` folder under the system temp
  directory if unset. `fixtures/` and `logs/` subfolders are created
  underneath it automatically.

```sh
cd tools/capture_reference
MATITK_DIR=/path/to/dir/containing/matitk.mexa64 \
  matlab -batch "s00_smoke_test"
```

Run the scripts in order (`s00` through `s06`); later scripts assume
`load mri` and the same base volume conventions established earlier, and
`s01`/`s01b` establish the FOMT output-count semantics that `s03` relies
on. To point somewhere other than the temp-dir default for captured
output:

```sh
MATITK_DIR=/path/to/dir MEXITK_REFCAP_OUT=/path/to/output \
  matlab -batch "s02_fca_capture"
```

## Two real gotchas

1. **Opcode must be a `char` array, not a string.** The 2006 MEX rejects
   MATLAB's double-quoted string type: `matitk("FCA", ...)` errors with
   `Opcode input field must be of type string.` (yes, that message is
   printed when you pass the *wrong* type). Use single-quoted char arrays
   — `matitk('FCA', ...)` — or `char("FCA")` if you need to build the
   opcode dynamically. This is captured and asserted in
   `tests/fixtures/edge_cases.mat` (`edge.stringOpcode` vs.
   `edge.charCastOpcode`).

2. **`matlab -batch` changes the current directory to the script's own
   folder when you invoke it via `run('/path/to/script.m')`, but does
   *not* put anything else on the MATLAB path.** That's why each script
   calls `addpath(cfg.matitkDir)` explicitly rather than relying on the
   current directory — `matitk.mexa64` normally lives outside this repo
   entirely. Because scripts run this way execute from their own folder,
   plain function calls to sibling files in this directory (like
   `refcap_config.m` or `local_md5.m`) resolve without any extra
   `addpath`.

Also note: MATLAB script filenames cannot start with a digit, which is
why these are named `s00_...`, `s01_...`, etc. rather than `00_...`.

## What must not change if you edit these scripts

The captures, parameters, fixture field names, and saved variable names
are load-bearing — mexitk's tests compare against them by field name and
value. If you touch these scripts, keep the scientific behavior
byte-for-byte identical; only path plumbing should ever change here.
