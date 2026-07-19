// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// RD - Demons deformable registration. Wraps a three-stage pipeline
// (itk::HistogramMatchingImageFilter feeding itk::DemonsRegistrationFilter
// feeding itk::WarpImageFilter), modules ITKImageIntensity + ITKPDEDeformable-
// Registration + ITKImageGrid, mirroring the classic ITK Demons registration
// example: match the moving image's histogram to the fixed image's, register
// with Demons to get a displacement field, then warp the ORIGINAL (pre-match)
// moving image with that field so the output keeps its own intensity range
// rather than the histogram-matched intermediate's.

#include "mexitk_common.h"
#include "opcode.h"

#include "itkDemonsRegistrationFilter.h"
#include "itkHistogramMatchingImageFilter.h"
#include "itkVector.h"
#include "itkWarpImageFilter.h"

#include <cmath>
#include <type_traits>

namespace mexitk {
namespace {

// Same promote-integral-to-float policy as every other real-pixel-only
// filter in this codebase (FCA, FCF, FMMCF, SFM, SGAC, ...); see
// FcaRealType's comment in fca.cpp. Demons and HistogramMatching both
// require a floating-point pixel type.
template <typename PixelT>
using RdRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunRd(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = RdRealType<PixelT>;
  using RealImage = Image3<RealT>;
  using DisplacementFieldType = itk::Image<itk::Vector<RealT, kDimension>, kDimension>;

  RequireVolumeB(ctx.volumeA, ctx.volumeB, "RD");

  typename InImage::Pointer inputA = ImportVolume<PixelT>(ctx.volumeA);
  typename InImage::Pointer inputB = ImportVolume<PixelT>(ctx.volumeB);
  typename RealImage::Pointer realA = PromoteToReal<PixelT, RealT>(inputA);
  typename RealImage::Pointer realB = PromoteToReal<PixelT, RealT>(inputB);

  const std::vector<double>& p = *ctx.params;

  // Non-finite guard, per docs/COMPATIBILITY.md deviation 12:
  // DemonStandardDeviations is a raw double with no prior sign/range
  // constraint (unlike e.g. FLS/FGMRG's sigma, which already throw via
  // ITK's own exception for <= 0), so only the non-finite case is rejected
  // here. NumberOfHistogramLevels/NumberOfMatchPoints/DemonNumberofIterations
  // need no separate guard: CastParam's integral path below already rejects
  // non-finite (and negative) values as part of its own cast-safety check.
  if (!std::isfinite(p[3])) {
    throw OpcodeError("mexitk:RD:DemonStandardDeviations",
                      "DemonStandardDeviations must be finite.");
  }

  // Fixed/moving role assignment, fixture-verified against
  // rd_demons_volB_double (Epic 4 Phase 1) the same way SGAC's own
  // feature/initial-level-set roles were: both wirings were tried against
  // the fixture, and only ONE reproduces it -- see StatusNote below and
  // src/opcodes/sgac.cpp for the precedent. volumeA is the FIXED (reference)
  // image; volumeB is the MOVING image, matched onto volumeA's histogram
  // and then registered onto volumeA's grid.
  typename RealImage::Pointer fixed = realA;
  typename RealImage::Pointer moving = realB;

  using MatchFilter = itk::HistogramMatchingImageFilter<RealImage, RealImage>;
  typename MatchFilter::Pointer matcher = MatchFilter::New();
  matcher->SetInput(moving);
  matcher->SetReferenceImage(fixed);
  matcher->SetNumberOfHistogramLevels(
      CastParam<itk::SizeValueType>(p[0], "RD", "NumberOfHistogramLevels"));
  matcher->SetNumberOfMatchPoints(
      CastParam<itk::SizeValueType>(p[1], "RD", "NumberOfMatchPoints"));
  // Explicit despite matching the class's own default (true): the classic
  // ITK Demons registration example calls this explicitly too, and leaving
  // it implicit invites a silent behaviour change if a future ITK release
  // moves the default, the same "left explicit with a comment" discipline
  // as FOMT's SetReturnBinMidpoint note.
  matcher->ThresholdAtMeanIntensityOn();
  matcher->Update();

  using DemonsFilter = itk::DemonsRegistrationFilter<RealImage, RealImage, DisplacementFieldType>;
  typename DemonsFilter::Pointer demons = DemonsFilter::New();
  demons->SetFixedImage(fixed);
  demons->SetMovingImage(matcher->GetOutput());
  demons->SetNumberOfIterations(
      CastParam<itk::IdentifierType>(p[2], "RD", "DemonNumberofIterations"));
  demons->SetStandardDeviations(p[3]);
  // The trap documented in docs/itk_opcode_mapping.md: SetStandardDeviations
  // is inert unless smoothing is explicitly enabled --
  // PDEDeformableRegistrationFilter::m_SmoothDisplacementField
  // default-initializes to false, and DemonsRegistrationFilter's own
  // constructor never touches it. Without this call,
  // DemonStandardDeviations is silently ignored. Do not remove it.
  demons->SmoothDisplacementFieldOn();
  demons->Update();

  // Warp the ORIGINAL (pre-histogram-match) moving image, not
  // matcher->GetOutput(): the classic ITK Demons example does this so the
  // final registered image keeps the moving image's own intensity range
  // rather than the histogram-matched intermediate's, which is only a
  // computational aid for the registration step itself. This particular
  // fixture cannot independently discriminate the two choices: volumeB is
  // circshift(volumeA), so both images share EXACTLY the same histogram,
  // and histogram matching against your own histogram is very close to
  // identity -- measured directly, warping matcher->GetOutput() instead of
  // `moving` here produces bit-identical mexitk output on this fixture
  // (RMS/max-abs unchanged to the printed precision). The choice is
  // therefore the classic-example convention, not an independently proven
  // fixture finding; a future fixture with genuinely different fixed/moving
  // histograms would be needed to settle it.
  using WarpFilter = itk::WarpImageFilter<RealImage, RealImage, DisplacementFieldType>;
  typename WarpFilter::Pointer warp = WarpFilter::New();
  warp->SetInput(moving);
  warp->SetDisplacementField(demons->GetDisplacementField());
  warp->SetOutputParametersFromImage(fixed);
  warp->Update();

  ctx.plhs[0] = ExportPromoted<PixelT, RealT>(warp->GetOutput());
}

class RdOpcode : public Opcode {
 public:
  const char* Name() const override { return "RD"; }
  Category GetCategory() const override { return Category::kRegistration; }
  const char* Description() const override { return "Demons deformable registration"; }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "does not reproduce the original bit-for-bit on the one captured "
           "fixture (rd_demons_volB_double: NumberOfHistogramLevels=1024, "
           "NumberOfMatchPoints=7, DemonNumberofIterations=150, "
           "DemonStandardDeviations=1, volumeB=circshift(volumeA,[3 3 1]), "
           "double): measured RMS 4.63626, max-abs 88 (the full 0-88 input "
           "intensity range), on 173173/442368 voxels (39.1%), asserted by "
           "tests/tReferenceBounded.m -- far above the floating-point noise "
           "floor other bounded-deviation opcodes here show (e.g. SFM's "
           "6.1e-15), so a real numerics difference, not rounding. The same "
           "broad category as FCA/FMMCF/SWS: an iterative solver (150 "
           "Demons iterations here) whose exact per-step numerics moved "
           "between ITK 2.4 and 5.4, plausibly compounding over that many "
           "iterations, though this is a single-fixture measurement with no "
           "second capture at a different iteration count to independently "
           "confirm compounding the way FCA's multi-iteration fixtures did. "
           "numberOfIterations=0 IS confirmed to be an exact identity "
           "no-op (0/442368 voxels differ from the unwarped moving image), "
           "ruling out a basic wiring error as the source. Fixed/moving "
           "role assignment (volumeA fixed, volumeB moving) was confirmed "
           "by a swap test against this fixture, the same evidence-based "
           "method as SGAC's role assignment (see src/opcodes/sgac.cpp): "
           "the swapped wiring measures RMS 21.7/ndiff 189263/442368, "
           "materially worse. Two consecutive local runs were compared "
           "bit-for-bit before comparing to the fixture, to rule out "
           "iterative/multithreaded nondeterminism as the source of any "
           "residual -- they matched exactly. No fixture exists for "
           "single/uint8/int32 or other parameters, so no agreement claim "
           "is made for them; uint8/int32 promote to float internally. The "
           "moving image is warped in its ORIGINAL (pre-histogram-match) "
           "form, per the classic ITK Demons example; matcher->GetOutput() "
           "is used only as the Demons filter's own moving-image input. "
           "This fixture cannot independently discriminate that choice "
           "(volumeB shares volumeA's exact histogram via circshift, so "
           "histogram matching is near-identity here) -- warping "
           "matcher->GetOutput() instead measures bit-identical to warping "
           "the original on this fixture.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"NumberOfHistogramLevels", "1024"},
        {"NumberOfMatchPoints", "7"},
        {"DemonNumberofIterations", "150"},
        {"DemonStandardDeviations", "1.0"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunRd<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetRdOpcode() {
  static const RdOpcode op;
  return &op;
}

}  // namespace mexitk
