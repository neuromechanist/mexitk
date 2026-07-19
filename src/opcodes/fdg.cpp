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

#include <cmath>

namespace mexitk {
namespace {

const std::vector<ParamSpec>& DiscreteGaussianParams() {
  static const std::vector<ParamSpec> kParams = {
      {"gaussianVariance", nullptr},
      {"maxKernelWidth", nullptr},
  };
  return kParams;
}

template <typename PixelT>
void RunDiscreteGaussian(OpContext& ctx, const char* opcodeName) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::DiscreteGaussianImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);
  filter->SetVariance(p[0]);
  filter->SetMaximumKernelWidth(CastParam<unsigned int>(p[1], opcodeName, "maxKernelWidth"));
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

// Shared by FdgOpcode and FgaOpcode. A non-positive variance silently yields
// a degenerate, non-Gaussian kernel rather than an error, so it is rejected
// here under the caller's own opcode name (for the error id and CastParam
// diagnostics) before dispatching. A NaN variance reaches the same silent
// path (confirmed empirically: SetVariance(NaN) produces an all-NaN output
// with no exception) since `<= 0.0` alone does not catch NaN -- guarded
// here too, param-guard hardening pass.
void ExecuteDiscreteGaussian(OpContext& ctx, const char* opcodeName,
                             const char* varianceErrorId) {
  const double variance = (*ctx.params)[0];
  if (!std::isfinite(variance) || variance <= 0.0) {
    throw OpcodeError(varianceErrorId, "gaussianVariance must be finite and positive.");
  }
  DispatchOnPixelType(mxGetClassID(ctx.volumeA), [&](auto tag) {
    RunDiscreteGaussian<typename decltype(tag)::type>(ctx, opcodeName);
  });
}

class FdgOpcode : public Opcode {
 public:
  const char* Name() const override { return "FDG"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override { return "Discrete Gaussian smoothing"; }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "does not reproduce the original bit-for-bit: "
           "DiscreteGaussianImageFilter's numerics moved between ITK 2.4 "
           "and 5.x, the same class of upstream evolution as FCA. Measured "
           "RMS is small (order 1e-3 to 4e-3 at gaussianVariance 4-10) but "
           "nonzero on double/single/int32; the original rejects uint8 "
           "outright (a caught exception after a kernel-width-truncation "
           "warning), and mexitk accepts it, with no agreement claim for "
           "that pixel type. See tests/tReferenceBounded.m and "
           "tests/tReferenceRejections.m for the measured numbers and the "
           "uint8 accepts-more case, and docs/COMPATIBILITY.md for the "
           "full writeup, including the confirmed FGA==FDG alias (the "
           "original's own two opcodes are bit-identical to each other at "
           "every capturable point, per the s12_fga_fdg_isequal.mat "
           "cross-check probe, with the same uint8 failure mode).";
  }

  const std::vector<ParamSpec>& Params() const override { return DiscreteGaussianParams(); }

  void Execute(OpContext& ctx) const override {
    ExecuteDiscreteGaussian(ctx, "FDG", "mexitk:FDG:gaussianVariance");
  }
};

class FgaOpcode : public Opcode {
 public:
  const char* Name() const override { return "FGA"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Discrete Gaussian smoothing (registry duplicate of FDG)";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "registry parameter signature is identical to FDG (gaussianVariance, "
           "maxKernelWidth) and mexitk implements it as the same "
           "itk::DiscreteGaussianImageFilter. The alias is now fixture-"
           "confirmed, not just inferred: the original's own FGA and FDG "
           "outputs are bit-identical to each other at every capturable "
           "point (double and uint8, per the s12_fga_fdg_isequal.mat "
           "cross-check probe), and share the same uint8 failure mode. "
           "Same measured deviation from the original as FDG (see "
           "FdgOpcode::StatusNote and tests/tReferenceBounded.m); whether "
           "the original shipped two genuinely distinct filters under "
           "these names remains unconfirmed against MATITK source, but the "
           "bit-identical cross-check makes a Perl-generator duplicate the "
           "far more likely explanation.";
  }

  const std::vector<ParamSpec>& Params() const override { return DiscreteGaussianParams(); }

  void Execute(OpContext& ctx) const override {
    ExecuteDiscreteGaussian(ctx, "FGA", "mexitk:FGA:gaussianVariance");
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
