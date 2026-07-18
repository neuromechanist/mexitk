// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// SOT - single Otsu threshold.
// Wraps itk::OtsuThresholdImageFilter (module ITKThresholding).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkOtsuThresholdImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunSot(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  using FilterType = itk::OtsuThresholdImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);

  const std::vector<double>& p = *ctx.params;
  // Always set bins explicitly: MATITK's default hint is 128 but ITK's base
  // (HistogramThresholdImageFilter) default is 256, so an unset value would
  // silently disagree with the original's intent.
  filter->SetNumberOfHistogramBins(
      CastParam<unsigned int>(p[0], "SOT", "numberOfHistogram"));
  // InsideValue and OutsideValue are left at ITK's defaults (inside = pixel
  // type max, outside = 0). The registry exposes neither, and both the ITK 2.4
  // OtsuThresholdImageFilter constructor and the 5.4 HistogramThresholdImageFilter
  // base default to exactly this. Threshold polarity is also unchanged
  // 2.4->5.4: intensity in [min, otsuThreshold] receives InsideValue, so the
  // LOW side of the threshold becomes inside. Consequence: two-valued output
  // {0, typemax} -> {0,255} on uint8, but {0, realmax} on double/single. This
  // is ITK's faithful default, not a bug.
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class SotOpcode : public Opcode {
 public:
  const char* Name() const override { return "SOT"; }
  Category GetCategory() const override { return Category::kSegmentation; }
  const char* Description() const override {
    return "Otsu threshold; returns a two-valued image";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists. "
           "InsideValue and OutsideValue are ITK's defaults (inside = "
           "pixel-type max, outside = 0), matching the ITK 2.4 constructor; "
           "the low side of the Otsu threshold (intensity <= threshold) "
           "becomes inside. Two-valued output is {0,255} on uint8 but "
           "{0,realmax} on double/single. Bins are always set explicitly "
           "(ITK base default is 256). numberOfHistogram below 2 is "
           "rejected (mexitk:SOT:numberOfHistogram): ITK's Otsu calculator "
           "crashes the MATLAB process outright at 0 or 1 bins (measured, "
           "not a catchable exception), since bipartitioning a histogram "
           "into inside/outside needs at least 2 bins.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"numberOfHistogram", "128"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    // ITK's Otsu histogram calculator crashes the whole MATLAB process (not
    // a catchable itk::ExceptionObject) at 0 or 1 histogram bins: measured
    // directly, a bus error / SIGSEGV inside
    // itk::Statistics::Histogram::GetIndex. Reject before it ever reaches
    // ITK, the same severity class as the SWS overthresholding deviation
    // (docs/COMPATIBILITY.md deviation #1).
    //
    // Written as !(x >= 2.0) rather than (x < 2.0) deliberately: NaN
    // compares false against every ordered relational operator, so
    // (NaN < 2.0) is false and would fall through to CastParam's generic
    // mexitk:paramRange instead of this opcode-specific guard. !(NaN >= 2.0)
    // is true, so this form catches NaN under the same identifier as every
    // other too-few-bins case.
    if (!((*ctx.params)[0] >= 2.0)) {
      throw OpcodeError("mexitk:SOT:numberOfHistogram",
                        "numberOfHistogram must be at least 2.");
    }
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunSot<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetSotOpcode() {
  static const SotOpcode op;
  return &op;
}

}  // namespace mexitk
