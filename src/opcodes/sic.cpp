// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// SIC - isolated-connected region growing (two seed groups).
// Wraps itk::IsolatedConnectedImageFilter (module ITKRegionGrowing).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkIsolatedConnectedImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunSic(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  // IsolatedConnected needs two seed groups. The registry gives one seedsArray;
  // the first seed point becomes group 1, the second becomes group 2, matching
  // the two-seed shape of the ITK example the original was generated from
  // (Examples/Segmentation/IsolatedConnectedImageFilter.cxx: SetSeed1/SetSeed2).
  // Additional points are silently ignored (unverified against MATITK source).
  // Fewer than two points cannot form the two groups; ITK would throw
  // "Seeds1/Seeds2 container is empty" from Update(), so reject earlier with a
  // specific identifier, based on the raw count (not yet bounds-checked).
  const std::vector<double>& allSeeds = *ctx.seeds;
  if (allSeeds.size() < 2 * kDimension) {
    throw OpcodeError(
        "mexitk:SIC:seeds",
        "SIC needs at least two seed points ([d1 d2 d3 e1 e2 e3 ...]): the "
        "first labels the region to keep, the second the region to isolate "
        "from.");
  }

  // Only the first two points are ever consumed, so only those two are
  // bounds-validated: the original never read anything past the second
  // point, and rejecting an out-of-bounds IGNORED extra point would accept
  // strictly less than the original did. [Overrides this plan's own
  // validate-all default per lead decision.] Slice before calling
  // SeedPointsToIndices so any further, unused triplets never reach the
  // bounds check at all.
  const std::vector<double> consumedSeeds(allSeeds.begin(), allSeeds.begin() + 2 * kDimension);
  const auto indices =
      SeedPointsToIndices(consumedSeeds, input->GetLargestPossibleRegion().GetSize());

  using FilterType = itk::IsolatedConnectedImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);

  const std::vector<double>& p = *ctx.params;
  filter->SetLower(CastParam<PixelT>(p[0], "SIC", "LowerThreshold"));
  filter->SetReplaceValue(CastParam<PixelT>(p[1], "SIC", "ReplaceValue"));
  filter->AddSeed1(indices[0]);
  filter->AddSeed2(indices[1]);
  // The upper isolating threshold is found internally by binary search
  // (GetIsolatedValue); the caller supplies no Upper. GetThresholdingFailed()
  // exists but is deliberately NOT surfaced: the ITK 2.4 example the original
  // was generated from never checks it, so surfacing it would be behaviour the
  // original never had.

  filter->Update();
  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class SicOpcode : public Opcode {
 public:
  const char* Name() const override { return "SIC"; }
  Category GetCategory() const override { return Category::kSegmentation; }
  const char* Description() const override {
    return "Isolated-connected region growing (two seed groups)";
  }
  Status GetStatus() const override { return Status::kValidated; }
  const char* StatusNote() const override {
    return "bit-identical to the original on every fixture with two valid "
           "seed groups (7 of 10 captured, all four pixel types), asserted "
           "by tests/tReferenceExact.m; the other three are a mutual "
           "rejection (a single seed group) and two accepts-more cases (a "
           "dimension-maximum second seed, an ignored out-of-bounds third "
           "seed), see tests/tReferenceRejections.m. "
           "The single seedsArray is split: first point to seed group 1, "
           "second to group 2 (matching the ITK two-seed example); any "
           "further points are ignored and NOT bounds-checked (the original "
           "never read them, so an out-of-range ignored point must not "
           "reject a call the original would have accepted). Fewer than two "
           "points is rejected (mexitk:SIC:seeds). The upper threshold is "
           "found by ITK's internal binary search; the isolation-failure "
           "flag (GetThresholdingFailed) is not surfaced, matching the "
           "example the original was generated from.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"LowerThreshold", nullptr},
        {"ReplaceValue", "255"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunSic<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetSicOpcode() {
  static const SicOpcode op;
  return &op;
}

}  // namespace mexitk
