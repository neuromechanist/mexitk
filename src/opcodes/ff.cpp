// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FF - flip along selected axes.
// Wraps itk::FlipImageFilter (module ITKImageGrid).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkFlipImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunFf(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::FlipImageFilter<InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);

  typename FilterType::FlipAxesArrayType axes;
  axes[0] = (p[0] != 0.0);
  axes[1] = (p[1] != 0.0);
  axes[2] = (p[2] != 0.0);
  filter->SetFlipAxes(axes);
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class FfOpcode : public Opcode {
 public:
  const char* Name() const override { return "FF"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override { return "Flip image along selected axes"; }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"XDIRECTION", nullptr},
        {"YDIRECTION", nullptr},
        {"ZDIRECTION", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFf<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFfOpcode() {
  static const FfOpcode op;
  return &op;
}

}  // namespace mexitk
