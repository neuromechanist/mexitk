// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// RTPS - thin-plate-spline landmark warping. Wraps
// itk::ThinPlateSplineKernelTransform (module ITKTransform) feeding
// itk::ResampleImageFilter (module ITKImageGrid, already present for FF).
// The registry lists ZERO parameters for RTPS: every input rides the seed
// argument (arg5) as a flat list of landmark coordinates -- see RunRtps and
// the StatusNote below for exactly what is fixture-proven.
//
// Epic 4 Phase 1's own initial implementation (split-in-half landmarks,
// fixed=volumeA/moving=volumeB) was an INFERENCE from the ITK worked-example
// convention, made with no successful reference capture to check it against.
// A targeted reference-host capture round (s14, tools/capture_reference/
// s14_rtps_landmarks.m) then produced six real fixtures, and the original's
// identity-landmark case (rtps_nc5_identity_double) immediately disproved
// that inference: feeding IDENTICAL source/target landmarks under a
// split-half reading, with volumeA==volumeB, did NOT reproduce the input
// (measured 181548/442368 voxels differ, output mean 2.62 vs the volume's
// own mean 21.82). The convention below is the one that actually reproduces
// the captures; see the StatusNote for the full evidence.

#include "mexitk_common.h"
#include "opcode.h"

#include "itkResampleImageFilter.h"
#include "itkThinPlateSplineKernelTransform.h"

#include <type_traits>

