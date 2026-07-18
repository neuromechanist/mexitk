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
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists. "
           "uint8/int32 promote to float internally and have no reference. "
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
