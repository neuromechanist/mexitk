// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FDG / FGA - discrete Gaussian smoothing.
// Wraps itk::DiscreteGaussianImageFilter (module ITKSmoothing).
//
// FDG and FGA share an identical registry parameter signature
// (gaussianVariance, maxKernelWidth) and no other ITK class matches that
// shape, so both are implemented as the same filter. See FgaOpcode::StatusNote.

#include "mexitk_common.h"
#include "opcode.h"

#include "itkDiscreteGaussianImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunDiscreteGaussian(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::DiscreteGaussianImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);
  filter->SetVariance(p[0]);
  filter->SetMaximumKernelWidth(static_cast<unsigned int>(p[1]));
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class FdgOpcode : public Opcode {
 public:
  const char* Name() const override { return "FDG"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override { return "Discrete Gaussian smoothing"; }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"gaussianVariance", nullptr},
        {"maxKernelWidth", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(
        mxGetClassID(ctx.volumeA),
        [&](auto tag) { RunDiscreteGaussian<typename decltype(tag)::type>(ctx); });
  }
};

class FgaOpcode : public Opcode {
 public:
  const char* Name() const override { return "FGA"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Discrete Gaussian smoothing (registry duplicate of FDG)";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "registry parameter signature is identical to FDG (gaussianVariance, "
           "maxKernelWidth) and mexitk implements it as the same "
           "itk::DiscreteGaussianImageFilter. Whether the original shipped two "
           "distinct filters under these names is unconfirmed against MATITK "
           "source; it is most likely a Perl-generator duplicate.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"gaussianVariance", nullptr},
        {"maxKernelWidth", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(
        mxGetClassID(ctx.volumeA),
        [&](auto tag) { RunDiscreteGaussian<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFdgOpcode() {
  static const FdgOpcode op;
  return &op;
}

const Opcode* GetFgaOpcode() {
  static const FgaOpcode op;
  return &op;
}

}  // namespace mexitk
