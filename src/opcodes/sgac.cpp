// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// SGAC - geodesic active contour level-set segmentation.
// Wraps itk::GeodesicActiveContourLevelSetImageFilter (module ITKLevelSets),
// the first two-volume opcode in this codebase (volumeA and volumeB are
// both genuinely consumed, not accepted-and-ignored like every existing
// opcode's optional arg4).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkBinaryThresholdImageFilter.h"
#include "itkGeodesicActiveContourLevelSetImageFilter.h"

#include <cmath>
#include <limits>
#include <type_traits>

namespace mexitk {
namespace {

// Same promote-integral-to-float policy as every other real-pixel-only
// filter in this codebase (FCA, FCF, FMMCF, SFM, ...); see FcaRealType's
// comment in fca.cpp. TOutputPixelType is set to RealT explicitly below
// (rather than left at the class's own float default) so a double input
// computes the level set at full double precision, matching SFM's own
// precedent (proven correct there by the fixture's exact LargeValue
// sentinel) rather than silently narrowing to float mid-pipeline.
template <typename PixelT>
using SgacRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunSgac(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = SgacRealType<PixelT>;
  using RealImage = Image3<RealT>;

  RequireVolumeB(ctx.volumeA, ctx.volumeB, "SGAC");

  typename InImage::Pointer inputA = ImportVolume<PixelT>(ctx.volumeA);
  typename InImage::Pointer inputB = ImportVolume<PixelT>(ctx.volumeB);
  typename RealImage::Pointer realA = PromoteToReal<PixelT, RealT>(inputA);
  typename RealImage::Pointer realB = PromoteToReal<PixelT, RealT>(inputB);

  const std::vector<double>& p = *ctx.params;

  // Non-finite guards up front, per docs/COMPATIBILITY.md deviation 12: none
  // of these four raw doubles has a prior mexitk-level or ITK-exception-level
  // sign/range constraint (unlike e.g. FLS/FGMRG's sigma), so only the
  // non-finite case is rejected here, nothing tightened beyond it.
  // MaxIteration needs no separate guard: CastParam<itk::IdentifierType>
  // below already rejects non-finite (and negative) values as part of its
  // own integral-cast safety check.
  if (!std::isfinite(p[0])) {
    throw OpcodeError("mexitk:SGAC:propagationScaling", "propagationScaling must be finite.");
  }
  if (!std::isfinite(p[1])) {
    throw OpcodeError("mexitk:SGAC:CurvatureScaling", "CurvatureScaling must be finite.");
  }
  if (!std::isfinite(p[2])) {
    throw OpcodeError("mexitk:SGAC:AdvectionScaling", "AdvectionScaling must be finite.");
  }
  if (!std::isfinite(p[3])) {
    throw OpcodeError("mexitk:SGAC:MaximumRMSError", "MaximumRMSError must be finite.");
  }

  using FilterType = itk::GeodesicActiveContourLevelSetImageFilter<RealImage, RealImage, RealT>;
  typename FilterType::Pointer filter = FilterType::New();
  // Role assignment, fixture-verified (Epic 3 Phase 2,
  // sgac_sgac_volB_seedS1_double): volumeA is the FEATURE image
  // (edge-potential map) and volumeB is the INITIAL level set. This is not
  // documented anywhere in the registry or the ITK mapping doc -- it was
  // determined empirically, the same kind of evidence-based reverse
  // engineering of the calling convention as the axis-swap findings for
  // FF/FMEDIAN/SNC elsewhere in this codebase, not a tuned choice: calling
  // the built opcode with the two volumes swapped at the MATLAB call site
  // was tried both ways, and only feature=volumeA / initial-level-set=
  // volumeB reproduces the fixture when called in ITS OWN natural
  // (volumeA, volumeB) argument order -- bit-exact, 0/442368 voxels differ
  // after the threshold step below.
  filter->SetFeatureImage(realA);
  filter->SetInput(realB);
  filter->SetPropagationScaling(CastParam<RealT>(p[0], "SGAC", "propagationScaling"));
  filter->SetCurvatureScaling(CastParam<RealT>(p[1], "SGAC", "CurvatureScaling"));
  filter->SetAdvectionScaling(CastParam<RealT>(p[2], "SGAC", "AdvectionScaling"));
  filter->SetMaximumRMSError(p[3]);
  filter->SetNumberOfIterations(CastParam<itk::IdentifierType>(p[4], "SGAC", "MaxIteration"));
  filter->Update();

  // Downstream binary threshold, fixture-verified: the original thresholds
  // the raw level set at its own zero crossing and maps the INSIDE region
  // to 255. GeodesicActiveContourLevelSetImageFilter's own header
  // documents "negative values ... represent the inside ... positive
  // values ... represent the outside" -- confirmed against the fixture,
  // not just assumed from the docstring: thresholding negative values to
  // 255 (bounds [lowest, 0], the classic ITK example's own
  // BinaryThresholdImageFilter pattern) reproduces the fixture bit-exact.
  // No fixture voxel lands at exactly 0.0 (the zero crossing itself), so
  // whether 0.0 counts as inside or outside is unverified either way;
  // SetUpperThreshold(0.0) is inclusive, matching the ITK example's own
  // bounds rather than inventing an exclusive variant with no evidence.
  using ThresholdType = itk::BinaryThresholdImageFilter<RealImage, InImage>;
  typename ThresholdType::Pointer thresh = ThresholdType::New();
  thresh->SetInput(filter->GetOutput());
  thresh->SetLowerThreshold(std::numeric_limits<RealT>::lowest());
  thresh->SetUpperThreshold(static_cast<RealT>(0.0));
  thresh->SetInsideValue(static_cast<PixelT>(255));
  thresh->SetOutsideValue(static_cast<PixelT>(0));
  thresh->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(thresh->GetOutput());
}

class SgacOpcode : public Opcode {
 public:
  const char* Name() const override { return "SGAC"; }
  Category GetCategory() const override { return Category::kSegmentation; }
  const char* Description() const override {
    return "Geodesic active contour level-set segmentation";
  }
  Status GetStatus() const override { return Status::kValidated; }
  const char* StatusNote() const override {
    return "bit-identical to the original on the one captured fixture "
           "(sgac_sgac_volB_seedS1_double: propagationScaling=1, "
           "CurvatureScaling=1, AdvectionScaling=1, MaximumRMSError=0.02, "
           "MaxIteration=50, seed [70 50 14], double), asserted by "
           "tests/tReferenceExact.m. Role assignment (volumeA=feature "
           "image, volumeB=initial level set) and threshold polarity "
           "(negative level-set values -> 255) were both determined "
           "empirically against this fixture, not documented anywhere in "
           "the original's own registry -- see the comments in this file. "
           "Seeds are accepted and ignored (verified: bit-identical output "
           "with and without the seed argument), the same convention as "
           "SWS. No fixture exists for single/uint8/int32 or other "
           "parameter values, so no agreement claim is made for them; "
           "uint8/int32 promote to float internally.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"propagationScaling", nullptr},
        {"CurvatureScaling", "1.0"},
        {"AdvectionScaling", "1.0"},
        {"MaximumRMSError", "0.02"},
        {"MaxIteration", "800"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunSgac<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetSgacOpcode() {
  static const SgacOpcode op;
  return &op;
}

}  // namespace mexitk
