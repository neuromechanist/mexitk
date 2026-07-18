// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// SCC - confidence-connected region growing.
// Wraps itk::ConfidenceConnectedImageFilter (module ITKRegionGrowing).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkConfidenceConnectedImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunScc(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  using FilterType = itk::ConfidenceConnectedImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);

  const std::vector<double>& p = *ctx.params;
  filter->SetMultiplier(p[0]);  // SetMultiplier takes double; p[0] is a double
  filter->SetNumberOfIterations(
      CastParam<unsigned int>(p[1], "SCC", "NumberOfIteration"));
  filter->SetReplaceValue(CastParam<PixelT>(p[2], "SCC", "ReplaceValue"));

  // InitialNeighborhoodRadius is left at ITK's default (1). The registry
  // exposes no such parameter; the ITK 2.4 example sets 2, but MATITK's flat
  // param list omits it, so the constructor default applies. Empty seeds are
  // defined in ITK 5.4: GenerateData returns an all-zero image when no seed is
  // inside the region (itkConfidenceConnectedImageFilter.hxx, "no seeds result
  // in zero image").
  for (const auto& idx :
       SeedPointsToIndices(*ctx.seeds, input->GetLargestPossibleRegion().GetSize())) {
    filter->AddSeed(idx);
  }

  filter->Update();
  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class SccOpcode : public Opcode {
 public:
  const char* Name() const override { return "SCC"; }
  Category GetCategory() const override { return Category::kSegmentation; }
  const char* Description() const override {
    return "Confidence-connected region growing from seed(s)";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists. "
           "InitialNeighborhoodRadius is left at ITK's default of 1 (registry "
           "exposes no such parameter; the ITK example sets 2, but the "
           "original's param list omits it). An empty seed list yields an "
           "all-zero output.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"multiplier", "2.5"},
        {"NumberOfIteration", "5"},
        {"ReplaceValue", "100"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunScc<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetSccOpcode() {
  static const SccOpcode op;
  return &op;
}

}  // namespace mexitk
