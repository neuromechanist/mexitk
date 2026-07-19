// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FGMRG - gradient magnitude via recursive Gaussian derivative.
// Wraps itk::GradientMagnitudeRecursiveGaussianImageFilter (module ITKImageGradient).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkCastImageFilter.h"
#include "itkGradientMagnitudeRecursiveGaussianImageFilter.h"

#include <cmath>
#include <type_traits>

namespace mexitk {
namespace {

// The filter has no float concept check (only InputHasNumericTraitsCheck,
// itkGradientMagnitudeRecursiveGaussianImageFilter.h:133), but it hardwires
// InternalRealType = float internally (:75) and its final stage is a raw
// SqrtImageFilter functor cast into whatever output type is instantiated
// (:85). Promoting integral input to float and clamping back on export
// replaces that undefined-adjacent narrowing cast with defined saturation,
// the same policy already applied elsewhere (deviation 8).
template <typename PixelT>
using FgmrgRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunFgmrg(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = FgmrgRealType<PixelT>;
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

  using FilterType = itk::GradientMagnitudeRecursiveGaussianImageFilter<RealImage, RealImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(real);
  filter->SetSigma(p[0]);
  // NormalizeAcrossScale is left at its ITK default (false): the registry
  // exposes no such parameter, so the constructor default applies.
  filter->Update();

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(filter->GetOutput());
  } else {
    // See FcaRealType's comment in fca.cpp for the saturation rationale.
    ctx.plhs[0] = ClampExport<PixelT, RealT>(filter->GetOutput());
  }
}

class FgmrgOpcode : public Opcode {
 public:
  const char* Name() const override { return "FGMRG"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Gradient magnitude (recursive Gaussian derivative)";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "bit-identical to the original on int32/uint8 at sigma=2 (see "
           "tests/tReferenceExact.m); every other captured combination "
           "(double at sigma 1/2/4, single at sigma 2) has a residual at "
           "the floating-point noise floor (RMS order 1e-7 to 1e-8), "
           "asserted by tests/tReferenceBounded.m. Not classified as "
           "validated overall because of the double/single residual. "
           "Distinct algorithm from FGM (recursive Gaussian derivative vs "
           "central differences); the two return different output on the "
           "same volume by design.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"sigma", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    // Same rationale as FLS's own sigma guard (shared RecursiveGaussian
    // base): sigma <= 0 is already caught by ITK's own exception
    // (mexitk:itkException), unchanged here. That guard's `<= 0.0` does
    // not catch NaN or +Inf (confirmed empirically: silent all-NaN
    // output, no exception) -- the actual pre-PR gap this guard closes.
    // `-Inf` is different: `-Inf <= 0.0` is true, so ITK's own exception
    // already caught it pre-PR too (as mexitk:itkException); this guard
    // now intercepts it first instead, since it runs before RunFgmrg ever
    // dispatches to the filter, so -Inf now surfaces as
    // mexitk:FGMRG:sigma -- a deliberate, disclosed identifier change,
    // not a new rejection.
    if (!std::isfinite((*ctx.params)[0])) {
      throw OpcodeError("mexitk:FGMRG:sigma", "sigma must be finite.");
    }
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFgmrg<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFgmrgOpcode() {
  static const FgmrgOpcode op;
  return &op;
}

}  // namespace mexitk
