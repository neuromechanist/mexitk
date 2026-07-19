// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// SFM - fast marching (arrival-time map from seed(s)).
// Wraps itk::FastMarchingImageFilter (module ITKFastMarching). Confirmed
// (itkFastMarchingImageFilter.h:134) to NOT inherit FastMarchingImageFilterBase
// / FastMarchingBase, so the ITK-2.4-era API (SetTrialPoints/SetStoppingValue)
// is fully intact.

#include "mexitk_common.h"
#include "opcode.h"

#include "itkCastImageFilter.h"
#include "itkFastMarchingImageFilter.h"

#include <type_traits>

namespace mexitk {
namespace {

// FastMarchingImageFilter's own concept checks (itkFastMarchingImageFilter.h:
// 377-384) only require the level-set (output) pixel type to be convertible
// from/to double and stream-writable, which an integral type technically
// satisfies -- but the fixture evidence (sfm_stop100_seedS1_double's
// LargeValue sentinel matches NumericTraits<double>::max()/2 exactly, proven
// by direct comparison, not assumed) shows the original ran double natively.
// Promoting integral input to float mirrors the FCF/FMMCF precedent and
// keeps the (very large) sentinel value's narrowing export saturating and
// defined via ClampExport, instead of an undefined-behaviour cast.
template <typename PixelT>
using SfmRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunSfm(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = SfmRealType<PixelT>;
  using RealImage = Image3<RealT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  typename RealImage::Pointer speed;
  if constexpr (std::is_same<PixelT, RealT>::value) {
    speed = input;
  } else {
    using CastIn = itk::CastImageFilter<InImage, RealImage>;
    typename CastIn::Pointer cast = CastIn::New();
    cast->SetInput(input);
    cast->Update();
    speed = cast->GetOutput();
  }

  using FilterType = itk::FastMarchingImageFilter<RealImage, RealImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(speed);

  // Trial points: one per seed, value 0.0 -- the classic ITK FastMarching
  // example's own convention, and consistent with the fixture (the sole
  // 0-valued output voxel is exactly the seed voxel, verified directly, no
  // axis swap). Seeds map onto ITK axes with no transpose, same as every
  // other seeded opcode; see SeedPointsToIndices. An empty seed list is
  // defined behaviour, consistent with SCT/SNC/SCC: no trial points are
  // inserted, the main marching loop's heap is empty from the start, and
  // Initialize() has already set every output voxel to LargeValue, so the
  // call returns a fully allocated, all-sentinel output rather than
  // erroring (verified directly against itkFastMarchingImageFilter.hxx's
  // Initialize()/GenerateData()).
  using NodeContainer = typename FilterType::NodeContainer;
  using NodeType = typename FilterType::NodeType;
  typename NodeContainer::Pointer trial = NodeContainer::New();
  NodeType node;
  node.SetValue(0.0);
  typename NodeContainer::ElementIdentifier id = 0;
  for (const auto& idx :
       SeedPointsToIndices(*ctx.seeds, input->GetLargestPossibleRegion().GetSize())) {
    node.SetIndex(idx);
    trial->InsertElement(id++, node);
  }
  filter->SetTrialPoints(trial);

  // SetOutputSize/SetOutputOrigin/SetOutputSpacing are deliberately NOT
  // called: per itkFastMarchingImageFilter.h:103-113 and its own
  // GenerateOutputInformation() (verified directly in
  // itkFastMarchingImageFilter.hxx), the output geometry is copied from the
  // speed image whenever one is supplied via SetInput() and
  // OverrideOutputInformation stays false (its default) -- both true here
  // -- so the 16^3 OutputRegion this class would otherwise default to never
  // applies. NormalizationFactor stays at its own default (1.0): the
  // fixture's LargeValue sentinel (NumericTraits<double>::max()/2, matched
  // exactly) is independent of it, and nothing in the registry or the
  // fixture evidence suggests the original set it to anything else.
  const std::vector<double>& p = *ctx.params;
  filter->SetStoppingValue(CastParam<double>(p[0], "SFM", "stoppingTime"));
  filter->Update();

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(filter->GetOutput());
  } else {
    ctx.plhs[0] = ClampExport<PixelT, RealT>(filter->GetOutput());
  }
}

class SfmOpcode : public Opcode {
 public:
  const char* Name() const override { return "SFM"; }
  Category GetCategory() const override { return Category::kSegmentation; }
  const char* Description() const override {
    return "Fast marching (raw arrival-time map from seed(s))";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "does not reproduce the original bit-for-bit on the one "
           "captured fixture (sfm_stop100_seedS1_double: stoppingTime=100, "
           "seed [70 50 14], double): measured RMS 6.1e-15, max-abs "
           "9.0e-14, on 168112/442368 voxels, asserted by "
           "tests/tReferenceBounded.m -- the floating-point noise floor "
           "(the same order of magnitude as e.g. FCF's own double "
           "residual), consistent with priority-queue/op-order "
           "non-associativity in the marching update, not an algorithmic "
           "difference. The 270838 sentinel-valued voxels (61.22% of the "
           "volume, ITK's LargeValue = NumericTraits<double>::max()/2, a "
           "constant assigned during Initialize rather than computed) are "
           "verified to match EXACTLY, both count and membership -- every "
           "differing voxel is a genuinely computed, reached arrival time. "
           "The original returns this RAW arrival-time map with the "
           "sentinel intact -- no thresholding, no rescale, no downstream "
           "step. No fixture exists for single/uint8/int32 or for other "
           "parameters/seeds, so no agreement claim is made for them; "
           "uint8/int32 promote to float internally and ClampExport back, "
           "saturating the sentinel to the integral type's own max. An "
           "empty seed list returns a fully allocated, all-sentinel "
           "output rather than erroring (verified directly, not "
           "fixture-covered).";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"stoppingTime", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunSfm<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetSfmOpcode() {
  static const SfmOpcode op;
  return &op;
}

}  // namespace mexitk
