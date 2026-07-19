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

  // Force the Otsu histogram bounds to the actual image min/max, rather than
  // trusting ITK's per-pixel-type default. On uint8, ITK 5.4's histogram
  // calculator otherwise defaults to the full [0,255] TYPE range instead of
  // the data's own [min,max], which shifts the computed threshold (measured:
  // 33.867 on the type range vs. the correct 32.3125 over this project's
  // reference volume, whose data spans [0,88]) and misclassifies 1087
  // intensity-33 voxels. int32/double/single already auto-range correctly
  // (their ITK default has no fixed type bound to fall back to), so this is
  // a no-op for them, made explicit and uniform anyway rather than relying
  // on a per-type default that happens to already be correct. Fixture-
  // proven: bit-exact against every sot_* fixture after this change.
  filter->SetAutoMinimumMaximum(true);

  // InsideValue/OutsideValue: the ORIGINAL's mask value is a FIXED 255 on
  // every pixel type, not the pixel type's own max -- overturning an
  // earlier, never-fixture-verified assumption ({0,realmax} on
  // double/single) that predates this opcode having any reference capture.
  // Measured directly against every sot_* fixture (double/single/int32/
  // uint8 alike): fixture.output is {0,255} in every case, never
  // {0,realmax}/{0,intmax}. 255 is the same fixed mask value used
  // throughout the original's segmentation opcodes regardless of pixel
  // type (SCT's inferred ReplaceValue=255, SNC/SIC's ReplaceValue default
  // of 255), so SOT hardcodes it too rather than deriving from PixelT.
  //
  // Polarity is also swapped from itk::OtsuThresholdImageFilter's own
  // default: the ORIGINAL assigns 255 to the HIGH side of the threshold
  // (intensity > otsuThreshold), where ITK's own class default assigns its
  // InsideValue to the LOW side. Setting InsideValue=0 (low side) and
  // OutsideValue=255 (high side) reproduces this. Both the fixed-255 value
  // and the polarity swap are fixture-proven bit-exact against every
  // sot_*/sot_polarity_* fixture across all four pixel types.
  filter->SetInsideValue(static_cast<PixelT>(0));
  filter->SetOutsideValue(static_cast<PixelT>(255));
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
  Status GetStatus() const override { return Status::kValidated; }
  const char* StatusNote() const override {
    return "bit-identical to the original on every captured fixture (6 of "
           "6, all four pixel types), asserted by tests/tReferenceExact.m. "
           "InsideValue/OutsideValue are "
           "hardcoded (inside = 0, outside = 255) on every pixel type, "
           "matching the original: the mask value is fixed at 255 "
           "regardless of pixel type, not the pixel type's own max, "
           "overturning an earlier unverified {0,realmax} assumption for "
           "double/single. Polarity is swapped from "
           "itk::OtsuThresholdImageFilter's own default: 255 is assigned to "
           "the HIGH side of the Otsu threshold, matching the original; "
           "ITK's own default assigns its InsideValue to the low side. The "
           "histogram bounds are forced to the image's actual min/max via "
           "SetAutoMinimumMaximum(true), since ITK 5.4's default otherwise "
           "uses the full uint8 TYPE range [0,255] rather than the data "
           "range, shifting the threshold. Two-valued output is {0,255} on "
           "every pixel type. Bins are always set explicitly (ITK base "
           "default is 256). numberOfHistogram below 2 is rejected "
           "(mexitk:SOT:numberOfHistogram): ITK's Otsu calculator crashes "
           "the MATLAB process outright at 0 or 1 bins (measured, not a "
           "catchable exception), since bipartitioning a histogram into "
           "inside/outside needs at least 2 bins.";
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
