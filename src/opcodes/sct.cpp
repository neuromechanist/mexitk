// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// SCT - connected-threshold region growing.
// Wraps itk::ConnectedThresholdImageFilter (module ITKRegionGrowing).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkConnectedThresholdImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunSct(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  using FilterType = itk::ConnectedThresholdImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);

  const std::vector<double>& p = *ctx.params;
  filter->SetLower(CastParam<PixelT>(p[0], "SCT", "LowerThreshold"));
  filter->SetUpper(CastParam<PixelT>(p[1], "SCT", "UpperThreshold"));

  // ReplaceValue is HARDCODED to 255. The MATITK registry exposes no
  // ReplaceValue parameter for SCT (docs/matitk_opcode_registry.txt: only
  // LowerThreshold, UpperThreshold), and the ITK 2.4 example the original's
  // Perl generator worked from hardcodes exactly this:
  //   connectedThreshold->SetReplaceValue( 255 );
  // (Examples/Segmentation/ConnectedThresholdImageFilter.cxx, v2.4.0). ITK's
  // own constructor default is 1, not 255, so this must be set explicitly.
  filter->SetReplaceValue(static_cast<PixelT>(255));

  // Seeds map onto ITK axes with no transpose; see SeedPointsToIndices. An
  // empty seed list is defined behaviour: the flood iterator reports IsAtEnd
  // immediately and the output is all-background (verified from
  // itkFloodFilledFunctionConditionalConstIterator GoToBegin()).
  for (const auto& idx :
       SeedPointsToIndices(*ctx.seeds, input->GetLargestPossibleRegion().GetSize())) {
    filter->AddSeed(idx);
  }

  filter->Update();
  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class SctOpcode : public Opcode {
 public:
  const char* Name() const override { return "SCT"; }
  Category GetCategory() const override { return Category::kSegmentation; }
  const char* Description() const override {
    return "Connected-threshold region growing from seed(s)";
  }
  Status GetStatus() const override { return Status::kValidated; }
  const char* StatusNote() const override {
    return "bit-identical to the original on every fixture the original "
           "itself accepted (14 of 17 captured), asserted by "
           "tests/tReferenceExact.m; the other three are a mutual "
           "rejection (an out-of-range seed) and two accepts-more cases "
           "(a dimension-maximum seed, an arg4-class-mismatch call), see "
           "tests/tReferenceRejections.m. "
           "ReplaceValue is hardcoded to 255 (inferred: the registry exposes "
           "no ReplaceValue and ITK's ConnectedThreshold example hardcodes "
           "255; ITK's own default is 1). Seed coordinates map onto image "
           "axes in dimension order with no transpose; an empty seed list "
           "yields an all-background output.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"LowerThreshold", nullptr},
        {"UpperThreshold", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunSct<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetSctOpcode() {
  static const SctOpcode op;
  return &op;
}

}  // namespace mexitk
