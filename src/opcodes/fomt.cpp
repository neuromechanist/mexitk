// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FOMT - Otsu multiple thresholds.
// Wraps itk::OtsuMultipleThresholdsImageFilter (module ITKThresholding), which
// ITK 2.4 spelled OtsuMultipleThresholdImageFilter (singular).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkBinaryThresholdImageFilter.h"
#include "itkOtsuMultipleThresholdsImageFilter.h"

namespace mexitk {
namespace {

// The Otsu label image holds values 0..numberOfThresholds, so uint8 is ample
// for any sane threshold count; ValidateFomtParams rejects counts that would
// not fit.
using FomtLabelImage = Image3<std::uint8_t>;

constexpr int kMaxThresholds = 254;

template <typename PixelT>
void RunFomt(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  const std::vector<double>& p = *ctx.params;
  const int nThresholds = static_cast<int>(p[0]);
  const int nBins = static_cast<int>(p[1]);

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  using OtsuType = itk::OtsuMultipleThresholdsImageFilter<InImage, FomtLabelImage>;
  typename OtsuType::Pointer otsu = OtsuType::New();
  otsu->SetInput(input);
  otsu->SetNumberOfThresholds(nThresholds);
  otsu->SetNumberOfHistogramBins(nBins);
  otsu->SetLabelOffset(0);
  // ITK exposes ReturnBinMidpoint (bin midpoint vs bin maximum as the reported
  // threshold), defaulting to midpoint only under ITKV4_COMPATIBILITY. Since the
  // reference is an ITK 2.4 build, midpoint looked like the behaviour to match,
  // but it is not: setting it true makes every double/single case diverge from
  // the reference, while the modern default (bin maximum) reproduces them
  // bit-for-bit. Left at the default deliberately; do not "fix" this.
  otsu->SetReturnBinMidpoint(false);
  otsu->Update();

  // N thresholds partition the intensity range into N+1 classes, but the
  // original returns only the lowest N: the top class is computed and silently
  // dropped. This is an off-by-one inherited from the ITK 2.4 example MATITK
  // was generated from, and it is reproduced deliberately, because callers rely
  // on it. NFT's segm_scalp/segm_brain both use not(output), which selects
  // "everything outside class j" and therefore includes the dropped top class.
  // Verified against the reference: coverage is 0.756/0.939/0.941 for N=2/3/4,
  // the shortfall being exactly the top class.
  for (int j = 0; j < nThresholds; ++j) {
    using ThresholdType = itk::BinaryThresholdImageFilter<FomtLabelImage, InImage>;
    typename ThresholdType::Pointer thresh = ThresholdType::New();
    thresh->SetInput(otsu->GetOutput());
    thresh->SetLowerThreshold(static_cast<std::uint8_t>(j));
    thresh->SetUpperThreshold(static_cast<std::uint8_t>(j));
    thresh->SetInsideValue(static_cast<PixelT>(255));
    thresh->SetOutsideValue(static_cast<PixelT>(0));
    thresh->Update();
    ctx.plhs[j] = ExportVolume<PixelT>(thresh->GetOutput());
  }
}

class FomtOpcode : public Opcode {
 public:
  const char* Name() const override { return "FOMT"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Otsu multiple thresholds; returns one 0/255 mask per class";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "bit-identical to the original for double and single at N=2,3,4 "
           "(every threshold count NFT uses), and for uint8 at N=1, "
           "asserted exactly by tests/tFomtReference.m. uint8 at N=2,3,4 "
           "deviates (0.17%/0.38%/0.84% of voxels respectively, measured), "
           "asserted as a bound (not equality) by "
           "tests/tFomtReference.m's uint8DeviationStaysWithinMeasuredBound. "
           "Epic 2 Phase 3 tested and ruled out SOT's own root cause here "
           "(SOT's histogram needed an explicit auto-range call; FOMT's "
           "OtsuMultipleThresholdsImageFilter already auto-ranges to the "
           "image's actual min/max by default, confirmed empirically: "
           "forcing the same bounds explicitly changes nothing) -- the "
           "uint8 multi-threshold deviation is a genuine ITK 2.4-to-5.x "
           "difference in how integral pixel types are binned into the "
           "Otsu histogram, not a mexitk bug. See docs/COMPATIBILITY.md. "
           "Returns N masks for N thresholds, dropping the top Otsu class, "
           "as the original does";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"numberOfThresholds", "less than 5"},
        {"numberOfBins", "128"},
    };
    return kParams;
  }

  // The defining quirk of this opcode: output count is a parameter, and the
  // original requires nargout to match it exactly.
  int OutputCount(const std::vector<double>& params) const override {
    return static_cast<int>(params[0]);
  }

  void Execute(OpContext& ctx) const override {
    const int nThresholds = static_cast<int>((*ctx.params)[0]);
    if (nThresholds < 1 || nThresholds > kMaxThresholds) {
      // A plain mexErrMsgIdAndTxt call here would be caught by mexFunction's
      // outer std::exception handler (Execute() runs inside that try) and its
      // specific identifier discarded in favour of the generic
      // mexitk:exception; throw OpcodeError instead so it survives. See
      // mexitk_common.h.
      throw OpcodeError(
          "mexitk:FOMT:numberOfThresholds",
          FormatMessage("numberOfThresholds must be between 1 and %d; got %d.",
                        kMaxThresholds, nThresholds));
    }
    if (static_cast<int>((*ctx.params)[1]) < 1) {
      throw OpcodeError("mexitk:FOMT:numberOfBins", "numberOfBins must be a positive integer.");
    }
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFomt<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFomtOpcode() {
  static const FomtOpcode op;
  return &op;
}

}  // namespace mexitk
