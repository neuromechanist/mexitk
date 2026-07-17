# mexitk build strategy

MATLAB MEX files linked against ITK 5.x, built reproducibly with CMake, for
macOS arm64 (`maca64`) and Linux x86_64 (`glnxa64`).
This document is the output of hands-on research plus a verified proof of
concept (PoC), not a survey.
Facts below were checked against this Mac (Apple M4 Pro, arm64, macOS Tahoe
26 / Darwin 25.5.0, Apple clang 21.0.0, CMake 4.4.0), against an internal
Linux x86_64 test host (Ubuntu 24.04, gcc 13.3, CMake 3.28.3, no sudo),
and against the ITK 5.4.6 and CMake 4.4 sources directly.

## 1. Headline result

A real ITK-linked MEX file was built with `matlab_add_mex()` and CMake 4.4,
and loaded and ran correctly inside MATLAB R2025b on Apple Silicon.
It imported a MATLAB double array as an `itk::Image<double,3>` via
`itk::ImportImageFilter` (zero-copy), ran `itk::MedianImageFilter` over it,
and returned a correct filtered array.
`mexext` reported `mexmaca64` as expected.
See section 4 for the full trace, including two real bugs that were hit and
fixed along the way (a linker incompatibility and a VTK-teardown crash).

## 2. How to obtain ITK 5.x per platform

### Recommendation

**Ship a static, module-pruned ITK superbuild, pinned to a tag, built once
per platform and cached.**
Do not link a Homebrew (or any shared) ITK into anything that gets
redistributed.
Use a Homebrew ITK only for local, throwaway PoC work exactly as done here.

### Why, with the evidence

**Homebrew (`brew install itk`) — good for local PoC, wrong for shipping.**
Verified on this Mac: `itk` is at stable **5.4.6** (bottle revision 1), with
a native `arm64_tahoe` bottle, so on this machine it installs with **zero
compilation** — pure bottle pours.
But look at what it actually is:

- Built with `-DBUILD_SHARED_LIBS=ON` (see the formula's `install` block on
  GitHub) — every ITK library is a `.dylib` under `/opt/homebrew/opt/itk/lib`.
  `otool -L` on the PoC's compiled `.mexmaca64` shows absolute linker paths
  like `/opt/homebrew/opt/itk/lib/libITKCommon-5.4.1.dylib`.
  Ship that file to a user without Homebrew ITK installed at that exact path
  and it fails to load — this is exactly the failure mode the project exists
  to avoid.
- The formula depends on 10 other formulae unconditionally
  (`double-conversion`, `fftw`, `gdcm`, `hdf5`, `jpeg-turbo`, `libpng`,
  `libtiff`, `vtk`, plus `freetype`/`glew` on macOS), and turns on
  `-DModule_ITKVtkGlue=ON`, `-DModule_ITKReview=ON`, `-DModule_SCIFIO=ON`.
  `brew install itk` on this machine pulled **~70 transitive dependencies**
  including all of VTK, Qt (`qtbase`, `qtdeclarative`, `qtsvg`), GCC, and
  Python 3.14 — about 1.2 GB actually installed
  (`vtk` alone is 297 MB, `proj` 834 MB).
  None of that is needed for a segmentation-filter MEX.
- **This is not just a size problem — it is a crash bug.** The PoC linked
  against the full default-module Homebrew ITK first.
  It computed the correct answer, then **MATLAB itself segfaulted on exit**
  inside `vtkObjectFactoryRegistryCleanup`'s static destructor
  (`vtkCollection::RemoveAllItems` called on already-torn-down state).
  A control run of `matlab -batch "disp(1+1)"` with no MEX loaded exits
  clean (code 0), proving the crash is caused by the MEX pulling VTK's
  global object-factory machinery into MATLAB's own Cocoa/AppKit process.
  Re-scoping `find_package(ITK COMPONENTS ITKCommon ITKSmoothing)` (see
  §4) removed VTK from the link graph entirely and the crash disappeared,
  same binary output, clean exit code 0.
  This is a second, independent argument for module pruning beyond size and
  build time: an unpruned "kitchen sink" ITK build can crash the MATLAB
  host process on exit.
