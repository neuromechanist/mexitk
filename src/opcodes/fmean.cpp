// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FMEAN - mean filter.
// Wraps itk::MeanImageFilter (module ITKSmoothing).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkMeanImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunFmean(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::MeanImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);

  // The 2006 original maps X-named parameters to MATLAB dim 2 (ITK axis 1)
  // and Y-named parameters to MATLAB dim 1 (ITK axis 0); Z is unchanged.
  // Applied here for family consistency with FMEDIAN/SNC/FVBIH, which all
  // share the same XRADIUS/YRADIUS/ZRADIUS registry naming: FMEAN's own
  // captured fixtures are all symmetric-radius, so this swap is NOT
  // directly fixture-proven for FMEAN itself, only inferred. See
  // docs/COMPATIBILITY.md, second capture campaign findings.
  typename FilterType::RadiusType radius;
  radius[0] = CastParam<itk::SizeValueType>(p[1], "FMEAN", "YRADIUS");
  radius[1] = CastParam<itk::SizeValueType>(p[0], "FMEAN", "XRADIUS");
  radius[2] = CastParam<itk::SizeValueType>(p[2], "FMEAN", "ZRADIUS");
  filter->SetRadius(radius);
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class FmeanOpcode : public Opcode {
 public:
  const char* Name() const override { return "FMEAN"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Mean filter over a rectangular neighbourhood";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"XRADIUS", nullptr},
        {"YRADIUS", nullptr},
        {"ZRADIUS", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFmean<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFmeanOpcode() {
  static const FmeanOpcode op;
  return &op;
}

}  // namespace mexitk