namespace mexitk {
namespace {

// Same promote-integral-to-float policy as RD and every other real-pixel-
// only filter in this codebase; see FcaRealType's comment in fca.cpp.
template <typename PixelT>
using RtpsRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunRtps(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = RtpsRealType<PixelT>;
  using RealImage = Image3<RealT>;

  RequireVolumeB(ctx.volumeA, ctx.volumeB, "RTPS");

  typename InImage::Pointer inputA = ImportVolume<PixelT>(ctx.volumeA);
  typename InImage::Pointer inputB = ImportVolume<PixelT>(ctx.volumeB);
  typename RealImage::Pointer realA = PromoteToReal<PixelT, RealT>(inputA);
  typename RealImage::Pointer realB = PromoteToReal<PixelT, RealT>(inputB);

  // Fixed/moving role assignment: volumeB is FIXED (the output/source-
  // landmark space), volumeA is MOVING (the input/target-landmark space
  // that gets resampled). This is the OPPOSITE of RD's own assignment
  // (volumeA fixed, volumeB moving) -- carrying RD's role over to RTPS was
  // Phase 1's original assumption, and the s14 captures disproved it
  // directly: rtps_pairs4_translate_double (an asymmetric, flipped+shifted
  // volumeB) is the decisive capture, and it reproduces bit-close (RMS
  // 2.6e-12) only with volumeB as fixed; the volumeA-fixed wiring measures
  // RMS 37.7, not even close. See StatusNote.
  typename RealImage::Pointer fixed = realB;
  typename RealImage::Pointer moving = realA;

  // Landmark convention, now fixture-proven (s14 captures), NOT the
  // split-in-half inference Phase 1 shipped with: the flat landmark list is
  // INTERLEAVED (source1,target1,source2,target2,...), not a full source
  // block followed by a full target block. Proven by rtps_nc5_identity_double
  // and rtps_nc5_translate_double: both use volumeA==volumeB and share the
  // exact same interleaved point stream (only the second half of each
  // POINT differs between the two captures), and the interleaved reading
  // reproduces both at the floating-point noise floor (RMS ~2e-10) while
  // the split-half reading is wrong by RMS ~36-37 on both. See StatusNote.
  const std::vector<double>& seeds = *ctx.seeds;
  if (seeds.empty()) {
    throw OpcodeError("mexitk:RTPS:landmarks",
                      "RTPS requires landmarks. Each landmark should be "
                      "3-dimensional, and there must be an even number of "
                      "landmarks (source landmarks, then target landmarks).");
  }
  // seeds.size() is already guaranteed a multiple of kDimension by
  // mexFunction's central seed-array validation (src/mexitk.cpp), so
  // dividing by kDimension here is exact.
  const size_t numLandmarks = seeds.size() / kDimension;
  if (numLandmarks % 2 != 0) {
    throw OpcodeError("mexitk:RTPS:landmarks",
                      "RTPS requires landmarks. Each landmark should be "
                      "3-dimensional, and there must be an even number of "
                      "landmarks (source landmarks, then target landmarks).");
  }

  // Landmarks are validated and converted through the SAME 1-based,
  // matrix-order, bounds-checked convention every other seeded opcode
  // uses (SeedPointsToIndices; see docs/COMPATIBILITY.md, "Seed
  // coordinates are 1-based..."), rather than treating them as unbounded
  // continuous physical points: no evidence distinguishes a "landmark"
  // from any other seed in the original's own calling convention, and
  // reusing this helper keeps the interpretation consistent with the rest
  // of the codebase. Bounds are checked against volumeA's size for both
  // halves: RequireVolumeB above already guarantees volumeB is the exact
  // same per-axis size, so this is not a narrowing of the valid domain for
  // either landmark set.
  const std::vector<itk::Index<kDimension>> indices =
      SeedPointsToIndices(seeds, inputA->GetLargestPossibleRegion().GetSize());
  const size_t numPairs = indices.size() / 2;

  using TransformType = itk::ThinPlateSplineKernelTransform<double, kDimension>;
  using PointSetType = typename TransformType::PointSetType;
  using PointType = typename TransformType::InputPointType;

  typename PointSetType::Pointer sourceLandmarks = PointSetType::New();
  typename PointSetType::Pointer targetLandmarks = PointSetType::New();
  for (size_t i = 0; i < numPairs; ++i) {
    PointType ps, pt;
    // Landmark coordinates are physical points in the shared unit-spacing,
    // zero-origin geometry ImportVolume establishes for every volume in
    // this codebase, so TransformIndexToPhysicalPoint is numerically a
    // component-wise copy here -- spelled out via the image's own API
    // rather than assumed, so a future spacing/origin change stays correct.
    inputA->TransformIndexToPhysicalPoint(indices[2 * i], ps);
    inputA->TransformIndexToPhysicalPoint(indices[2 * i + 1], pt);
    sourceLandmarks->SetPoint(static_cast<typename PointSetType::PointIdentifier>(i), ps);
    targetLandmarks->SetPoint(static_cast<typename PointSetType::PointIdentifier>(i), pt);
  }

  typename TransformType::Pointer transform = TransformType::New();
  // Source landmarks are the OUTPUT/fixed-space points (volumeB's frame)
  // and target landmarks are the INPUT/moving-space points (volumeA's
  // frame) -- the standard convention for plugging a KernelTransform
  // directly into ResampleImageFilter without inverting it:
  // ResampleImageFilter calls transform->TransformPoint(outputPoint) to
  // find the corresponding inputPoint, and KernelTransform::TransformPoint
  // maps SourceLandmarks-space to TargetLandmarks-space by construction.
  // Both landmark sets are read through inputA's geometry only because
  // volumeA and volumeB share identical spacing/origin (unit, zero) --
  // not because either landmark set is assumed to "belong" to volumeA.
  transform->SetSourceLandmarks(sourceLandmarks);
  transform->SetTargetLandmarks(targetLandmarks);
  transform->ComputeWMatrix();

  using ResampleFilter = itk::ResampleImageFilter<RealImage, RealImage>;
  typename ResampleFilter::Pointer resample = ResampleFilter::New();
  resample->SetInput(moving);
  resample->SetTransform(transform);
  resample->SetOutputParametersFromImage(fixed);
  resample->Update();

  ctx.plhs[0] = ExportPromoted<PixelT, RealT>(resample->GetOutput());
}

class RtpsOpcode : public Opcode {
 public:
  const char* Name() const override { return "RTPS"; }
  Category GetCategory() const override { return Category::kRegistration; }
  const char* Description() const override { return "Thin-plate-spline landmark warping"; }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "Epic 4 Phase 1's original implementation (split-in-half "
           "landmarks, fixed=volumeA/moving=volumeB) was an unproven "
           "inference; a targeted reference-host capture round (s14, six "
           "fixtures) disproved it and pinned down the real convention. "
           "Landmarks are INTERLEAVED (source1,target1,source2,target2,"
           "...), not split into a source block then a target block: "
           "rtps_nc5_identity_double and rtps_nc5_translate_double (both "
           "volumeA==volumeB, five well-spread non-coplanar landmark "
           "pairs) share the identical interleaved point stream and the "
           "interleaved reading reproduces both at the floating-point "
           "noise floor (RMS 2.12e-10 and 2.00e-10) while split-half is "
           "wrong by RMS ~36-37 on both. volumeB is FIXED (source-"
           "landmark/output space) and volumeA is MOVING (target-landmark"
           "/input space, the one resampled) -- the OPPOSITE of RD's role "
           "assignment: rtps_pairs4_translate_double (an asymmetric, "
           "flipped+shifted volumeB, the decisive geometry capture) "
           "reproduces at RMS 2.63e-12 with volumeB fixed, RMS 37.7 with "
           "volumeA fixed. Three of five successful captures are exact at "
           "the floating-point noise floor this way "
           "(rtps_nc5_identity_double, rtps_nc5_translate_double, "
           "rtps_pairs4_translate_double); the other two "
           "(rtps_pairs4_identity_double, RMS 2.226571; "
           "rtps_pair1_minimal_double, RMS 3.647131) have a real, modest, "
           "measured residual, not floating-point noise. Both are "
           "landmark configurations that are structurally degenerate for "
           "a thin-plate spline, not the well-posed cases: "
           "rtps_pairs4_identity_double's four interleaved pairs collapse "
           "to only two DISTINCT (source,target) pairs, each supplied "
           "twice (verified directly: pair 1 == pair 3 and pair 2 == pair "
           "4 exactly), a rank-deficient landmark system; "
           "rtps_pair1_minimal_double supplies only one pair, far below "
           "the four non-degenerate pairs a 3-D thin-plate spline's affine "
           "component needs to be well-determined. Both residuals are "
           "consistent with ITK's SVD-based pseudo-inverse resolving a "
           "near-singular system slightly differently between 2.4 (the "
           "original's build) and 5.4, the same upstream-numerics-"
           "evolution category as FCA/SNC/SWS elsewhere in this project, "
           "not a wiring error -- the three well-posed captures above rule "
           "out a wiring bug as the explanation, since the wiring is "
           "identical across all five. All five successful captures and "
           "both rejections (the original single-seed fixture "
           "rtps_tps_volB_seedS1_double, and rtps_odd3_reject_double, "
           "three landmarks) are asserted in tests/tReferenceBounded.m / "
           "tests/tReferenceRejections.m. Only double has been captured; "
           "single/uint8/int32 carry no agreement claim and promote to "
           "float internally.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {};
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunRtps<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetRtpsOpcode() {
  static const RtpsOpcode op;
  return &op;
}

}  // namespace mexitk