- No static-library option exists in the formula at all (no `--build-static`
  variant, `args` array is hardcoded `-DBUILD_SHARED_LIBS=ON`).
  Getting static libraries out of Homebrew ITK would mean maintaining a
  private tap/formula fork — more maintenance than a superbuild.

**ITK superbuild from source, pinned tag, static, module-pruned — the
shipping path.**
Checked directly against ITK's `CMakeLists.txt` at tag `v5.4.6`:

```cmake
set(ITK_OLDEST_VALIDATED_POLICIES_VERSION "3.16.3")
set(ITK_NEWEST_VALIDATED_POLICIES_VERSION "3.29.0")
cmake_minimum_required(VERSION ${ITK_OLDEST_VALIDATED_POLICIES_VERSION}...${ITK_NEWEST_VALIDATED_POLICIES_VERSION} FATAL_ERROR)
```

That is CMake's `<min>...<max>` range syntax with `min = 3.16.3`, safely
above the 3.5 floor CMake 4 enforces — **ITK 5.4.6 configures cleanly under
CMake 4.4 with no `CMAKE_POLICY_VERSION_MINIMUM` workaround needed** (verified:
the PoC's own `find_package(ITK 5.4 REQUIRED ...)` against a fully built ITK
5.4.6 package configured without a single fatal error under CMake 4.4.0; the
only noise was a `CMP0167` dev warning from VTK's *own* bundled `FindBoost`,
irrelevant once VTK is out of the module list).

Key CMake flags for a lean, static, redistributable build:

```
-DBUILD_SHARED_LIBS=OFF
-DITK_BUILD_DEFAULT_MODULES=OFF
-DModule_ITKCommon=ON            # + only the modules actually needed:
-DModule_ITKSmoothing=ON         #   e.g. filters actually used by mexitk
-DModule_ITKThresholding=ON
-DModule_ITKIOImageBase=ON       #   ... etc, enumerate explicitly
-DITK_USE_SYSTEM_ZLIB=OFF        # bundle third-party deps statically too,
-DITK_USE_SYSTEM_HDF5=OFF        # or link system static libs (see caveats)
-DITKV3_COMPATIBILITY=OFF
-DITK_LEGACY_REMOVE=ON
-DBUILD_TESTING=OFF
-DBUILD_EXAMPLES=OFF
-DCMAKE_POSITION_INDEPENDENT_CODE=ON   # required: a MEX is a shared object
-DCMAKE_CXX_STANDARD=17
```

The PoC proved the mechanism concretely: switching from an unscoped
`find_package(ITK 5.4 REQUIRED)` (which pulled in ~50 libraries including
all of VTK) to `find_package(ITK 5.4 REQUIRED COMPONENTS ITKCommon
ITKSmoothing)` cut the link graph to 14 libraries with **zero VTK**, just by
naming the two modules actually used.
`ITK_BUILD_DEFAULT_MODULES=OFF` + an explicit module list is the
build-time equivalent of that — it stops VTK/GDCM/HDF5/etc. from ever being
configured or compiled in the first place, not just left unlinked.
This is real and matters for build time and binary size, not a
micro-optimization.

