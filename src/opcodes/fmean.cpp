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

  typename FilterType::RadiusType radius;
  radius[0] = static_cast<itk::SizeValueType>(p[0]);
  radius[1] = static_cast<itk::SizeValueType>(p[1]);
  radius[2] = static_cast<itk::SizeValueType>(p[2]);
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
