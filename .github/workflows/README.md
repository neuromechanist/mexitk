# CI workflow notes

This directory has one workflow, `ci.yml`.
It builds the `mexitk` MEX file and runs the MATLAB test suite on push to `main`, on every pull request, and on manual dispatch.

This document says plainly what is proven, what is assumed, and what a maintainer needs to check the first time it actually runs, since none of it has run in real GitHub Actions yet (it was written and validated for YAML syntax only; see the note at the end).

## What CI does

Two jobs run in parallel, matching the project's primary platform targets:

- **`macos-arm64`** -- installs ITK via Homebrew, builds `mexitk` with CMake, uploads the resulting `matlab/mexitk.mexmaca64`, and (license permitting, see below) runs the test suite through `matlab-actions/run-command`.
- **`ubuntu-x86_64`** -- builds ITK from source (apt's packaged ITK is too old, see below), builds `mexitk`, uploads `matlab/mexitk.mexa64`, and (license permitting) runs the same test suite.

A third job, **`windows-placeholder`**, is defined but disabled (`if: false`).
Windows is best-effort per the project brief and nothing about a working Windows build (ITK source, MSVC linker quirks, artifact naming) has been established, so the honest choice was a documented, disabled stub instead of a job that would fail on every run.

## What is proven vs. assumed

**Proven** (matches a real build on this machine: macOS arm64 M4 Pro, MATLAB R2025b, Homebrew ITK 5.4.6, Apple clang 21, 34/34 tests passing):

- The CMake configure/build commands for macOS (`cmake -S . -B build -DCMAKE_BUILD_TYPE=Release ...` / `cmake --build build -j`).
- The test invocation (`addpath('matlab'); ...run_mexitk_tests('.')...`) as a command, modulo the `run-command`-vs-`exit()` adaptation noted in the workflow's own comments.
- ITK component pruning (`ITKCommon`, `ITKAnisotropicSmoothing`, `ITKThresholding`, `ITKWatersheds`) avoiding the VTK link/crash problem.

**Researched and verified against current vendor docs (July 2026), but never exercised in an actual Actions run**:

- `matlab-actions/setup-matlab@v3` / `matlab-actions/run-command@v3` exist at those major versions, support macOS/Linux/Windows GitHub-hosted runners, and macOS Apple Silicon needs a JRE (GitHub's hosted `macos-*` arm64 images already ship one; only self-hosted arm64 runners need to install it manually).
- MATLAB licensing: public repos get free automatic licensing, but **only** when MATLAB is launched through `run-command` / `run-tests` / `run-build` themselves, not through a bare `matlab -batch` call or CTest.
  Private repos get no automatic licensing at all and need a MATLAB Batch Licensing Pilot token (`MLM_LICENSE_TOKEN` secret).
  See "Private-repo licensing" below; this is the single most important unverified-in-practice fact in this workflow.
- `libinsighttoolkit5-dev` on `ubuntu-latest` (Ubuntu 24.04 "noble") is version 5.3.0, below the 5.4 floor `find_package(ITK 5.4 REQUIRED ...)` demands (confirmed against Launchpad's package listing); hence building ITK from source on Ubuntu instead of `apt install`.
- Homebrew's `itk` formula is at 5.4.6 with prebuilt `arm64_sequoia` / `arm64_tahoe` / `arm64_sonoma` bottles, so `brew install itk` on a GitHub-hosted `macos-15` runner should be a bottle pour, not a source build (confirmed against formulae.brew.sh's formula API; not timed on an actual runner).
- `macos-15`, `macos-14`, and `macos-26` are all arm64 runner labels today; `macos-latest` also currently resolves to arm64.
  The workflow pins `macos-15` rather than floating on `-latest`.

**Pure estimate, explicitly flagged as such inline in `ci.yml`**:

- Ubuntu's from-source, module-pruned ITK build time (10-25 minutes, reasoned from Homebrew's dependency graph and community reports, not measured in CI).
  The `timeout-minutes: 60` ceiling on that job is a safety margin, not a target.
- That `matlab_add_mex()` compiling against the MATLAB tree `setup-matlab` installs behaves the same as compiling against a normal desktop MATLAB install.
  This is very likely true (it is how most MATLAB CMake projects use these actions) but was not independently verified in this session.

## Private-repo licensing -- read this first

`mexitk` starts as a **private** repository.
On GitHub Actions, MATLAB licensing for `matlab-actions/run-command` (and `run-tests`/`run-build`) is **free and automatic only on public repositories**.
On a private repo, with no license configured, the action cannot start MATLAB at all.

The workflow does not let this fail silently or fake a pass.
Each job:

1. Always runs the CMake configure/build steps and uploads the MEX artifact; this needs no MATLAB license (`matlab_add_mex()` compiles directly against MATLAB's headers/import libraries, no MATLAB process is launched to build).
2. Checks whether `MLM_LICENSE_TOKEN` is set (as a repo secret) or whether the repository is public.
3. If neither is true, **skips** the test step and prints a `::warning::` annotation explaining exactly why, instead of either failing red (which would look like a real regression) or silently passing (which would hide that no test ever ran).
4. If either is true, runs the real test suite and fails the job on any test failure, same as normal CI.

**To get real test signal while the repo is private**, a maintainer must request a MATLAB Batch Licensing Pilot token from MathWorks (see `matlab-actions/setup-matlab`'s README for the current eligibility-form link) and add it as the `MLM_LICENSE_TOKEN` repository secret.
That is an application to a pilot program, not an instant/guaranteed grant, and it explicitly does not cover MATLAB Engine / external-language-interface scenarios (not relevant here; mexitk's tests are plain MATLAB unit tests).
The alternative is simply making the repository public, at which point licensing becomes free and automatic with no token needed.

## What a maintainer must check on the first real run

1. **Does the private-repo licensing gate behave as intended?**
   Confirm the "Warn if MATLAB tests are being skipped" step actually fires (repo is private, no token yet) instead of either job going green on a real test pass it didn't do, or red for a reason unrelated to the code.
2. **Does `find_package(Matlab)` succeed against `setup-matlab`'s installed tree via the `MATLAB_ROOT_DIR` env var wiring?**
   This has not been exercised; if configure fails here, it is the first thing to debug.
3. **Ubuntu ITK build time and success.**
   This is the biggest unknown in the whole workflow; it has never been run.
   Expect the first attempt to need iteration (missing system packages, module-dependency resolution inside ITK's own CMake, etc.), and once it does succeed, update the time-estimate comments in `ci.yml` with the measured number.
4. **The ITK cache key.**
   It hardcodes the pruned module list as a literal string (`common_aniso_thresh_watersheds`) rather than hashing a `cmake/`-tracked file, because this workflow does not own such a file.
   If `CMakeLists.txt`'s `MEXITK_ITK_COMPONENTS` list changes, this literal must be updated by hand or the cache will silently serve a stale module set.
5. **Artifact filenames.**
   `matlab/mexitk.mexmaca64` (macOS) and `matlab/mexitk.mexa64` (Linux) are asserted by `upload-artifact`'s `if-no-files-found: error`; if `matlab_add_mex()`'s target name or output directory ever changes in `CMakeLists.txt`, this workflow needs a matching update.

## YAML validity

The workflow was checked locally with `python3 -c "import yaml; yaml.safe_load(open('ci.yml'))"` plus a structural check that every job has `runs-on` and that the `uses:` action references match what was intended.
That confirms the file parses as valid YAML and is structurally sane; it does **not** confirm the workflow actually succeeds on GitHub's runners.
`act` (local GitHub Actions runner) was not used, and no version of this workflow has executed on GitHub's infrastructure.