**Build time / feasibility, estimated, not directly measured in CI:**
This Mac is an Apple M4 Pro with 14 cores (10 performance + 4 efficiency,
confirmed via `sysctl -n machdep.cpu.brand_string` /
`hw.perflevel{0,1}.physicalcpu`; the prompt's "12-core" figure is the other
common M4 Pro binning, not this specific unit).
A full default-module ITK build (what Homebrew does, including VTK/GDCM/
HDF5/etc.) commonly runs 45–90 minutes on a modern multi-core machine; a
`ITK_BUILD_DEFAULT_MODULES=OFF` build scoped to ~10–15 modules
(`ITKCommon`, `ITKSmoothing`, `ITKThresholding`, `ITKImageFilterBase`,
`ITKIOImageBase`, `ITKIONIFTI`/`ITKIOMeta` if segmentation I/O is needed,
etc.) should land in roughly 10–25 minutes on a GitHub Actions
`macos-15-arm64` runner (typically 3–4 vCPUs) and faster on this M4 Pro or
on a self-hosted runner (the internal Linux test host has CMake 3.28 / gcc
13.3, no sudo, so ITK build artifacts would need to be produced elsewhere
and copied in, or built in the user's own build dir without installing
system-wide).
This is an estimate reasoned from the measured Homebrew dependency graph and
published ITK community build-time reports, not a timed run in this task —
flag it as the first thing to calibrate once a real CI job exists (§5).

**conda-forge / micromamba (`itk` package).**
Consumable from CMake (conda-forge ships `ITKConfig.cmake` under
`$CONDA_PREFIX/lib/cmake`, and conda-forge's activation scripts add
`$CONDA_PREFIX/{include,lib}` to `CMAKE_ARGS`/compiler search paths).
But it is built **shared** by conda-forge's standard toolchain (same
redistribution problem as Homebrew), and it pulls a full conda environment
as a runtime dependency footprint.
There is a known conda-forge issue
(`conda-forge/libitk-feedstock#7`, hardcoded system HDF5 paths in
`ITKHDF5.cmake`) that reflects the general fragility of consuming a
package-manager ITK from a from-scratch CMake project.
Not recommended for shipping; not obviously better than Homebrew for a
disposable local PoC either, and this project has no conda/mamba installed,
so it would add a new tool dependency for no PoC benefit — skipped.

**vcpkg.** ITK **5.4.4** is currently in the vcpkg registry ("supported on
all triplets" per the vcpkg package page), meaning static triplets
(`x64-osx`, `arm64-osx`, `x64-linux`, and their `-static` variants) are
expected to work, with optional features (`fftw`, `vtk`, `opencv`, `tbb`,
`cuda`, `python`, …) that map directly onto ITK's module system — critically,
**`vtk` is an opt-in feature, off by default**, meaning a default vcpkg ITK
build already avoids the VTK-teardown problem found in the PoC.
vcpkg's version (5.4.4) trails Homebrew's (5.4.6) by two patch releases;
worth checking whether that gap matters before committing (likely not — no
known ABI-relevant changes between .4 and .6, but verify against the actual
module list mexitk needs).
This is the strongest **alternative** to a hand-rolled superbuild: vcpkg
already encodes "static, module-scoped, per-triplet, cacheable" as first-class
concepts, and `vcpkg.json` manifest mode integrates with `CMakePresets.json`
and GitHub Actions' `actions/cache` idiomatically.
**Recommendation stands as a hand-pinned CMake superbuild for full control
over the exact module list and version tag**, but vcpkg is the fallback if
superbuild maintenance becomes a burden — it is not a dead end, just not
what was chased down to a working build in the time available for this task.

### Self-contained requirement — what "self-contained" concretely means here

The PoC's `otool -L` on the Homebrew-linked `.mexmaca64` is the negative
example: absolute paths to `/opt/homebrew/opt/itk/lib/*.dylib` and
`/opt/homebrew/opt/fftw/lib/*.dylib`.
A static superbuild eliminates every one of those lines except MATLAB's own
`libmex.dylib`/`libmx.dylib` (which MATLAB always provides) and baseline
system libraries (`libSystem.B.dylib`, `libc++.1.dylib`, both present on
every Mac).
That is the concrete, testable definition of "ships with no runtime
dependency on a package manager": run `otool -L` (macOS) /
`ldd` (Linux) on the final `.mexmaca64`/`.mexa64` and see nothing outside
MATLAB's own `bin/<arch>` and the OS's base libraries.

## 3. CMake + MEX integration

### `FindMatlab`, in the CMake actually installed here (4.4.0)

`find_package(Matlab REQUIRED COMPONENTS MX_LIBRARY MEX_COMPILER)` works as
documented, but note a real version drift: in CMake ≥3.14, `MX_LIBRARY` (and
`ENGINE_LIBRARY`, `DATAARRAY_LIBRARY`) are **always found unconditionally**
and are no longer real "components" — passing `MX_LIBRARY` explicitly is
harmless (accepted, just redundant) but the module's own docs now describe
it as legacy phrasing.
Not a blocker, just don't be surprised if newer `FindMatlab` reference pages
look different from older tutorials.

**Non-standard MATLAB location.** Confirmed by reading `FindMatlab.cmake`
directly (lines ~252–290): on macOS, automatic search only checks
`$HOME/Applications` and `/Applications`, falling back to `PATH`.
The MATLAB install used for this research lives in a non-standard location
(call it `<MATLAB_ROOT>`, e.g. an external/secondary volume), so none of
that fires automatically — **`-DMatlab_ROOT_DIR=<MATLAB_ROOT>` is
required** on the CMake command line (or `Matlab_ROOT`, the CMake-3.25+
`<PackageName>_ROOT` spelling).
This was verified directly: `find_package(Matlab REQUIRED ...)` failed silently
without it and succeeded with it, reporting
`Found Matlab: <MATLAB_ROOT> (found version "25.2.0.3055257")`.

### CMake 4.4 compatibility — checked, not assumed

- **ITK 5.4.6**: configures clean under CMake 4.4 (see §2 — its own
  `cmake_minimum_required` range already satisfies the ≥3.5 floor CMake 4
  enforces). No `CMAKE_POLICY_VERSION_MINIMUM` shim needed for ITK itself.
- **FindMatlab**: is CMake's *own* bundled module (this is CMake 4.4.0's
  copy at `share/cmake/Modules/FindMatlab.cmake`), so by definition there is
  no version-skew issue — it's whatever ships with the CMake in use.
  Confirmed working end-to-end against MATLAB R2025b.
