// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FGMRG / FGMS - gradient magnitude via recursive Gaussian derivative.
// Wraps itk::GradientMagnitudeRecursiveGaussianImageFilter (module ITKImageGradient).
//
// FGMRG and FGMS share an identical single-parameter (Sigma) registry
// signature, and the original's own captured output is BIT-IDENTICAL
// between the two at every matching sigma (1, 2, 4; verified directly --
// fgms_sigma1_double's outputHash equals fgmrg_1_double's, and likewise for
// sigma 2 and 4 -- not merely close, the exact same array), the same
// Perl-generator-duplicate situation as FDG/FGA (see fdg.cpp). Both are
// implemented as the same filter call. See FgmsOpcode::StatusNote.
// docs/itk_opcode_mapping.md's own FGMS entry hypothesized a DIFFERENT,
// two-stage pipeline (SmoothingRecursiveGaussianImageFilter feeding
// GradientMagnitudeImageFilter) at Low confidence, flagged as needing a
// live comparison against the real binary before committing to an
// implementation; the fixture comparison above settles it in favor of the
// FGMRG alias instead, correcting that hypothesis.

#include "mexitk_common.h"
#include "opcode.h"

#include "itkCastImageFilter.h"
#include "itkGradientMagnitudeRecursiveGaussianImageFilter.h"

#include <cmath>
#include <type_traits>

