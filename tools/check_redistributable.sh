#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
# Swartz Center for Computational Neuroscience (SCCN),
# Institute for Neural Computation (INC), UC San Diego.
#
# Fail if a built MEX is not redistributable.
#
# Usage: tools/check_redistributable.sh <path-to-mex>
#
# A MEX linked against a shared ITK records absolute paths to the build
# machine's ITK and loads nowhere else. On macOS a Homebrew-linked build had 22
# references into /opt/homebrew/opt/itk/lib; on Linux the same mistake surfaces
# at load as "libitkNetlibSlatec-5.4.so.1: cannot open shared object file".
# Both look fine on the machine that built them, which is exactly why this check
# exists: a build-and-test-on-the-same-runner job proves nothing about
# redistributability, because the toolchain is still sitting right there.
#
# A correctly built (static ITK) MEX depends only on the C/C++ runtime and on
# MATLAB's own libmex/libmx, which MATLAB resolves itself at load time.

set -euo pipefail

MEX="${1:?usage: check_redistributable.sh <path-to-mex>}"
[ -f "$MEX" ] || { echo "FAIL: $MEX does not exist"; exit 1; }

echo "==> Checking $MEX ($(du -h "$MEX" | cut -f1))"

case "$(uname -s)" in
  Darwin)
    DEPS="$(otool -L "$MEX" | tail -n +2 | awk '{print $1}')"
    # LC_RPATH entries can also smuggle in a build-time prefix.
    DEPS="$DEPS
$(otool -l "$MEX" | awk '/LC_RPATH/{f=1} f&&/path /{print $2; f=0}')"
    ;;
  Linux)
    # DT_NEEDED is what the loader will look for; RPATH/RUNPATH is where it
    # will look. Both must be free of build-time paths. Deliberately not `ldd`,
    # which reports what resolves *here* rather than what is recorded.
    DEPS="$(objdump -p "$MEX" | awk '/NEEDED/{print $2}')
$(objdump -p "$MEX" | awk '/R(UN)?PATH/{print $2}')"
    ;;
  *)
    echo "FAIL: unsupported platform $(uname -s)"; exit 1 ;;
esac

echo "--- recorded dependencies and search paths ---"
echo "$DEPS" | sed '/^[[:space:]]*$/d' | sed 's/^/    /'
echo "---"

# matlab_add_mex() records the build machine's MATLAB directories as rpaths.
# That is expected and harmless: MATLAB has already loaded libmex/libmx into the
# process before it opens a MEX, so the loader matches them by install name
# (@rpath/libmex.dylib) against the already-loaded images and never consults
# these paths. Excluding them is not a loophole -- ITK is the thing that must
# not be needed, and the clean-runner load test below is what actually proves
# it. Without this exclusion the check false-fails on CI, where setup-matlab
# installs MATLAB under a runner-specific path.
CHECKABLE="$(echo "$DEPS" | grep -viE 'matlab|/extern/bin/' || true)"

status=0

# 1. No ITK at all. Static linking means ITK must not appear as a runtime
#    dependency; if it does, the build silently used a shared ITK.
#    Anchored to a `lib` prefix on purpose: ITK's libraries are libITKCommon,
#    libitkNetlibSlatec and so on, whereas a bare 'itk' match also hits our own
#    "mexitk.mexmaca64" self-reference and fails every correct build.
if echo "$CHECKABLE" | grep -qiE '(^|/)lib[A-Za-z0-9_]*itk'; then
  echo "FAIL: the MEX still depends on ITK at runtime; ITK was not linked statically."
  status=1
fi

# 2. No absolute paths into any package manager or build-time prefix.
if echo "$CHECKABLE" | grep -qE '/opt/homebrew|/usr/local/opt|/opt/local|itk-install|itk-static|/prefix/'; then
  echo "FAIL: the MEX references a build-time prefix; it will not load elsewhere."
  status=1
fi

# 3. Linux only: the MEX must not require a newer libstdc++ than MATLAB ships.
#    MATLAB preloads its own libstdc++.so.6 from sys/os/glnxa64. R2025b bundles
#    6.0.30, which provides up to GLIBCXX_3.4.30 (measured directly from a real
#    R2025b install, not assumed). Build with gcc 13 and the MEX asks for
#    GLIBCXX_3.4.32 and dies at load, even though checks 1 and 2 both pass and
#    the file looks perfect. This is the exact failure that got through before,
#    so it gets its own gate rather than relying on the load test to catch it.
if [ "$(uname -s)" = "Linux" ]; then
  MAX_ALLOWED="${MEXITK_MAX_GLIBCXX:-3.4.30}"
  REQUIRED="$(objdump -T "$MEX" 2>/dev/null \
    | grep -oE 'GLIBCXX_[0-9]+\.[0-9]+\.[0-9]+' | sed 's/GLIBCXX_//' \
    | sort -V | tail -1 || true)"
  if [ -n "$REQUIRED" ]; then
    echo "    highest GLIBCXX required: $REQUIRED (MATLAB provides up to $MAX_ALLOWED)"
    if [ "$(printf '%s\n%s\n' "$MAX_ALLOWED" "$REQUIRED" | sort -V | tail -1)" != "$MAX_ALLOWED" ]; then
      echo "FAIL: the MEX requires GLIBCXX_$REQUIRED but MATLAB's bundled libstdc++"
      echo "      only provides up to GLIBCXX_$MAX_ALLOWED. It will fail at load."
      echo "      Build with gcc/g++ 12 or older. Do not use -static-libstdc++:"
      echo "      it segfaults MATLAB on the error paths (two libstdc++ copies)."
      status=1
    fi
  fi
fi

if [ "$status" -eq 0 ]; then
  echo "PASS: no ITK runtime dependency and no build-prefix paths."
  echo "      (This proves what is *recorded* in the binary. Loading it in"
  echo "       MATLAB on a runner that never installed ITK is the other half;"
  echo "       see the verify-clean-runner job in .github/workflows/.)"
fi
exit "$status"
