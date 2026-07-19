// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FBB - binomial blur.
// Wraps itk::BinomialBlurImageFilter (module ITKSmoothing).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkBinomialBlurImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunFbb(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::BinomialBlurImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);
  filter->SetRepetitions(CastParam<unsigned int>(p[0], "FBB", "repetitions"));
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class FbbOpcode : public Opcode {
 public:
  const char* Name() const override { return "FBB"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Binomial blur (repeated nearest-neighbour smoothing)";
  }
  Status GetStatus() const override { return Status::kValidated; }
  const char* StatusNote() const override {
    return "bit-identical to the original on every captured fixture (4 of "
           "4, all four pixel types), asserted by tests/tReferenceExact.m.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"repetitions", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFbb<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFbbOpcode() {
  static const FbbOpcode op;
  return &op;
}

}  // namespace mexitk
