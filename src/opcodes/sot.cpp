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
           "(ITK base default is 256).";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"numberOfHistogram", "128"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
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
