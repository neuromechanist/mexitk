# Building mexitk

mexitk is a MEX (MATLAB executable) interface that lets MATLAB call ITK
(Insight Segmentation and Registration Toolkit) image filters.
This document describes how to build it from a clean checkout, on every
platform the project targets, along with the two hard-won build gotchas you
will hit on macOS.

## Prerequisites

All platforms:

- C++17 compiler.
- ITK 5.4 or later.
- CMake 3.16 or later (CMake 4.4 has been verified to work).
- MATLAB with the MEX compiler (`mex`) available.
  mexitk uses the classic C MEX API with the `-R2018a` (interleaved complex)
  flag, not the newer C++ MEX API, so no C++ MEX support is required from
  MATLAB itself.

macOS specific:

- Apple clang (Xcode command line tools). Verified with Apple clang 21.
- Homebrew, for the development path to ITK (see below).

Linux specific:

- gcc or clang with C++17 support.
- ITK 5.4 or later, built or installed separately; no packaged install path
  has been verified yet (see Platform status below).

Windows specific:

- Windows builds are best-effort only, exercised through GitHub Actions.
  No prerequisites have been verified on Windows directly.

## Getting ITK

### Development: Homebrew (macOS)

For local development on macOS, install ITK with Homebrew:

```sh
brew install itk
```

This has been verified to install ITK 5.4.6 as a native `arm64` bottle, with
no compilation needed on Apple Silicon.
It is a fast, convenient way to get a working ITK for local builds and
tests.

It is not, however, suitable for shipping a binary.
Homebrew's ITK is built shared (`BUILD_SHARED_LIBS=ON`), and a MEX linked
against it carries absolute linker paths into
`/opt/homebrew/opt/itk/lib/*.dylib` (confirmed with `otool -L` on a built
MEX).
Ship that file to a machine without Homebrew ITK installed at that exact
path, and it fails to load.
Homebrew's ITK build also pulls in roughly 70 transitive dependencies,
including all of VTK and Qt, none of which mexitk's filters need; see
Troubleshooting below for why that matters beyond disk space.

### Shipping: static superbuild (not yet implemented)

The intended path for a redistributable binary is a static, module-pruned
ITK superbuild, pinned to a fixed tag (`v5.4.6`), built with
`BUILD_SHARED_LIBS=OFF` and `ITK_BUILD_DEFAULT_MODULES=OFF` plus an explicit
module list matching what mexitk actually links against.
This has **not yet been done**; there is no static ITK build script in this
repository yet, and no static-linked mexitk binary has been produced or
tested.
A fuller writeup of the reasoning and the concrete CMake flags involved is
in `.context/research.md`; read that file for detail if you are picking up
this work.

## Configuring and building

```sh
# Only needed if MATLAB is installed in a non-standard location:
export MATLAB_ROOT_DIR=/path/to/MATLAB_R2025b.app

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

`MATLAB_ROOT_DIR` seeds CMake's `FindMatlab` module so it can locate a
MATLAB installation outside the locations it searches automatically.
Set it to the MATLAB application/installation root, not to a `bin` or
`extern` subdirectory.

The build writes the compiled MEX to `matlab/mexitk.<ext>`, where `<ext>` is
the platform's MEX extension (for example `mexmaca64` on macOS arm64).
The `matlab/` output directory is set explicitly in `CMakeLists.txt`, so the
MEX lands next to the MATLAB helper scripts and tests that expect it there,
regardless of where the `build/` directory itself is.

## Running the tests

```sh
matlab -batch "addpath('matlab'); exit(run_mexitk_tests('.'))"
```

`run_mexitk_tests` returns the number of failing tests, which becomes the
process exit code; `0` means every test passed.
On the verified macOS arm64 build, this reports 34/34 tests passing.

## Platform status

| Platform | MEX extension | Status |
|---|---|---|
| macOS arm64 | `mexmaca64` | Builds and tested. Verified on Apple M4 Pro, MATLAB R2025b, Homebrew ITK 5.4.6, Apple clang 21. |
| Linux x86_64 | `glnxa64` | Not yet built. This is a primary target, but no build has been attempted or verified yet. |
| macOS x86_64 | `mexmaci64` | Untried. Legacy target: R2025b is MathWorks' final Intel-Mac release. Build it if convenient, but it is never a blocker. |
| Windows | `mexw64` | Not attempted. Best-effort only, through GitHub Actions. |

Linux arm64 is not a target: MATLAB does not exist on that platform.

## Troubleshooting

### "symbol(s) not found for architecture arm64" on macOS

On macOS, CMake's `FindMatlab` module adds
`-Wl,-U,_mexCreateMexFunction -Wl,-U,_mexDestroyMexFunction -Wl,-U,_mexFunctionAdapter`
to the MEX link line.
These flags tell the linker that those three symbols may remain undefined,
which is what keeps a plain C MEX API build loadable by a MATLAB that also
supports the C++ MEX API, even though a C-API MEX never references those
symbols.

Apple's `ld-prime` linker, the default on arm64 since Xcode 15, does not
honor `-Wl,-U` for these three symbols.
The build fails with:

```
Undefined symbols for architecture arm64:
  "_mexCreateMexFunction", referenced from: <initial-undefines>
  "_mexDestroyMexFunction", referenced from: <initial-undefines>
  "_mexFunctionAdapter", referenced from: <initial-undefines>
ld: symbol(s) not found for architecture arm64
```

even though none of those symbols are ever called.

`CMakeLists.txt` works around this by adding `-Wl,-ld_classic` to the MEX
target's link options on Apple platforms, which switches back to the
classic linker and resolves the failure.
Apple has marked `-ld_classic` deprecated and warns it will be removed in a
future release, so this is a workaround, not a permanent fix.
It needs revisiting once MathWorks ships an updated `FindMatlab`/`mex`
toolchain that is compatible with the new linker.

### MATLAB crashes on exit after ITK filters run correctly

If `find_package(ITK ...)` is called without `COMPONENTS`, it pulls in
`ITKVtkGlue`, which brings VTK into the link graph.
VTK's static destructors can crash MATLAB on process exit, even when the
ITK filter itself ran and returned a correct result; the crash happens
after the computation succeeds, on teardown.

This is a correctness requirement, not an optimization: `CMakeLists.txt`
scopes `find_package(ITK 5.4 REQUIRED COMPONENTS ...)` to only the ITK
modules mexitk's filters actually need.
Doing so removes VTK from the link graph entirely, and the crash
disappears.
The current component list is:

```
ITKCommon ITKAnisotropicSmoothing ITKThresholding ITKWatersheds
```

If you add a filter that needs a new ITK module, add that module to the
`COMPONENTS` list explicitly; do not switch to an unscoped
`find_package(ITK REQUIRED)` to save the trouble of enumerating modules.