- **Watch item, not a blocker:** third-party ITK dependencies that get
  dragged in by an unpruned/default build (e.g. VTK's `FindBoost`) still use
  old-style unversioned `find_package(Boost)`, which trips CMake 4's
  `CMP0167` **policy warning** (not an error) because `FindBoost` is removed
  from CMake 4's own bundled modules in favor of upstream `BoostConfig.cmake`
  (Boost ships its own since 1.70). Confirmed: this fired during the PoC's
  first configure (before module pruning removed VTK from the graph) and
  was non-fatal — the configure completed and the build succeeded. This is
  further ammunition for module pruning: it also sidesteps CMake-4-era
  policy noise from ITK's heavier third-party modules.

### MEX API choice: C MEX API (`mexFunction`, `mxArray`) — recommended

Use the classic C MEX API, not the newer C++ MEX API
(`matlab::mex::Function`, MATLAB Data API).
Reasons, weighed for this project specifically:

- **Portability.** The C API is what every MATLAB release since forever
  supports, including the MCR, and is what `matlab_add_mex()`'s simplest
  path targets. The C++ API pulls in `libMatlabDataArray`/`libMatlabEngine`
  and a heavier initialization sequence (visible in the PoC's own
  `link.txt`: even a pure-C-API MEX gets `libMatlabEngine.dylib` and
  `libMatlabDataArray.dylib` linked in automatically by `matlab_add_mex()`
  as insurance — see next point).
- **This project's target (glnxa64 + maca64, MCR-agnostic, minimal runtime
  footprint) matches the C API's design center exactly.** The C++ API's
  main benefit — safer typed containers, RAII — is achievable with a thin
  wrapper over the C API's typed accessors (`mxGetDoubles`, not the
  deprecated `mxGetPr`) without taking on the heavier dependency.
