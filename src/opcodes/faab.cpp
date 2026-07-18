// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FAAB - anti-alias binary level-set smoothing.
// Wraps itk::AntiAliasBinaryImageFilter (module ITKAntiAlias).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkAntiAliasBinaryImageFilter.h"
#include "itkCastImageFilter.h"
#include "itkClampImageFilter.h"

#include <type_traits>

namespace mexitk {
namespace {

// Concept checks are DoubleConvertibleToOutputCheck + InputOStreamWritableCheck
// only (both satisfied by integral types) -- documented, not concept-enforced.
// The header's own OUTPUT/IMPORTANT paragraphs: "The filter will output a
// level set image of real, signed values ... Values outside the zero level
// set are negative and values inside the zero level set are positive"
// and "The output image type you use to instantiate this filter should be a
// real valued scalar type. In other words: doubles or floats"
// (itkAntiAliasBinaryImageFilter.h:82-90). The output being genuinely signed
// means the integral clamp-back path saturates the ENTIRE outside-negative
// half of the level set to 0 on uint8 -- a large, deliberate, documented
// effect (see StatusNote), not an edge case.
template <typename PixelT>
using FaabRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunFaab(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = FaabRealType<PixelT>;
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

  using FilterType = itk::AntiAliasBinaryImageFilter<RealImage, RealImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(real);
  filter->SetMaximumRMSError(p[0]);
  // SetNumberOfIterations is IdentifierType on the FiniteDifferenceImageFilter
  // base, same as FCF; do NOT use the deprecated SetMaximumIterations alias
  // (itkWarns and forwards to this same setter).
  filter->SetNumberOfIterations(
      CastParam<itk::IdentifierType>(p[1], "FAAB", "numberOfIterations"));
  filter->SetNumberOfLayers(CastParam<unsigned int>(p[2], "FAAB", "numberOfLayers"));
  filter->Update();

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(filter->GetOutput());
  } else {
    // See FcaRealType's comment in fca.cpp for the saturation rationale.
    // Here it is a large, expected effect, not an edge case: the entire
    // outside-negative half of the signed level set saturates to 0.
    using ClampOut = itk::ClampImageFilter<RealImage, InImage>;
    typename ClampOut::Pointer back = ClampOut::New();
    back->SetInput(filter->GetOutput());
    back->Update();
    ctx.plhs[0] = ExportVolume<PixelT>(back->GetOutput());
  }
}

class FaabOpcode : public Opcode {
 public:
  const char* Name() const override { return "FAAB"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Anti-alias binary level-set smoothing";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists. "
           "Output is a signed level-set field (positive inside the surface, "
           "negative outside, zero crossing at the estimated surface); "
           "uint8/int32 input promotes to float and the signed output "
           "saturates on export, so on uint8 everything outside the surface "
           "becomes 0.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"maximumRMSError", "0.01"},
        {"numberOfIterations", "50"},
        {"numberOfLayers", "2"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFaab<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFaabOpcode() {
  static const FaabOpcode op;
  return &op;
}

}  // namespace mexitk
