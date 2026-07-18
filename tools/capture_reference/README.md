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

### Campaign order: s07 through s13

`s07`–`s13` extend the harness to the 30 opcodes mexitk has since
implemented (`s07`–`s11`), a set of cross-check probes (`s12`), and the
10 opcodes mexitk still does not implement (`s13`). Run them after
`s00`–`s06`, in numeric order, **each in its own separate `matlab -batch`
invocation** — this is a crash-isolation requirement, not a style
preference: some of these opcodes (see `s13` below) may crash the whole
MATLAB process, and a fresh invocation per script means a crash in one
script cannot take an earlier script's already-saved fixtures with it.

```sh
MATITK_DIR=/path/to/dir MEXITK_REFCAP_OUT=/path/to/output \
  matlab -batch "s07_filters_capture"
# ...repeat for s08_morphology_capture, s09_regiongrow_capture,
# s10_gradients_capture, s11_fca_sws_integral_capture, s12_inference_probes...
MATITK_DIR=/path/to/dir MEXITK_REFCAP_OUT=/path/to/output \
  matlab -batch "s13_unimplemented_probes"   # its OWN run; may crash
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

## No fixture may embed a path or hostname

This is a public repo, so **no fixture may contain any absolute path,
hostname, or `cfg.matitkDir` value.** `s07`–`s13` add no path-bearing
field at all — every value they save is either a captured array, a hash,
a parameter, or a recipe string whose only free variable is `V` (the
`mri` base volume). `s06_provenance.m` is the one script that ever
embeds a path (`provenance.binaryPath`, `provenance.md5sumRaw`), and only
because provenance is the point of that script; the **committed**
`tests/fixtures/provenance.mat` replaces the real path with the literal
placeholder string `$MATITK_DIR` before it is committed — that
substitution happens by hand at commit time, not automatically by the
script, so if you ever re-run `s06` and commit its output, repeat the
substitution. See the project's public-repo rule: never expose internal
cluster paths or hostnames.

## Derived-input recipe convention

Several `s07`–`s13` fixtures use an input that isn't a plain cast of the
`mri` base volume (binarized/labelled/carved-hole volumes, the `FAAB`
binarize-at-33 input, an all-zero volume, and `s13`'s shifted second
image). These carry an `inputRecipe` field (or, for a second image,
`arg4Recipe`): a `char` MATLAB expression whose only free variable is
`V`. The capture script builds the actual input by `eval`-ing the exact
string it then stores — one source of truth, so the recipe and the
captured `inputHash` can never drift apart. A consumer (Phase 3's
`mexitkFixture` extension) rebuilds the same input by evaluating
`fixture.inputRecipe` with `V = squeeze(mri.D)` in scope, then asserts
`local_md5(vin) == fixture.inputHash`.

One MATLAB wrinkle to know before doing that: **`eval` cannot capture a
return value from a string that itself contains an assignment
statement** — this is general MATLAB behavior, not specific to any one
recipe (`y = eval('a=1; a')` errors "Incorrect use of '=' operator" on
its own). Most recipes here are a single expression (e.g.
`double(V>30)*255`), so `vin = eval(recipe)` works directly. The two
"carved hole" recipes are multi-statement with internal assignments
(`b=...; c=...; h=...; b(h(1))=0; b`), so both the capture script and any
consumer must instead run `eval([recipe ';']);` as a bare statement (the
appended `;` only suppresses console echo of the whole volume, it does
not change the recipe) and then read the recipe's own named result
variable, `b`, out of the workspace afterward — not `vin = eval(recipe)`.
`s08_morphology_capture.m` has a worked example.

## s13 is expendable and expected to crash

`s13_unimplemented_probes.m` probes the 10 opcodes mexitk does not
implement, several of which (registration, level sets, and especially
`SCSS`, which maps to ITK's `CellularAggregate` and carries global static
state plus a mesh output) may crash the MATLAB process outright — not a
catchable `itk::ExceptionObject`, a real process exit. This is expected
and acceptable: `s13` is exploratory, its probes are fingerprints rather
than faithful captures, they are ordered cheap/safe first and dangerous
last (`SCSS` is always the final probe; nothing is expected to run after
it), and every probe saves its own `.mat` immediately so a crash only
loses whatever that one probe was doing, never any earlier result. Run
`s13` in its own invocation, never combined with another script, and
don't be alarmed if the MATLAB process it runs in doesn't exit cleanly.

## Runtimes are unknown but logged

Expected runtimes per script against the real binary are not known ahead
of time (they depend entirely on hardware nobody running this harness
has). Each script writes a `diary` log to `logsDir` so a real campaign
run leaves a timing record after the fact. Two points are already known
to be slow from mexitk's own equivalent calls: `FBL [5 5]` (`s10`, ~5-6
seconds per call — captured exactly once, not swept across classes) and
`RD`'s 150-iteration demons registration (`s13`).

## Validating locally without the original binary

`matitk.mexa64` is Intel-Linux-only and unavailable to most contributors
(see "Do you need to run this?" above), so these scripts cannot be
exercised against the real binary outside a machine that has it. Set
`MEXITK_REFCAP_DRYRUN=1` to validate everything else locally: every
script still runs `load mri`, builds every input (including `eval`-ing
every derived-input recipe), and constructs every case — it just skips
the `matitk` call itself, recording `success=false` / `errmsg='dryrun'`
per case instead. A broken recipe or a malformed case table still fails
immediately under dry-run; that is the point. `MATITK_DIR` must still
point at an existing directory (it does not need to contain the binary
in dry-run mode; a scratch directory is fine):

```sh
MATITK_DIR=/tmp/some-existing-dir MEXITK_REFCAP_OUT=/tmp/mexitk-dryrun \
  MEXITK_REFCAP_DRYRUN=1 matlab -batch "s07_filters_capture"
```

Dry-run fixtures are throwaway — never commit anything captured with
`MEXITK_REFCAP_DRYRUN=1` set.

## What must not change if you edit these scripts

The captures, parameters, fixture field names, and saved variable names
are load-bearing — mexitk's tests compare against them by field name and
value. If you touch these scripts, keep the scientific behavior
byte-for-byte identical; only path plumbing should ever change here.

`s00`–`s06`, `refcap_config.m`, and `local_md5.m` are byte-identical
locked: mexitk's committed fixtures (`tests/fixtures/`) were captured by
their exact current text, so nothing in them may change, ever, ideally not
even a comment. `s07`–`s13` and the shared helpers (`capture_case.m`,
`local_summarize.m`, `local_isdryrun.m`) are not under that lock yet —
no fixture from them is committed as of this phase, fixture selection is
a later phase's job — but once a fixture they produced is committed,
this same rule starts applying to whatever produced it.
