// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// SLLS - Laplacian level-set segmentation.
// Wraps itk::LaplacianSegmentationLevelSetImageFilter (module ITKLevelSets).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkBinaryThresholdImageFilter.h"
#include "itkLaplacianSegmentationLevelSetImageFilter.h"

#include <cmath>
#include <limits>
#include <type_traits>

namespace mexitk {
namespace {

// Same promote-integral-to-float policy as SGAC/SFM/FCA; see SgacRealType's
// comment in sgac.cpp.
template <typename PixelT>
using SllsRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunSlls(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = SllsRealType<PixelT>;
  using RealImage = Image3<RealT>;

  RequireVolumeB(ctx.volumeA, ctx.volumeB, "SLLS");

  typename InImage::Pointer inputA = ImportVolume<PixelT>(ctx.volumeA);
  typename InImage::Pointer inputB = ImportVolume<PixelT>(ctx.volumeB);
  typename RealImage::Pointer realA = PromoteToReal<PixelT, RealT>(inputA);
  typename RealImage::Pointer realB = PromoteToReal<PixelT, RealT>(inputB);

  const std::vector<double>& p = *ctx.params;

  // Non-finite guards up front, per docs/COMPATIBILITY.md deviation 12; see
  // SGAC's identical rationale. MaxIteration is self-guarded via
  // CastParam<itk::IdentifierType> below.
  if (!std::isfinite(p[0])) {
    throw OpcodeError("mexitk:SLLS:IsoSurfaceValue", "IsoSurfaceValue must be finite.");
  }
  if (!std::isfinite(p[1])) {
    throw OpcodeError("mexitk:SLLS:PropagationScaling", "PropagationScaling must be finite.");
  }
  if (!std::isfinite(p[2])) {
    throw OpcodeError("mexitk:SLLS:CurvatureScaling", "CurvatureScaling must be finite.");
  }
  if (!std::isfinite(p[3])) {
    throw OpcodeError("mexitk:SLLS:MaximumRMSError", "MaximumRMSError must be finite.");
  }

  using FilterType = itk::LaplacianSegmentationLevelSetImageFilter<RealImage, RealImage, RealT>;
  typename FilterType::Pointer filter = FilterType::New();
  // Role assignment, fixture-verified (Epic 3 Phase 2,
  // slls_slls_volB_seedS1_double): same convention as SGAC -- volumeA is
  // the FEATURE image and volumeB is the INITIAL level set (the seed
  // isosurface). This fixture's own console output corroborates volumeA's
  // role with the same text as SGAC's and SSDLS's fixtures (see sgac.cpp's
  // own comment for the exact wording and the "input A's gradient" vs
  // ITK's "initial level set" terminology note); the CONFIRMING evidence
  // for the actual SetInput()/SetFeatureImage() wiring is the swap test:
  // rebuilding with the two volumes swapped and comparing against the
  // fixture's own natural (volumeA, volumeB) order. feature=volumeA /
  // initial-level-set=volumeB reproduces it within the measured bounded
  // deviation (see StatusNote); the swapped assignment does not
  // (422527/442368 voxels differ, a completely different segmentation).
  filter->SetFeatureImage(realA);
  filter->SetInput(realB);
  filter->SetIsoSurfaceValue(CastParam<RealT>(p[0], "SLLS", "IsoSurfaceValue"));
  filter->SetPropagationScaling(CastParam<RealT>(p[1], "SLLS", "PropagationScaling"));
  filter->SetCurvatureScaling(CastParam<RealT>(p[2], "SLLS", "CurvatureScaling"));
  filter->SetMaximumRMSError(p[3]);
  filter->SetNumberOfIterations(CastParam<itk::IdentifierType>(p[4], "SLLS", "MaxIteration"));
  filter->Update();

  // Downstream binary threshold, fixture-verified -- and NOT what
  // LaplacianSegmentationLevelSetImageFilter's own header documents.
  // The header says "Positive values ... inside ... negative values ...
  // outside", the opposite of SGAC (SSDLS is not a threshold comparison
  // point here: it does not threshold its output at all, see ssdls.cpp).
  // Tried exactly that against the fixture first (bounds [0, max] -> 255)
  // and it was wrong by nearly the entire volume (442088/442368 voxels,
  // mean output 101 vs the fixture's 154). The convention that actually
  // matches, confirmed against the fixture, is the SAME as SGAC: negative
  // values -> 255 (inside), bounds [lowest, 0] inclusive of the zero
  // crossing. This is not a reproduction of the documented semantics; it
  // is what the fixture evidence shows the original actually did. See
  // StatusNote for the residual this leaves.
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

class SllsOpcode : public Opcode {
 public:
  const char* Name() const override { return "SLLS"; }
  Category GetCategory() const override { return Category::kSegmentation; }
  const char* Description() const override {
    return "Laplacian level-set segmentation";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "does not reproduce the original bit-for-bit on the one "
           "captured fixture (slls_slls_volB_seedS1_double: "
           "IsoSurfaceValue=0.5, PropagationScaling=1, CurvatureScaling=1, "
           "MaximumRMSError=0.02, MaxIteration=50, seed [70 50 14], "
           "double): 280/442368 voxels (0.063%) differ, asserted by "
           "tests/tReferenceBounded.m. Every differing voxel's raw, "
           "pre-threshold level-set value is within 0.077 of the zero "
           "crossing (median 0.00087) -- the floating-point noise floor of "
           "a 50-iteration finite-difference solver landing a boundary "
           "voxel on the wrong side of the threshold, the same category as "
           "SFM's own bounded deviation, not an algorithmic difference. "
           "Role assignment (volumeA=feature image, volumeB=initial level "
           "set) matches SGAC/SSDLS, independently re-confirmed by "
           "rebuilding with the volumes swapped (422527/442368 differ, a "
           "completely different segmentation). Threshold polarity is the "
           "SAME as SGAC (negative values -> 255; SSDLS does not threshold "
           "its output, so it is not a comparison point for polarity), NOT "
           "what LaplacianSegmentationLevelSetImageFilter's own header claims "
           "(positive-inside) -- see the comments in this file; the "
           "documented polarity was tried first and was wrong by nearly "
           "the entire volume. Seeds are accepted and ignored (verified: "
           "bit-identical output with and without the seed argument), the "
           "same convention as SWS. No fixture exists for single/uint8/"
           "int32 or other parameter values, so no agreement claim is made "
           "for them; uint8/int32 promote to float internally.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"IsoSurfaceValue", nullptr},
        {"PropagationScaling", nullptr},
        {"CurvatureScaling", "1.0"},
        {"MaximumRMSError", "0.02"},
        {"MaxIteration", "800"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunSlls<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetSllsOpcode() {
  static const SllsOpcode op;
  return &op;
}

}  // namespace mexitk
