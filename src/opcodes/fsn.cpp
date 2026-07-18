// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FSN - sigmoid intensity remapping.
// Wraps itk::SigmoidImageFilter (module ITKImageIntensity).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkSigmoidImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunFsn(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::SigmoidImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);
  filter->SetOutputMinimum(CastParam<PixelT>(p[0], "FSN", "outputMinimum"));
  filter->SetOutputMaximum(CastParam<PixelT>(p[1], "FSN", "outputMaximum"));
  filter->SetAlpha(p[2]);
  filter->SetBeta(p[3]);
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class FsnOpcode : public Opcode {
 public:
  const char* Name() const override { return "FSN"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override { return "Sigmoid intensity remapping"; }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"outputMinimum", "10"},
        {"outputMaximum", "240"},
        {"alpha", "10"},
        {"beta", "170"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    // alpha == 0 makes SigmoidImageFilter's functor divide by zero, producing
    // NaN that then hits an undefined-behaviour cast into an integer pixel
    // type. Reject it rather than reproduce the corruption.
    if ((*ctx.params)[2] == 0.0) {
      throw OpcodeError("mexitk:FSN:alpha", "alpha must be nonzero.");
    }
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFsn<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFsnOpcode() {
  static const FsnOpcode op;
  return &op;
}

}  // namespace mexitk
