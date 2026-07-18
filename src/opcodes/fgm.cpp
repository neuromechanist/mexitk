// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FGM - gradient magnitude (central differences).
// Wraps itk::GradientMagnitudeImageFilter (module ITKImageGradient).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkGradientMagnitudeImageFilter.h"

#include <type_traits>

namespace mexitk {
namespace {

// The only concept check is HasNumericTraits (satisfied by all four
// supported types; itkGradientMagnitudeImageFilter.h:119). No PIXEL-TYPE
// promotion happens here (float/double still run fully native, and no
// integral input is cast to float first): the computation itself is
// unchanged for every type. What changed is only how the result gets
// written into the output pixel type.
//
// GradientMagnitudeImageFilter's internal accumulation is
// NumericTraits<InputPixelType>::RealType (itkGradientMagnitudeImageFilter.h:63),
// which is double for BOTH uint8 and int32 (itkNumericTraits.h's unsigned
// char and int specializations). ITK's own GenerateData then writes
// static_cast<OutputPixelType>(std::sqrt(a)) with no clamping
// (itkGradientMagnitudeImageFilter.hxx:177): when the filter is instantiated
// natively (output type == input type, the original code here), that is a
// raw double-to-integral narrowing cast. For uint8 this narrowing is
// provably safe: this central-difference formula's worst case on an 8-bit
// input is bounded at ~220.9, under uint8's 255 max, so the native uint8
// path was never actually undefined. For int32 the same formula's worst
// case exceeds int32's own max, so the native path WAS undefined behaviour
// for int32 -- the reason for this change.
//
// Rather than special-case only int32, both integral types now instantiate
// the filter's OUTPUT at double (matching its own internal RealType exactly
// -- this is not promoting a different pixel type through the pipeline, it
// is simply not letting the filter's own final write narrow before mexitk
// gets a chance to clamp it) and export through ClampExport, which performs
// the identical static_cast<PixelT>(v) as before for every in-range value.
// uint8 and in-range int32 results are therefore bit-identical to the
// previous native-narrowing code; verified empirically with a before/after
// bit-compare on uint8 and int32 mri-derived volumes during development.
template <typename PixelT>
void RunFgm(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  if constexpr (std::is_floating_point<PixelT>::value) {
    using FilterType = itk::GradientMagnitudeImageFilter<InImage, InImage>;
    typename FilterType::Pointer filter = FilterType::New();
    filter->SetInput(input);
    filter->Update();
    ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
  } else {
    using DoubleImage = Image3<double>;
    using FilterType = itk::GradientMagnitudeImageFilter<InImage, DoubleImage>;
    typename FilterType::Pointer filter = FilterType::New();
    filter->SetInput(input);
    filter->Update();
    ctx.plhs[0] = ClampExport<PixelT, double>(filter->GetOutput());
  }
}

class FgmOpcode : public Opcode {
 public:
  const char* Name() const override { return "FGM"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Gradient magnitude (central differences)";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists. "
           "Distinct algorithm from FGMRG (central differences vs recursive "
           "Gaussian derivative); the two return different output on the "
           "same volume by design. uint8/int32 export through a saturating "
           "cast (int32's native narrowing cast could overflow; uint8's "
           "could not, and is bit-identical before and after this guard).";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {};
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFgm<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFgmOpcode() {
  static const FgmOpcode op;
  return &op;
}

}  // namespace mexitk
