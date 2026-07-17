# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
# Swartz Center for Computational Neuroscience (SCCN),
# Institute for Neural Computation (INC), UC San Diego.

cmake_minimum_required(VERSION 3.16...4.4)
project(mexitk VERSION 0.1.0 LANGUAGES CXX)

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
  ITKAnisotropicSmoothing  # FCA: CurvatureAnisotropicDiffusionImageFilter
  ITKThresholding          # FOMT: OtsuMultipleThresholds + BinaryThreshold
  ITKWatersheds            # SWS: WatershedImageFilter
)
find_package(ITK 5.4 REQUIRED COMPONENTS ${MEXITK_ITK_COMPONENTS})
include(${ITK_USE_FILE})

set(MEXITK_SOURCES
  src/mexitk.cpp
  src/opcode.cpp
  src/opcodes/fca.cpp
  src/opcodes/fomt.cpp
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

target_include_directories(mexitk PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src ${ITK_INCLUDE_DIRS})

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
