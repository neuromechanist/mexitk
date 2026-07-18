// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// SNC - neighborhood-connected region growing.
// Wraps itk::NeighborhoodConnectedImageFilter (module ITKRegionGrowing).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkNeighborhoodConnectedImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunSnc(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  using FilterType = itk::NeighborhoodConnectedImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);

  const std::vector<double>& p = *ctx.params;
  typename InImage::SizeType radius;
  radius[0] = CastParam<itk::SizeValueType>(p[0], "SNC", "RadiusX");
  radius[1] = CastParam<itk::SizeValueType>(p[1], "SNC", "RadiusY");
  radius[2] = CastParam<itk::SizeValueType>(p[2], "SNC", "RadiusZ");
  filter->SetRadius(radius);
  filter->SetLower(CastParam<PixelT>(p[3], "SNC", "LowerThreshold"));
  filter->SetUpper(CastParam<PixelT>(p[4], "SNC", "UpperThreshold"));
  filter->SetReplaceValue(CastParam<PixelT>(p[5], "SNC", "ReplaceValue"));

  for (const auto& idx :
       SeedPointsToIndices(*ctx.seeds, input->GetLargestPossibleRegion().GetSize())) {
    filter->AddSeed(idx);
  }

  filter->Update();
  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class SncOpcode : public Opcode {
 public:
  const char* Name() const override { return "SNC"; }
  Category GetCategory() const override { return Category::kSegmentation; }
  const char* Description() const override {
    return "Neighborhood-connected region growing from seed(s)";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists. "
           "Radius axes (X,Y,Z) map onto image dimensions 1,2,3. An empty "
           "seed list yields an all-zero output.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"RadiusX", "2"},
        {"RadiusY", "2"},
        {"RadiusZ", "2"},
        {"LowerThreshold", nullptr},
        {"UpperThreshold", nullptr},
        {"ReplaceValue", "255"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunSnc<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetSncOpcode() {
  static const SncOpcode op;
  return &op;
}

}  // namespace mexitk
