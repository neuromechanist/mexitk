#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
# Swartz Center for Computational Neuroscience (SCCN),
# Institute for Neural Computation (INC), UC San Diego.
#
# Build a static, module-pruned ITK suitable for linking into a redistributable
# MEX file.
#
# Usage:
#   tools/build_itk.sh <install-prefix> [itk-version]
#
# Then point mexitk at it:
#   cmake -S . -B build -DCMAKE_PREFIX_PATH=<install-prefix>
#
# Why static: a MEX linked against a shared ITK records absolute paths to the
# build machine's ITK (a Homebrew-linked build had 22 references into
# /opt/homebrew/opt/itk/lib) and fails to load anywhere else. On Linux the same
# thing surfaces as "libitkNetlibSlatec-5.4.so.1: cannot open shared object
# file" at MEX load. Linking ITK statically makes the MEX self-contained, which
# is the entire point of shipping a binary.
#
# Why pruned: this is a correctness requirement, not a size optimisation.
# Resolving ITK without an explicit module list pulls in ITKVtkGlue, and VTK's
# static destructors crash MATLAB on exit even when the filter returned a
# correct result. Only add a module here when an opcode actually needs it, and
# keep it in sync with MEXITK_ITK_COMPONENTS in CMakeLists.txt.

set -euo pipefail

PREFIX="${1:?usage: build_itk.sh <install-prefix> [itk-version]}"
ITK_VERSION="${2:-5.4.6}"

# Keep in sync with MEXITK_ITK_COMPONENTS in CMakeLists.txt.
# ITKCommon is part of ITK's core and is always built, so it is not listed here.
ITK_MODULES=(
  Module_ITKAnisotropicSmoothing=ON  # FCA, FGAD
  Module_ITKThresholding=ON          # FOMT
  Module_ITKWatersheds=ON            # SWS
  Module_ITKSmoothing=ON             # FMEDIAN, FMEAN, FDG, FGA, FBB
  Module_ITKImageIntensity=ON        # FSN
  Module_ITKImageGrid=ON             # FF
  Module_ITKImageFeature=ON          # FD, FBL, FLS, FVMI
  Module_ITKBinaryMathematicalMorphology=ON  # FBD, FBE
  Module_ITKDistanceMap=ON                   # FDM, FDMV
  Module_ITKLabelVoting=ON                   # FVBIH
  Module_ITKRegionGrowing=ON                 # SCT, SCC, SIC, SNC
  Module_ITKImageGradient=ON         # FGM, FGMRG
  Module_ITKCurvatureFlow=ON         # FCF, FMMCF
  Module_ITKAntiAlias=ON             # FAAB
  Module_ITKFastMarching=ON          # SFM
  Module_ITKLevelSets=ON             # SGAC, SLLS, SSDLS
  Module_ITKPDEDeformableRegistration=ON  # RD
  Module_ITKTransform=ON             # RTPS
)

WORK="${ITK_BUILD_WORKDIR:-$(mktemp -d)}"
SRC="${WORK}/InsightToolkit-${ITK_VERSION}"
BUILD="${WORK}/itk-build"
TARBALL="${WORK}/itk-${ITK_VERSION}.tar.gz"
URL="https://github.com/InsightSoftwareConsortium/ITK/releases/download/v${ITK_VERSION}/InsightToolkit-${ITK_VERSION}.tar.gz"

mkdir -p "${WORK}"

if [ ! -d "${SRC}" ]; then
  echo "==> Fetching ITK ${ITK_VERSION}"
  curl -fsSL -o "${TARBALL}" "${URL}"
  tar xzf "${TARBALL}" -C "${WORK}"
fi

echo "==> Configuring static ITK ${ITK_VERSION} -> ${PREFIX}"
cmake_args=(
  -S "${SRC}" -B "${BUILD}"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="${PREFIX}"
  # The three settings that make the result linkable into a MEX:
  -DBUILD_SHARED_LIBS=OFF            # static archives, no runtime .so/.dylib
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON  # static archives go into a shared object
  -DITK_BUILD_DEFAULT_MODULES=OFF    # prune; see the VTK note above
  -DBUILD_TESTING=OFF
  -DBUILD_EXAMPLES=OFF
  # A MEX must export exactly mexFunction. Hiding everything else keeps ITK's
  # symbols out of the MEX's dynamic symbol table.
  -DCMAKE_CXX_VISIBILITY_PRESET=hidden
  -DCMAKE_VISIBILITY_INLINES_HIDDEN=ON
)
for m in "${ITK_MODULES[@]}"; do
  cmake_args+=("-D${m}")
done
cmake "${cmake_args[@]}"

echo "==> Building"
cmake --build "${BUILD}" -j "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)" --target install

echo "==> Installed static ITK to ${PREFIX}"
find "${PREFIX}" -name 'libITK*' -maxdepth 3 2>/dev/null | head -5
echo "==> Shared libraries in prefix (expect none):"
find "${PREFIX}" \( -name '*.so*' -o -name '*.dylib' \) 2>/dev/null | head -5
echo "(empty above means the build is genuinely static)"
