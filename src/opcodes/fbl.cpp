// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FBL - bilateral filter.
// Wraps itk::BilateralImageFilter (module ITKImageFeature).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkBilateralImageFilter.h"

namespace mexitk {
namespace {

// No promotion: the only concept check is OutputHasNumericTraitsCheck
// (itkBilateralImageFilter.h:174), satisfied by all four supported types,
// and there is no float requirement anywhere in the class documentation.
// The output is a normalised weighted average of in-range input values, so
// a native integral output cannot leave the input's own value range.
template <typename PixelT>
void RunFbl(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::BilateralImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);
  filter->SetDomainSigma(p[0]);  // scalar double overload, fills all axes
  filter->SetRangeSigma(p[1]);
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class FblOpcode : public Opcode {
 public:
  const char* Name() const override { return "FBL"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override { return "Bilateral filter (edge-preserving smoothing)"; }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"domainSigma", "5"},
        {"rangeSigma", "5"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFbl<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFblOpcode() {
  static const FblOpcode op;
  return &op;
}

}  // namespace mexitk
