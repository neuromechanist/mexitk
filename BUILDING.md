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

### Shipping: static ITK (recommended, and what CI uses)

For a **redistributable** binary, build a static, module-pruned ITK and link
that instead:

```sh
./tools/build_itk.sh "$HOME/itk-prefix"          # pinned to ITK 5.4.6
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
      -DITK_DIR="$HOME/itk-prefix/lib/cmake/ITK-5.4"
cmake --build build -j
./tools/check_redistributable.sh matlab/mexitk.mexmaca64
```

`tools/build_itk.sh` sets `BUILD_SHARED_LIBS=OFF`,
`CMAKE_POSITION_INDEPENDENT_CODE=ON` (static archives have to go into a shared
object), `ITK_BUILD_DEFAULT_MODULES=OFF` plus the explicit module list, and
hidden symbol visibility.
Measured at roughly 80 seconds on a 12-core Apple M4 Pro, because the pruned
module set is small; expect a few minutes on a machine with fewer cores.

The difference is not subtle. Linked against Homebrew's ITK, the MEX records
**22 absolute references** into `/opt/homebrew/opt/itk/lib` and loads only on a
machine with that exact ITK at that exact path. Linked against a static ITK, the
same MEX depends only on the C/C++ runtime and MATLAB's own `libmex`/`libmx`:

```
@rpath/libmex.dylib          <- MATLAB's, resolved by MATLAB at load
@rpath/libmx.dylib
/usr/lib/libSystem.B.dylib
/usr/lib/libc++.1.dylib
```

`tools/check_redistributable.sh` enforces exactly that, and is verified to
reject a Homebrew-linked MEX and accept a static one. CI additionally downloads
the artifact onto a runner that never installed ITK and loads it there, because
a build-and-test-on-the-same-machine result cannot prove redistributability.

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
| macOS arm64 | `mexmaca64` | Builds and tested, 34/34, against both Homebrew ITK and a static ITK. Verified on Apple M4 Pro, MATLAB R2025b, ITK 5.4.6, Apple clang 21. The static build is confirmed self-contained (no ITK or package-manager paths recorded). |
| Linux x86_64 | `mexa64` | Builds and tested, 34/34, with static ITK 5.4.6 built from source. Verified in CI on a runner with no ITK installed. **Must be built with GCC 12 or older** (see Troubleshooting). |
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

### Linux: "version `GLIBCXX_3.4.32' not found" when loading the MEX

MATLAB preloads its **own** `libstdc++.so.6` from `sys/os/glnxa64`, and that copy
is usually older than a current distribution's.
R2025b bundles `libstdc++.so.6.0.30`, which provides up to `GLIBCXX_3.4.30`
(measured directly from a real R2025b install, not inferred).
Ubuntu 24.04's default GCC 13 emits references to `GLIBCXX_3.4.32`,
so the MEX compiles and links cleanly and then fails at load:

```
Invalid MEX-file 'mexitk.mexa64': .../sys/os/glnxa64/libstdc++.so.6:
version `GLIBCXX_3.4.32' not found (required by mexitk.mexa64)
```

Build with **GCC 12 or older**, which tops out at exactly `GLIBCXX_3.4.30`:

```sh
sudo apt-get install -y gcc-12 g++-12
export CC=gcc-12 CXX=g++-12      # set before building ITK too, so the ABI matches
```

`tools/check_redistributable.sh` fails the build if the MEX requires a newer
`GLIBCXX` than MATLAB provides, and `CMakeLists.txt` warns at configure time.

**Do not work around this with `-static-libstdc++`.**
It was tried, and it is worse than the problem.
It puts a second libstdc++ in the process, so the C++ exception that
`mexErrMsgIdAndTxt` throws unwinds out of the MEX using the static copy and is
caught by MATLAB's copy, which segfaults the entire MATLAB session.
It appears to work, because it only crashes on the error paths.
