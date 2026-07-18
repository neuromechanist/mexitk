// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FBT - binary threshold.
// Wraps itk::BinaryThresholdImageFilter (module ITKThresholding).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkBinaryThresholdImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunFbt(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::BinaryThresholdImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);
  filter->SetOutsideValue(CastParam<PixelT>(p[0], "FBT", "outsideValue"));
  filter->SetInsideValue(CastParam<PixelT>(p[1], "FBT", "insideValue"));
  filter->SetLowerThreshold(CastParam<PixelT>(p[2], "FBT", "lowerThreshold"));
  filter->SetUpperThreshold(CastParam<PixelT>(p[3], "FBT", "upperThreshold"));
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class FbtOpcode : public Opcode {
 public:
  const char* Name() const override { return "FBT"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Binary threshold to inside/outside values";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"outsideValue", nullptr},
        {"insideValue", nullptr},
        {"lowerThreshold", nullptr},
        {"upperThreshold", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFbt<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFbtOpcode() {
  static const FbtOpcode op;
  return &op;
}

}  // namespace mexitk
