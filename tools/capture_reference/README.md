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
# s10_gradients_capture, s10b_faab_crash_probe, s11_fca_sws_integral_capture,
# s12_inference_probes...
MATITK_DIR=/path/to/dir MEXITK_REFCAP_OUT=/path/to/output \
  matlab -batch "s13_unimplemented_probes"   # its OWN run; may crash
```

`s10b_faab_crash_probe.m` runs after `s10`, in its own invocation, for the
same crash-isolation reason as `s13`: `FAAB` on `uint8` input was measured,
across two campaign runs, to kill the original's process with a floating
point exception, not a catchable `itk::ExceptionObject` — first on raw
mri (run 1), then again on the already-binarized `bin33` input (run 2).
The crash is about the pixel type, not the pixel value distribution:
binarizing first does not avoid it. `s10` itself only captures `FAAB` on
`double`/`single`, both raw and `bin33` (all of which completed cleanly
in both runs); `s10b` isolates every integral-class `FAAB` case — raw and
`bin33`, `uint8` and `int32` (presumed to crash the same way, not yet
directly confirmed) — so a crash there cannot cost `s10`'s other cases.

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
hostname, or `cfg.matitkDir` value belonging to *this project's own
infrastructure*** — the capture machine, `MATITK_DIR`, or anything else
under this harness's control. `s07`–`s13` add no such path-bearing field
at all — every value they save is either a captured array, a hash, a
parameter, or a recipe string whose only free variable is `V` (the `mri`
base volume). `s06_provenance.m` is the one script that ever embeds one
of *this project's* paths (`provenance.binaryPath`, `provenance.md5sumRaw`),
and only because provenance is the point of that script; the
**committed** `tests/fixtures/provenance.mat` replaces the real path with
the literal placeholder string `$MATITK_DIR` before it is committed —
that substitution happens by hand at commit time, not automatically by
the script, so if you ever re-run `s06` and commit its output, repeat the
substitution. See the project's public-repo rule: never expose internal
cluster paths or hostnames.

This rule does **not** apply to the original binary's own strings.
`consoleText`/`errmsg` routinely preserve paths the *2006 binary itself*
has compiled in — e.g. `itkGaussianOperator`'s warnings cite
`/cs/guests/vwchu/myfiles/LinuxBuildMATITK64/InsightToolkit-2.8.1/...`,
the original author's own SFU build tree from 2006. That is authentic
captured output, not a leak: the rule concerns this project's
infrastructure, and scrubbing the reference binary's own embedded
strings would falsify the very console text the campaign exists to
record faithfully.

## Derived-input recipe convention

Several `s07`–`s13` fixtures use an input that isn't a plain cast of the
`mri` base volume (binarized/labelled/carved-hole volumes, the `FAAB`
binarize-at-33 input, an all-zero volume, and `s13`'s shifted second
image). These carry an `inputRecipe` field (or, for a second image,
`arg4Recipe`): a `char` MATLAB expression whose only free variable is
`V`. The capture script builds the actual input by `eval`-ing the exact
string it then stores — one source of truth, so the recipe and the
captured `inputHash` can never drift apart. A consumer (this **epic's**
Phase 3 — reference tests — not the opcode epic's Phase 3, `mexitkFixture`
extension) rebuilds the same input by evaluating
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
The `diary` log is written incrementally too, so it survives a crash up
to its last flushed line — check it first if you need to know exactly
where a run stopped.

**After any crash, verify every `.mat` in `fixturesDir` loads before
trusting or committing anything from that run.** A crash mid-`save` can
leave a partially written or corrupt `.mat` file behind; a load-check
catches that immediately instead of surfacing it later, silently, in
Phase 2's fixture selection or Phase 3's tests:

```matlab
files = dir(fullfile(cfg.fixturesDir, '*.mat'));
for i = 1:numel(files)
    try
        load(fullfile(files(i).folder, files(i).name));
    catch me
        fprintf('CORRUPT: %s (%s)\n', files(i).name, me.message);
    end
