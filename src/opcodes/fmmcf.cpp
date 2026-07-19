// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FMMCF - min/max curvature flow.
// Wraps itk::MinMaxCurvatureFlowImageFilter (module ITKCurvatureFlow).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkCastImageFilter.h"
#include "itkMinMaxCurvatureFlowImageFilter.h"

#include <cmath>
#include <type_traits>

namespace mexitk {
namespace {

// MinMaxCurvatureFlowImageFilter derives from CurvatureFlowImageFilter and
// inherits its "output image pixels [must be] of a floating point type"
// requirement (itkMinMaxCurvatureFlowImageFilter.h:58-60, quoting the base
// class); see FcfRealType's comment in fcf.cpp for the same finding on the
// sibling filter. Promoted per that precedent.
template <typename PixelT>
using FmmcfRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunFmmcf(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = FmmcfRealType<PixelT>;
  using RealImage = Image3<RealT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  typename RealImage::Pointer real;
  if constexpr (std::is_same<PixelT, RealT>::value) {
    real = input;
  } else {
    using CastIn = itk::CastImageFilter<InImage, RealImage>;
    typename CastIn::Pointer cast = CastIn::New();
    cast->SetInput(input);
    cast->Update();
    real = cast->GetOutput();
  }

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::MinMaxCurvatureFlowImageFilter<RealImage, RealImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(real);
  // SetNumberOfIterations is inherited from CurvatureFlowImageFilter, which
  // itself inherits it from FiniteDifferenceImageFilter as IdentifierType,
  // not unsigned int; same finding as FCF (see the comment in fcf.cpp),
  // re-verified directly against this class's own inheritance chain.
  filter->SetNumberOfIterations(
      CastParam<itk::IdentifierType>(p[0], "FMMCF", "numberOfIterations"));
  // Same ill-posed-backward-flow rationale as FCF's timeStep guard: a
  // negative timeStep runs the flow backward in time. timeStep == 0 stays
  // accepted as a defined no-op. Non-finite (NaN/Inf) is rejected too, not
  // just negative: measured directly, a NaN timeStep crashes the whole
  // MATLAB process with a SIGBUS inside MinMaxCurvatureFlowFunction::
  // ComputeThreshold's Dispatch<3> path, not merely a silent bad result --
  // the same severity class as the SWS-overthresholding and SOT-histogram
  // crash guards (see docs/COMPATIBILITY.md deviations 1 and 9). A plain
  // `< 0.0` comparison does not catch this: NaN compares false against
  // every ordered relational operator, so it would sail through unrejected.
  if (!std::isfinite(p[1]) || p[1] < 0.0) {
    throw OpcodeError("mexitk:FMMCF:timeStep",
                      "timeStep must be finite and not negative.");
  }
  filter->SetTimeStep(p[1]);
  // StencilRadius is RadiusValueType, declared locally on this class
  // (itkMinMaxCurvatureFlowImageFilter.h:112-117) as an unsigned integer;
  // CastParam's integral path rejects a negative value.
  filter->SetStencilRadius(
      CastParam<typename FilterType::RadiusValueType>(p[2], "FMMCF", "stencilRadius"));
  filter->Update();

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(filter->GetOutput());
  } else {
    // See FcaRealType's comment in fca.cpp for the saturation rationale.
    ctx.plhs[0] = ClampExport<PixelT, RealT>(filter->GetOutput());
  }
}

class FmmcfOpcode : public Opcode {
 public:
  const char* Name() const override { return "FMMCF"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Min/max curvature flow (edge-preserving smoothing)";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "does not reproduce the original bit-for-bit on the one "
           "captured fixture (fmmcf_10_0p0625_1_double: "
           "numberOfIterations=10, timeStep=0.0625, stencilRadius=1, "
           "double): measured RMS 1.597, max-abs 43.25, on 147675/442368 "
           "voxels (33%), asserted by tests/tReferenceBounded.m. This is "
           "far above the floating-point noise floor other double-input "
           "opcodes show (e.g. FCF's own double residual is RMS ~1e-15), "
           "so it is a real MinMaxCurvatureFlowFunction numerics drift "
           "between ITK 2.4 and 5.x -- the same class of upstream "
           "evolution as FCA/SWS -- not a wiring bug: verified directly "
           "that numberOfIterations=0 is an exact no-op and that 1 vs 2 "
           "iterations produce meaningfully different output (max diff "
           "13.1), so the parameter is genuinely wired and the deviation "
           "compounds with iteration count like FCF's own. No fixture "
           "exists for single/uint8/int32 or other parameter values, so "
           "no agreement claim is made for them; uint8/int32 promote to "
           "float internally and ClampExport back, the same pattern as "
           "FCF (see fcf.cpp).";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"numberOfIterations", "10"},
        {"timeStep", "0.0625"},
        {"stencilRadius", "1"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFmmcf<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFmmcfOpcode() {
  static const FmmcfOpcode op;
  return &op;
}

}  // namespace mexitk
