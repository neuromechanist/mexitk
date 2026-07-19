// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// SSDLS - shape detection level-set segmentation.
// Wraps itk::ShapeDetectionLevelSetImageFilter (module ITKLevelSets). Unlike
// SGAC/SLLS, the original does not threshold this filter's output: it
// returns the raw, narrow-band level-set values directly.

#include "mexitk_common.h"
#include "opcode.h"

#include "itkShapeDetectionLevelSetImageFilter.h"

#include <cmath>
#include <type_traits>

namespace mexitk {
namespace {

// Same promote-integral-to-float policy as SGAC/SLLS/SFM/FCA; see
// SgacRealType's comment in sgac.cpp.
template <typename PixelT>
using SsdlsRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunSsdls(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = SsdlsRealType<PixelT>;
  using RealImage = Image3<RealT>;

  RequireVolumeB(ctx.volumeA, ctx.volumeB, "SSDLS");

  typename InImage::Pointer inputA = ImportVolume<PixelT>(ctx.volumeA);
  typename InImage::Pointer inputB = ImportVolume<PixelT>(ctx.volumeB);
  typename RealImage::Pointer realA = PromoteToReal<PixelT, RealT>(inputA);
  typename RealImage::Pointer realB = PromoteToReal<PixelT, RealT>(inputB);

  const std::vector<double>& p = *ctx.params;

  // Non-finite guards up front, per docs/COMPATIBILITY.md deviation 12; see
  // SGAC's identical rationale. MaxIteration is self-guarded via
  // CastParam<itk::IdentifierType> below.
  if (!std::isfinite(p[0])) {
    throw OpcodeError("mexitk:SSDLS:propagationScaling", "propagationScaling must be finite.");
  }
  if (!std::isfinite(p[1])) {
    throw OpcodeError("mexitk:SSDLS:curvatureScaling", "curvatureScaling must be finite.");
  }
  if (!std::isfinite(p[2])) {
    throw OpcodeError("mexitk:SSDLS:MaximumRMSError", "MaximumRMSError must be finite.");
  }

  using FilterType = itk::ShapeDetectionLevelSetImageFilter<RealImage, RealImage, RealT>;
  typename FilterType::Pointer filter = FilterType::New();
  // Role assignment, fixture-verified (Epic 3 Phase 2,
  // ssdls_ssdls_volB_seedS1_double): same convention as SGAC/SLLS --
  // volumeA is the FEATURE image (edge-potential map) and volumeB is the
  // INITIAL level set. This fixture's own console output corroborates
  // volumeA's role with the same text as SGAC's and SLLS's fixtures (see
  // sgac.cpp's own comment for the exact wording and the "input A's
  // gradient" vs ITK's "initial level set" terminology note); the
  // CONFIRMING evidence for the actual SetInput()/SetFeatureImage() wiring
  // is the swap test: rebuilding with the two volumes swapped and
  // comparing against the fixture's own natural (volumeA, volumeB) order.
  // feature=volumeA / initial-level-set=volumeB reproduces it within the
  // measured bounded deviation (see StatusNote); the swapped assignment
  // does not (max-abs 8 vs. 5.25e-6, RMS 1.57 vs. 6.7e-8 -- three orders
  // of magnitude worse, a completely different segmentation).
  filter->SetFeatureImage(realA);
  filter->SetInput(realB);
  filter->SetPropagationScaling(CastParam<RealT>(p[0], "SSDLS", "propagationScaling"));
  filter->SetCurvatureScaling(CastParam<RealT>(p[1], "SSDLS", "curvatureScaling"));
  // No AdvectionScaling parameter: ShapeDetectionLevelSetImageFilter's own
  // header documents "there is no advection term for this filter. Setting
  // the advection scaling will have no effect", matching the original's own
  // 4-parameter list for this opcode (no AdvectionScaling slot), so nothing
  // is set here.
  filter->SetMaximumRMSError(p[2]);
  filter->SetNumberOfIterations(CastParam<itk::IdentifierType>(p[3], "SSDLS", "MaxIteration"));
  filter->Update();

  // No threshold step: fixture-verified the original returns this filter's
  // raw, narrow-band level-set output directly (values bounded within the
  // solver's own narrow band, +-4 on the captured fixture), unlike
  // SGAC/SLLS which both binary-threshold their output.
  ctx.plhs[0] = ExportPromoted<PixelT, RealT>(filter->GetOutput());
}

class SsdlsOpcode : public Opcode {
 public:
  const char* Name() const override { return "SSDLS"; }
  Category GetCategory() const override { return Category::kSegmentation; }
  const char* Description() const override {
    return "Shape detection level-set segmentation (raw level set)";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "does not reproduce the original bit-for-bit on the one "
           "captured fixture (ssdls_ssdls_volB_seedS1_double: "
           "propagationScaling=1, curvatureScaling=1, MaximumRMSError=0.02, "
           "MaxIteration=50, seed [70 50 14], double): measured max-abs "
           "5.25e-6, RMS 6.7e-8, on 26274/442368 voxels (5.94%), asserted "
           "by tests/tReferenceBounded.m -- the floating-point noise floor "
           "of a 50-iteration finite-difference solver (the same category "
           "as SFM's own bounded deviation), not an algorithmic difference: "
           "role assignment was independently re-confirmed by rebuilding "
           "with the volumes swapped, which produced max-abs 8 / RMS 1.57 "
           "(a completely different segmentation), showing the correct "
           "role (volumeA=feature image, volumeB=initial level set, same "
           "convention as SGAC/SLLS) is what is actually being measured "
           "here, not a role error masquerading as noise. The original "
           "does not threshold this opcode's output: it returns the raw, "
           "narrow-band level-set values directly (bounded +-4 on the "
           "captured fixture), reproduced the same way here, no "
           "thresholding step. Seeds are accepted and ignored (verified: "
           "bit-identical output with and without the seed argument), the "
           "same convention as SWS. No fixture exists for single/uint8/"
           "int32 or other parameter values, so no agreement claim is made "
           "for them; uint8/int32 promote to float internally and clamp "
           "back on export.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"propagationScaling", nullptr},
        {"curvatureScaling", "1.0"},
        {"MaximumRMSError", "0.02"},
        {"MaxIteration", "800"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunSsdls<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetSsdlsOpcode() {
  static const SsdlsOpcode op;
  return &op;
}

}  // namespace mexitk