end
```

## s14: settling RTPS's landmark calling convention

`s14_rtps_landmarks.m` is a targeted, single-opcode follow-up run after
`RD`/`RTPS` were implemented (Epic 4 Phase 1) from an inference with no
successful reference capture to check it against. It grew across two
rounds, nine fixtures total. Round 1 (six fixtures) answers two open
questions `s13`'s own single-seed probe left open: whether the flat
landmark list splits in half (a full source block then a full target
block) or interleaves (`source1,target1,source2,target2,...`), and which
volume the transform resamples, in which direction. Round 1 also left
two of its five successful captures with a real, unexplained residual;
round 2 (three more fixtures: a coplanar-but-distinct 3-pair set, a
2-distinct-pair set, and a 3-distinct-pair non-coplanar set) was added
specifically to isolate the cause, and did: the threshold is the number
of DISTINCT landmark pairs (3 or more reproduces exactly, regardless of
coplanarity), not coplanarity as round 1's evidence alone suggested.
Every question is answered by the captures themselves, not guessed: see
`docs/COMPATIBILITY.md`'s "RD and RTPS: the first registration opcodes"
section and `src/opcodes/rtps.cpp`'s `StatusNote` for the full evidence
trail. One structural finding worth noting here rather than only in the
opcode's own docs: the original rejects a landmark argument passed as a
**matrix** with `Seed array must be a vector.` — landmarks, like every
other seed array in this codebase, must be a flat row vector of
concatenated 3-tuples. Run it exactly like `s07`–`s13` (its own
`matlab -batch` invocation).

## Completion sentinels: telling exit-time corruption from a mid-script crash

The original binary was measured (run 1) to sometimes corrupt the heap
**after** a script's diary shows every case completed successfully —
`munmap_chunk(): invalid pointer` printed only once MATLAB itself was
shutting down, well after the script's last `capture_case` call had
already returned and saved. That still exits nonzero (typically `137`,
SIGKILL), which is indistinguishable from a genuine mid-script crash by
exit code alone — except that a script which finished has nothing left
to lose, and one that crashed mid-script may have lost every case after
the crash point.

Every `s07`–`s13` script (and `s10b`) resolves this ambiguity itself:
each writes a zero-byte completion marker,
`<MEXITK_REFCAP_OUT>/COMPLETE_<scriptId>` (e.g. `COMPLETE_s09`), as its
last act before `diary off` — after every case in its table has already
been captured and saved. If that marker exists after a run, the script
completed in full regardless of its exit code or what happened during
MATLAB's own shutdown; if it does not, the script was interrupted
mid-script and its diary log (see above) is the way to find out how far
it got.

## Resume mode

Set `MEXITK_REFCAP_RESUME=1` to make a rerun after a crash incremental:
`capture_case` checks, for every case, whether its target `.mat` already
exists in `fixturesDir` before doing anything else, and if so skips that
case entirely — no re-hashing, no re-running `matitk` — logging one line
and returning the previously saved fixture instead (so a script whose
later probes depend on an earlier capture's output, like `s12`'s
identity/accessor cross-checks, still behaves correctly across a
resumed run). Combine with the completion sentinels above: if a script's
marker is missing, rerun it with `MEXITK_REFCAP_RESUME=1` set and only
the cases that never got captured the first time will actually call
`matitk` again.

```sh
MATITK_DIR=/path/to/dir MEXITK_REFCAP_OUT=/path/to/output \
  MEXITK_REFCAP_RESUME=1 matlab -batch "s09_regiongrow_capture"
```

## Seeded calls need a class-matched empty arg4

Measured directly against the real binary (run 1): a seeded call
(`SCT`/`SCC`/`SNC`/`SIC`, or any `capture_case` row with `seedArg` but no
real `arg4`) on `single`/`uint8`/`int32` input failed uniformly with
`Both images (inputArrays) must be of the same data type.` — the
original type-checks `arg4` against the input's class even when `arg4`
is conceptually absent, and a bare MATLAB `[]` is a *double* empty, which
mismatches anything non-`double`. `capture_case` now passes
`cast([], class(input))` instead of a bare `[]` whenever a seed is
present without a real second image — `uint8([])`, `single([])`,
`int32([])`, or plain `[]` for `double` input, uniformly, with no
per-script special-casing needed. This is a no-op for `double` input, so
it changes nothing about the cases that already worked.

## Open question: is the original's seed indexing 0-based or 1-based?

Run 1 found that seeds sitting exactly at a dimension maximum — `[70 50
27]` (`z` = the volume's own z-extent) and `SIC`'s old second seed
`[1 128 1]` (`y` = the volume's own y-extent) — both error with
`Location of seed outside volume`, regardless of which axis was at the
maximum. That's consistent with more than one indexing rule (0-based
with an exclusive upper bound, 1-based with an off-by-one, etc.), so
`s12`'s `probe9_seed_base_indexing` brackets the known-good seed
`[70 50 14]` by -1/0/+1 on every axis at once — `[0 0 0]` in particular
is valid *only* if the original reads coordinates as literal 0-based ITK
indices with no MATLAB-side conversion. Either an output or the
outside-volume error at each bracketed point is itself the answer; this
is not resolved yet, it is instrumented so the next campaign's fixtures
can resolve it.

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
even a comment. `s07`–`s13`, `s10b`, and the shared helpers
(`capture_case.m`, `capture_classes.m`, `local_summarize.m`,
`local_isdryrun.m`, `local_isresume.m`, `local_mark_complete.m`) are now
under that same lock too: this phase committed the 256 fixtures they
produced (guarded by `tests/tFixtureHygiene.m` and `MANIFEST.txt`), so
per the rule above, whatever produced an already-committed fixture may
not change. What is still a later phase's job is fixture *selection* —
deciding which of these captures become the basis for correctness
assertions the way FCA/FOMT/SWS's fixtures already are.