- **The interleaved-vs-separate complex API choice is orthogonal and still
  applies to the C API.** `matlab_add_mex(... R2018a)` selects the modern
  **interleaved** complex memory layout (`-R2018a` mex flag), which is what
  new code should use; `R2017b` (the CMake module's *default* if the
  argument is omitted) selects the legacy separate-complex layout. **Pass
  `R2018a` explicitly** — the PoC does — since MathWorks' own docs warn a
  future MATLAB release will flip `mex`'s own default to `-R2018a`, and
  explicit is safer than relying on either default.
  `mxGetPr`/`mxGetPi` are formally "not recommended" (not yet hard-removed)
  in R2025b; new code should use `mxGetDoubles`/`mxGetComplexDoubles`. The
  PoC intentionally still calls `mxGetPr` on the real (non-complex) double
  input to keep the demonstration minimal — production `mexitk` code should
  use `mxGetDoubles` throughout.

### Output filename per platform

Confirmed: `matlab_add_mex()` handles this automatically via
`Matlab_MEX_EXTENSION`.
On this machine it produced `mexitk_median.mexmaca64` with no manual
`SUFFIX` handling needed (see `set_target_properties(... SUFFIX
".${Matlab_MEX_EXTENSION}")` inside `FindMatlab.cmake`).
Nothing to do here beyond calling `matlab_add_mex()`; it also correctly
strips the `lib` prefix (`PREFIX ""`), which a bare `add_library(... SHARED)`
would not.

### Symbol visibility — mechanism, read directly from `FindMatlab.cmake`

This is more subtle than "just add `-fvisibility=hidden`", and the module's
own prose is slightly out of step with what it actually does on modern
MATLAB. Read directly from `share/cmake/Modules/FindMatlab.cmake` (CMake
4.4.0, lines ~1460–1547):

- For MATLAB ≥ R2018b (`Matlab_VERSION_STRING >= 9.5`, true for R2025b), the
  module sets **`-fvisibility=default`** on the MEX target — *not* hidden.
  A code comment in the module explains why: `<mex.h>` in R2018b+ needs
  `MW_NEEDS_VERSION_H` defined for `mexFunction`'s
  `__attribute__((visibility("default")))` annotation to take effect, and
  building with `-fvisibility=hidden` at the compiler level was found to
  break the mex entry point on that MATLAB generation.
- The actual export restriction happens at the **linker** level instead: on
  macOS, `-Wl,-exported_symbols_list,<map-file>`; on Linux,
  `-Wl,--version-script,<map-file>`; on Windows, `/EXPORT:mexFunction`.
  The map files are shipped by MATLAB itself under
  `extern/lib/maca64/` (macOS) — confirmed present at
  `.../MATLAB_R2025b.app/extern/lib/maca64/c_exportsmexfileversion.map` and
  `.../cppMexFunction.map` — and list exactly the symbols MATLAB's mex host
  is allowed to call (`mexFunction`, `mexfilerequiredapiversion`, plus the
  C++-API bootstrap trio below).
- **Verified on the built PoC binary** (`nm -gU build/mexitk_median.mexmaca64`):
  exactly two external symbols exported — `_mexFunction` and
  `_mexfilerequiredapiversion`. None of ITK's ~1000+ symbols leak out, even
  though ITK itself was *not* built with hidden visibility (Homebrew's ITK
  uses default visibility throughout) — the linker-level export list is
  sufficient on its own to produce a clean, MATLAB-safe exported symbol
  table. This directly answers the "symbol visibility when linking a static
  ITK into a MEX" question from the brief: you don't need to fight ITK's own
  visibility settings at all; `matlab_add_mex()`'s linker-level restriction
  handles it regardless of how the linked-in ITK static libraries were
  compiled.

### A real linker bug found and fixed: Apple's new linker vs. `FindMatlab`'s C++ bootstrap stubs

