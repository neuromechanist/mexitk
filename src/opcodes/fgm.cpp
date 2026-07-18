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

namespace mexitk {
namespace {

// No promotion: the only concept check is HasNumericTraits (satisfied by all
// four supported types; itkGradientMagnitudeImageFilter.h:119), and ITK's own
// GenerateData writes static_cast<OutputPixelType>(std::sqrt(a)) directly
// (itkGradientMagnitudeImageFilter.hxx:177) -- the same native narrowing the
// original's own same-type codegen performed. Reproducing that narrowing
// natively, rather than promoting and clamping, matches the original; it is
// not an inconsistency with the promoted opcodes elsewhere in this file set.
template <typename PixelT>
void RunFgm(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  using FilterType = itk::GradientMagnitudeImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
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
           "same volume by design.";
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