namespace mexitk {
namespace {

const std::vector<ParamSpec>& GradientMagnitudeRecursiveGaussianParams() {
  static const std::vector<ParamSpec> kParams = {
      {"sigma", nullptr},
  };
  return kParams;
}

// The filter has no float concept check (only InputHasNumericTraitsCheck,
// itkGradientMagnitudeRecursiveGaussianImageFilter.h:133), but it hardwires
// InternalRealType = float internally (:75) and its final stage is a raw
// SqrtImageFilter functor cast into whatever output type is instantiated
// (:85). Promoting integral input to float and clamping back on export
// replaces that undefined-adjacent narrowing cast with defined saturation,
// the same policy already applied elsewhere (deviation 8).
template <typename PixelT>
using FgmrgRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunGradientMagnitudeRecursiveGaussian(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = FgmrgRealType<PixelT>;
  using RealImage = Image3<RealT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  typename RealImage::Pointer real;
  if constexpr (std::is_same<PixelT, RealT>::value) {
    real = input;
  } else {
    using CastIn = itk::CastImageFilter<InImage, RealImage>;
    typename CastIn::Pointer cast = CastIn::New();
    cast->SetInput(input);
    cast->Update();
    real = cast->GetOutput();
  }

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::GradientMagnitudeRecursiveGaussianImageFilter<RealImage, RealImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(real);
  filter->SetSigma(p[0]);
  // NormalizeAcrossScale is left at its ITK default (false): the registry
  // exposes no such parameter, so the constructor default applies.
  filter->Update();

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(filter->GetOutput());
  } else {
    // See FcaRealType's comment in fca.cpp for the saturation rationale.
    ctx.plhs[0] = ClampExport<PixelT, RealT>(filter->GetOutput());
  }
}

// Shared by FgmrgOpcode and FgmsOpcode. sigma <= 0 is already caught by
// ITK's own exception (mexitk:itkException), unchanged here. That guard's
// `<= 0.0` does not catch NaN or +Inf (confirmed empirically on FGMRG:
// silent all-NaN output, no exception) -- the actual pre-PR gap this guard
// closes. `-Inf` is different: `-Inf <= 0.0` is true, so ITK's own
// exception already caught it pre-PR too (as mexitk:itkException); this
// guard now intercepts it first instead, since it runs before either
// opcode's Run ever dispatches to the filter, so `-Inf` now surfaces
// under the caller's own `mexitk:<OPCODE>:sigma` id -- a deliberate,
// disclosed identifier change, not a new rejection.
void ExecuteGradientMagnitudeRecursiveGaussian(OpContext& ctx, const char* sigmaErrorId) {
  if (!std::isfinite((*ctx.params)[0])) {
    throw OpcodeError(sigmaErrorId, "sigma must be finite.");
  }
  DispatchOnPixelType(mxGetClassID(ctx.volumeA), [&](auto tag) {
    RunGradientMagnitudeRecursiveGaussian<typename decltype(tag)::type>(ctx);
  });
}

class FgmrgOpcode : public Opcode {
 public:
  const char* Name() const override { return "FGMRG"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Gradient magnitude (recursive Gaussian derivative)";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "bit-identical to the original on int32/uint8 at sigma=2 (see "
           "tests/tReferenceExact.m); every other captured combination "
           "(double at sigma 1/2/4, single at sigma 2) has a residual at "
           "the floating-point noise floor (RMS order 1e-7 to 1e-8), "
           "asserted by tests/tReferenceBounded.m. Not classified as "
           "validated overall because of the double/single residual. "
           "Distinct algorithm from FGM (recursive Gaussian derivative vs "
           "central differences); the two return different output on the "
           "same volume by design. FGMS (Epic 4 Phase 2) is now confirmed "
           "bit-identical to FGMRG in the original binary itself at every "
           "captured sigma -- see FgmsOpcode::StatusNote.";
  }

  const std::vector<ParamSpec>& Params() const override {
    return GradientMagnitudeRecursiveGaussianParams();
  }

  void Execute(OpContext& ctx) const override {
    ExecuteGradientMagnitudeRecursiveGaussian(ctx, "mexitk:FGMRG:sigma");
  }
};

class FgmsOpcode : public Opcode {
 public:
  const char* Name() const override { return "FGMS"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Gradient magnitude with smoothing (registry duplicate of FGMRG)";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "docs/itk_opcode_mapping.md's own FGMS entry could not pin this "
           "opcode to any specific ITK class from naming/parameter-shape "
           "evidence alone (Low confidence, flagged as needing a live "
           "comparison against the real binary), hypothesizing a two-stage "
           "SmoothingRecursiveGaussianImageFilter+GradientMagnitudeImage"
           "Filter pipeline as a guess. That hypothesis is now DISPROVEN, "
           "not just superseded: fixture comparison (Epic 4 Phase 2) shows "
           "the original's own FGMS output is BIT-IDENTICAL to its own "
           "FGMRG output at every captured sigma (1, 2, 4) -- "
           "outputHash equal, not merely close (fgms_sigma1_double == "
           "fgmrg_1_double, fgms_sigma2_double == fgmrg_2_double, "
           "fgms_sigma4_double == fgmrg_4_double, verified directly with "
           "isequal on the full array plus an independent hash check), the "
           "same Perl-generator-duplicate situation as FGA/FDG "
           "(see docs/COMPATIBILITY.md). mexitk implements FGMS as the "
           "same itk::GradientMagnitudeRecursiveGaussianImageFilter as "
           "FGMRG, and measures the identical residual against these "
           "fixtures as FGMRG measures against its own captured fixtures "
           "at the same sigma (RMS 2.73366e-07 at sigma=1, 1.32290e-07 at "
           "sigma=2, 7.13001e-08 at sigma=4 -- the floating-point noise "
           "floor, not an algorithmic difference), asserted by "
           "tests/tReferenceBounded.m. Whether the original shipped two "
           "genuinely distinct filters under these names remains "
           "unconfirmed against MATITK source, but the bit-identical "
           "cross-check makes a Perl-generator duplicate the far more "
           "likely explanation, same reasoning as FGA/FDG. Only double has "
           "been captured; single/uint8/int32 carry no agreement claim and "
           "promote to float internally, same as FGMRG.";
  }

  const std::vector<ParamSpec>& Params() const override {
    return GradientMagnitudeRecursiveGaussianParams();
  }

  void Execute(OpContext& ctx) const override {
    ExecuteGradientMagnitudeRecursiveGaussian(ctx, "mexitk:FGMS:sigma");
  }
};

}  // namespace

const Opcode* GetFgmrgOpcode() {
  static const FgmrgOpcode op;
  return &op;
}

const Opcode* GetFgmsOpcode() {
  static const FgmsOpcode op;
  return &op;
}

}  // namespace mexitk