This is the first genuinely new finding from the PoC, not documented
anywhere consulted during research. `FindMatlab.cmake` (same block as
above) unconditionally adds, on Apple platforms, when the found MATLAB
supports the C++ MEX API (true for R2025b, `Matlab_HAS_CPP_API`):

```
-Wl,-U,_mexCreateMexFunction -Wl,-U,_mexDestroyMexFunction -Wl,-U,_mexFunctionAdapter
```

`-Wl,-U,<symbol>` tells the linker "this symbol may remain undefined, don't
error" — it is inserted so a pure-C-API MEX (which never references these
three C++-bootstrap symbols) still links cleanly against the
`cppMexFunction.map` export list the module also attaches unconditionally
"even for C API MEX-files" (module's own comment).

**On this machine (Apple clang 21.0.0 / Xcode's default linker, `ld` version
1266.8, the "new" `ld-prime` linker that has been the arm64 default since
Xcode 15), `-Wl,-U` for these three symbols was silently not honored:**

```
Undefined symbols for architecture arm64:
  "_mexCreateMexFunction", referenced from: <initial-undefines>
  "_mexDestroyMexFunction", referenced from: <initial-undefines>
  "_mexFunctionAdapter", referenced from: <initial-undefines>
ld: symbol(s) not found for architecture arm64
```

Adding **`-Wl,-ld_classic`** to the MEX target's link options
(`target_link_options(mexitk_median PRIVATE -Wl,-ld_classic)`, gated
`if(APPLE)`) fixed it immediately — confirmed by a controlled A/B: removing
just that one flag from an otherwise-identical build reproduces the exact
failure above, and it is unrelated to the VTK issue (§2) — it reproduced
identically in both the VTK-linked and VTK-free builds.
Apple's linker prints `ld: warning: -ld_classic is deprecated and will be
removed in a future release`, so this is a **workaround, not a permanent
fix** — it needs a tracking issue and a periodic check of whether MathWorks
ships an updated `FindMatlab`/`mex` toolchain that plays correctly with the
new linker (this is entirely inside MATLAB's `extern/lib/maca64/*.map` files
and CMake's `FindMatlab.cmake`, i.e., not something `mexitk` itself can fix
upstream — file it against `matlab_add_mex`/CMake or MathWorks, and revisit
when Apple removes `ld_classic` entirely).

### C++ standard

ITK 5.4 hard-requires C++17 (confirmed directly in `CMakeLists.txt`:
`if(CMAKE_CXX_STANDARD EQUAL "98" OR CMAKE_CXX_STANDARD LESS "17")
message(FATAL_ERROR "C++98 to C++14 are no longer supported in ITK version
5.4 and greater.")`). R2025b's `mex` compiles with whatever
`CMAKE_CXX_STANDARD`/`-std=` is passed through the CMake toolchain — no
conflict was observed; the PoC sets `CMAKE_CXX_STANDARD 17` /
`CMAKE_CXX_STANDARD_REQUIRED ON` and the actual compile line captured in
`flags.make` shows `-std=c++17` applied cleanly alongside MATLAB's own
`-DMATLAB_DEFAULT_RELEASE=R2018a -DMATLAB_MEX_FILE` defines.

### macOS deployment target / arch

The PoC's compile/link lines show `-arch arm64` throughout, driven
automatically by CMake picking up the arm64 host and MATLAB's own arm64
toolchain; no manual `-mmacosx-version-min` was needed for this PoC to link
and run. For a shipped build, pin `CMAKE_OSX_DEPLOYMENT_TARGET` explicitly
to the oldest macOS MATLAB R2025b itself supports (currently macOS 14+ per
MathWorks system requirements — verify against the release notes actually
targeted at build time) and build the static ITK with the same value, so
ITK's and the MEX's object files agree on the deployment target and avoid
`-Wunguarded-availability`-class warnings/errors.

## 4. PoC — what was actually built and run

Built in a scratch directory during the bring-up session; a copy of the three
working files (`CMakeLists.txt`, `mexitk_median.cpp`, `test_mexitk.m`) is kept
outside the repo, in the maintainer's local working area, for reference. Not
committed anywhere — this is reference material, not shipped mexitk code, and
its content is superseded by the real `CMakeLists.txt` at the repo root.

**Route used for the PoC's ITK:** Homebrew (`brew install itk`, approved
before running), explicitly *not* the shipping recommendation — chosen
because it needed zero compile time (arm64_tahoe bottle) and the PoC's job
was only to prove the MEX+ITK+MATLAB toolchain works on arm64 at all, which
it does regardless of how ITK's libraries were produced.

**What the MEX does:** takes a MATLAB 3-D `double` array, wraps it with
`itk::ImportImageFilter<double,3>` (zero-copy — `SetImportPointer(inData,
numPixels, false)`, `false` meaning ITK does not take ownership/does not
free MATLAB's buffer), runs `itk::MedianImageFilter` with radius 1 over it,
and copies the filtered `itk::Image` buffer back into a newly allocated
MATLAB array returned as `plhs[0]`.

**Build command actually used:**

```sh
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DMatlab_ROOT_DIR=<MATLAB_ROOT> \
  -DITK_DIR=/opt/homebrew/opt/itk/lib/cmake/ITK-5.4
cmake --build build --config Release -j 10
```

Configure and build both completed cleanly (only the non-fatal `CMP0167`
policy warning noted in §3). Result:
`build/mexitk_median.mexmaca64`, Mach-O 64-bit dynamically linked shared
library, arm64, 144 KB.

**Verification inside MATLAB R2025b, exact command:**

```sh
<MATLAB_ROOT>/bin/matlab -batch "run('test_mexitk.m')"
```

Test script builds a 5×5×5 volume with a single hot outlier voxel (value
1000 at the center) and asserts the median filter knocks it down to 0 (the
local median of its 3×3×3 neighborhood, all zero) — this specifically rules
out the filter being a silent passthrough/no-op, since a no-op would return
1000 unchanged. Output:

```
mexext = mexmaca64
PASS: mexitk_median loaded, ran ITK MedianImageFilter, and produced correct output.
out(3,3,3) = 0 (expected 0, was 1000 before filtering)
EXIT CODE: 0
```

`nm -gU` on the built binary confirms exactly two exported symbols:
`_mexFunction`, `_mexfilerequiredapiversion` — no ITK internals leak into
MATLAB's symbol space.

**Two real problems hit and fixed, both documented in full in §3:**

1. Apple's new linker doesn't honor `FindMatlab.cmake`'s `-Wl,-U` stubs for
   the C++-API bootstrap symbols → fixed with `-Wl,-ld_classic` (deprecated,
   tracked as a revisit item).
2. An unpruned Homebrew ITK (with `ITKVtkGlue`/VTK linked in) caused MATLAB
   to segfault on process exit, *after* correctly computing and printing the
   right answer → fixed by scoping `find_package(ITK COMPONENTS ITKCommon
   ITKSmoothing)`, which is exactly the module-pruning practice already
   recommended for size/build-time reasons in §2 — this makes it also a
   correctness/stability requirement, not just an optimization.

**What was not verified:** Linux (`glnxa64`) build and load — the internal
Linux test host has no ITK installed and sudo is blocked there (per the
task's own constraint), so only the toolchain facts (CMake 3.28.3,
gcc 13.3.0, MATLAB R2025b at `/usr/local/bin/matlab`) were confirmed, not
an actual Linux build.
Windows: not attempted (best-effort/CI-only per the brief). A static
superbuild's actual build time was not measured — §2's figures are
reasoned estimates from the measured Homebrew dependency graph, flagged as
such and as the first thing to calibrate in real CI.

## 5. CI plan

### `matlab-actions/setup-matlab` on GitHub Actions

- Supports GitHub-hosted Linux/Windows/macOS runners and self-hosted UNIX
  runners. macOS Apple Silicon self-hosted runners additionally need a JRE
  installed (GitHub-hosted macOS-arm64 runners already ship one).
- **Licensing:** public repositories get MATLAB automatically licensed for
  free by the action itself (batch-licensing token only required for
  *private* repos — check whether the eventual `mexitk` repo is public
  before assuming this is free). Transformation products (MATLAB Coder,
  MATLAB Compiler) are excluded from the automatic public-repo licensing and
  would need separate arrangement — not needed for a MEX-only project.
- Release selection via the `release` input (`R2025b`, `R2025bU2`, etc.),
  products via a space-separated `products` list.

### Runner matrix

- `macos-15-arm64` (Sequoia, GA) or `macos-26-arm64`/Tahoe-labeled image
  (GA as of this research) for `maca64` — GitHub is phasing out macOS x86_64
  entirely by Fall 2027, so betting on arm64-only macOS runners going
  forward is the safe long-term choice, not just the cheaper one.
- `ubuntu-latest` (x86_64) for `glnxa64`.
- `windows-latest`, best-effort only, never a gate — matches the brief.

### Caching the static ITK build

Sketch, using `actions/cache` keyed on everything that invalidates a static
ITK build:

```yaml
- uses: actions/cache@v4
  with:
    path: ${{ runner.temp }}/itk-install
    key: itk-${{ matrix.os }}-${{ matrix.arch }}-v5.4.6-${{ hashFiles('cmake/itk-module-list.cmake') }}-${{ steps.cxx-version.outputs.value }}
```

Key components: ITK tag (`v5.4.6`), platform+arch (`macos-arm64` /
`linux-x86_64`), a hash of the explicit module list (so adding/removing a
module invalidates the cache), and the compiler identity/version (ABI is
compiler-version-sensitive for C++17 static libs). On a cache hit, skip the
ITK superbuild step entirely and just point `-DITK_DIR=` at the restored
install tree; on a miss, build and then save.

### The ITK build-time risk, and the mitigation

Per §2, an unpruned build is 45–90 minutes — expensive but not fatal within
GitHub Actions' 6-hour job limit, though it burns minutes on every
cache-miss run. A pruned, `ITK_BUILD_DEFAULT_MODULES=OFF` build is
estimated at 10–25 minutes (not yet measured in CI — calibrate on the first
real run and update this document with the measured number).
Mitigation, in priority order:

1. **Module pruning first** (§2) — the single biggest lever, and also fixes
   the VTK-teardown crash class found in §4, so it is not optional.
2. **Cache aggressively** (above) — after the first successful build per
   platform/module-list/compiler combination, subsequent CI runs restore in
   seconds instead of rebuilding.
3. **Build once, reuse across jobs**: build the static ITK in a dedicated
   job, upload as a build artifact, and have the actual MEX-build jobs
   (potentially a matrix over multiple mexitk MEX targets) download it
   rather than each rebuilding ITK independently.
4. If build time is still a problem after 1–3, consider a self-hosted
   runner for the ITK-build step specifically — the internal Linux test
   host is reachable but **sudo is blocked there and it must not be used
   for installs**; it could
   still serve as a plain build host for a from-source ITK build entirely
   within a user-writable prefix (no `sudo make install` needed for a
   superbuild that installs into a project-local directory), but this was
   not attempted or verified in this task.

## 6. What would need install approval, if this work continues

Nothing further was installed beyond the already-approved `brew install itk`
(which pulled ~70 dependencies, ~1.2 GB, all as bottles — see §2 for the
exact list). If the shipping (static superbuild) path is pursued next, no
new installs are obviously required — a from-source ITK superbuild only
needs the CMake/compiler toolchain already present on this Mac. If vcpkg
ends up preferred over a hand-rolled superbuild (§2's fallback), that would
need `brew install vcpkg` (or the bootstrap script) — not requested or run
in this task; ask before installing if that direction is taken.
