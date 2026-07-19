# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
# Swartz Center for Computational Neuroscience (SCCN),
# Institute for Neural Computation (INC), UC San Diego.

cmake_minimum_required(VERSION 3.16...4.4)
project(mexitk VERSION 0.4.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# MATLAB is frequently installed outside the default location, so allow
# MATLAB_ROOT_DIR from the environment to seed FindMatlab's Matlab_ROOT_DIR.
if(NOT DEFINED Matlab_ROOT_DIR AND DEFINED ENV{MATLAB_ROOT_DIR})
  set(Matlab_ROOT_DIR "$ENV{MATLAB_ROOT_DIR}")
endif()

find_package(Matlab REQUIRED COMPONENTS MX_LIBRARY MEX_COMPILER)

# The ITK component list is deliberately explicit and minimal. This is a
# correctness requirement, not just a build-time optimisation: resolving ITK
# without COMPONENTS pulls in ITKVtkGlue, and VTK's static destructors crash
# MATLAB on exit even when the filter itself returned a correct result.
# Every module added here must be justified by an opcode that needs it.
set(MEXITK_ITK_COMPONENTS
  ITKCommon                # itk::Image, ImportImageFilter, CastImageFilter
  ITKAnisotropicSmoothing  # FCA, FGAD: (Curvature|Gradient)AnisotropicDiffusionImageFilter
  ITKThresholding          # FOMT, SOT: OtsuMultiple/Otsu + BinaryThreshold
  ITKWatersheds            # SWS: WatershedImageFilter
  ITKRegionGrowing         # SCT, SCC, SIC, SNC: Connected/Confidence/Isolated/NeighborhoodConnected
  ITKSmoothing             # FMEDIAN, FMEAN, FDG, FGA, FBB
  ITKImageIntensity        # FSN: SigmoidImageFilter
  ITKImageGrid             # FF: FlipImageFilter
  ITKImageFeature          # FD, FBL, FLS, FVMI: Derivative/Bilateral/LaplacianRecursiveGaussian/Hessian+Vesselness
  ITKBinaryMathematicalMorphology  # FBD, FBE (BinaryDilate/Erode; BinaryBallStructuringElement
                                   # arrives transitively via ITKMathematicalMorphology)
  ITKDistanceMap           # FDM, FDMV: DanielssonDistanceMapImageFilter
  ITKLabelVoting           # FVBIH: VotingBinaryIterativeHoleFillingImageFilter
  ITKImageGradient         # FGM, FGMRG: GradientMagnitude(RecursiveGaussian)ImageFilter
  ITKCurvatureFlow         # FCF: CurvatureFlowImageFilter
  ITKAntiAlias             # FAAB: AntiAliasBinaryImageFilter (pulls ITKLevelSets transitively)
)
find_package(ITK 5.4 REQUIRED COMPONENTS ${MEXITK_ITK_COMPONENTS})

# Deliberately NOT include(${ITK_USE_FILE}).
# That legacy file calls a global include_directories() with ITK's dependency
# tree, which lands as plain -I. Anything in /opt/homebrew/include then gets
# searched BEFORE the toolchain's own headers, and if any Homebrew package has
# installed a stddef.h there, libc++'s <cstddef> resolves #include_next to the
# wrong file and the build dies with "tried including <stddef.h> but didn't find
# libc++'s <stddef.h>". Whether it breaks depends on which unrelated packages
# happen to be installed, so it passes locally and fails on CI runners.
# ITK 5's imported targets carry their include directories as usage
# requirements, and CMake treats IMPORTED targets' interface includes as
# -isystem, which keeps them after the toolchain headers where they belong.
# Link ${ITK_LIBRARIES} and let the targets do it.

set(MEXITK_SOURCES
  src/mexitk.cpp
  src/opcode.cpp
  src/opcodes/faab.cpp
  src/opcodes/fbb.cpp
  src/opcodes/fbd.cpp
  src/opcodes/fbe.cpp
  src/opcodes/fbl.cpp
  src/opcodes/fbt.cpp
  src/opcodes/fca.cpp
  src/opcodes/fcf.cpp
  src/opcodes/fd.cpp
  src/opcodes/fdg.cpp        # FDG and FGA
  src/opcodes/fdm.cpp        # FDM and FDMV
  src/opcodes/ff.cpp
  src/opcodes/fgad.cpp
  src/opcodes/fgm.cpp
  src/opcodes/fgmrg.cpp
  src/opcodes/fls.cpp
  src/opcodes/fmean.cpp
  src/opcodes/fmedian.cpp
  src/opcodes/fomt.cpp
  src/opcodes/fsn.cpp
  src/opcodes/fvbih.cpp
  src/opcodes/fvmi.cpp
  src/opcodes/scc.cpp
  src/opcodes/sct.cpp
  src/opcodes/sic.cpp
  src/opcodes/snc.cpp
  src/opcodes/sot.cpp
  src/opcodes/sws.cpp
)

# Sources are compiled straight into the MEX target rather than into an
# intermediate static library: opcode registration is explicit (see
# RegisterBuiltinOpcodes) precisely so we never depend on a linker choosing to
# keep an object file whose only purpose is a static initialiser.
matlab_add_mex(
  NAME mexitk
  SRC ${MEXITK_SOURCES}
  LINK_TO ${ITK_LIBRARIES}
  R2018a
)

target_include_directories(mexitk PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

# ITK's imported targets name dependency libraries (fftw3_threads and friends)
# without absolute paths, and ITK_USE_FILE used to supply the search path via a
# global link_directories(). Since we no longer include that file, provide the
# link directories explicitly. This is the half of ITK_USE_FILE that is actually
# needed; the include half is what poisoned the header search order.
target_link_directories(mexitk PRIVATE ${ITK_LIBRARY_DIRS})

if(UNIX AND NOT APPLE)
  # On Linux the MEX must be built with a compiler whose libstdc++ requirements
  # MATLAB can satisfy. MATLAB preloads its OWN libstdc++.so.6 from
  # sys/os/glnxa64, and R2025b bundles 6.0.30, which provides up to
  # GLIBCXX_3.4.30 (measured, not assumed). A MEX built by Ubuntu 24.04's
  # default gcc 13 asks for GLIBCXX_3.4.32 and dies at load with:
  #   version `GLIBCXX_3.4.32' not found (required by mexitk.mexa64)
  # Use gcc/g++ 12 or older (GLIBCXX_3.4.30). CI pins this; see ci.yml.
  #
  # Do NOT "fix" this with -static-libstdc++. It was tried and it is worse: it
  # puts a second libstdc++ in the process, so the C++ exception that
  # mexErrMsgIdAndTxt throws unwinds out of the MEX using our static copy and is
  # caught by MATLAB's, which segfaults the whole session. It looks like it
  # works, because it only crashes on the error paths.
  if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 13)
    message(WARNING
      "Building with GCC ${CMAKE_CXX_COMPILER_VERSION}. The resulting MEX will "
      "require GLIBCXX newer than the libstdc++ MATLAB ships (R2025b provides "
      "up to GLIBCXX_3.4.30) and will fail to load. Use gcc/g++ 12 or older, "
      "e.g. -DCMAKE_CXX_COMPILER=g++-12.")
  endif()
endif()

if(APPLE)
  # FindMatlab.cmake links every MEX against extern/lib/<arch>/cppMexFunction.map
  # and adds `-Wl,-U,_mexCreateMexFunction` (and friends) so a C-API MEX stays
  # loadable by a MATLAB that also supports the C++ MEX API. Apple's ld-prime
  # (default since Xcode 15 on arm64) ignores `-U` for these and fails with
  # "symbol(s) not found for architecture arm64", although the symbols are never
  # called. The classic linker honours it. -ld_classic is deprecated by Apple;
  # revisit when MathWorks updates FindMatlab/mex for the new linker.
  target_link_options(mexitk PRIVATE -Wl,-ld_classic)
endif()

# Place the built MEX where the MATLAB tests and users expect it.
set_target_properties(mexitk PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/matlab"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/matlab"
)

enable_testing()
if(Matlab_MAIN_PROGRAM)
  add_test(NAME matlab_unittests
    COMMAND ${Matlab_MAIN_PROGRAM} -batch
            "addpath('${CMAKE_CURRENT_SOURCE_DIR}/matlab'); exit(run_mexitk_tests('${CMAKE_CURRENT_SOURCE_DIR}'))")
endif()
