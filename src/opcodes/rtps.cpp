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
// s14_rtps_landmarks.m, two rounds, nine fixtures total) then produced real
// fixtures, and the original's identity-landmark case
// (rtps_nc5_identity_double) immediately disproved that inference: feeding
// IDENTICAL source/target landmarks under a split-half reading, with
// volumeA==volumeB, did NOT reproduce the input (measured 181548/442368
// voxels differ, output mean 2.62 vs the volume's own mean 21.82). The
// convention below is the one that actually reproduces the captures; a
// second capture round then isolated exactly which landmark configurations
// leave a real, measured residual (fewer than 3 distinct landmark pairs) --
// see the StatusNote for the full evidence.

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
           "inference; a targeted reference-host capture round (s14, "
           "nine fixtures across two rounds) disproved it and pinned "
           "down the real convention. Landmarks are INTERLEAVED "
           "(source1,target1,source2,target2,...), not split into a "
           "source block then a target block: rtps_nc5_identity_double "
           "and rtps_nc5_translate_double (both volumeA==volumeB, five "
           "well-spread non-coplanar landmark pairs) share the identical "
           "interleaved point stream and the interleaved reading "
           "reproduces both at the floating-point noise floor (RMS "
           "2.12e-10 and 2.00e-10) while split-half is wrong by RMS "
           "~36-37 on both. volumeB is FIXED (source-landmark/output "
           "space) and volumeA is MOVING (target-landmark/input space, "
           "the one resampled) -- the OPPOSITE of RD's role assignment: "
           "rtps_pairs4_translate_double (an asymmetric, flipped+shifted "
           "volumeB, the decisive geometry capture) reproduces at RMS "
           "2.63e-12 with volumeB fixed, RMS 37.7 with volumeA fixed. "
           "Five of the eight successful captures reproduce at the "
           "floating-point noise floor, in two magnitude bands: three at "
           "RMS ~1e-12 (rtps_pairs4_translate_double 2.63e-12, "
           "rtps_coplanar3_distinct_double 8.15e-13, "
           "rtps_pairs3_distinct_double 5.26e-12 on macOS/6.79e-12 on "
           "Linux -- see below) and two at RMS ~2e-10 "
           "(rtps_nc5_identity_double 2.12e-10, "
           "rtps_nc5_translate_double 2.00e-10) -- not one uniform "
           "ceiling. The remaining three "
           "(rtps_pairs4_identity_double, RMS 2.226571; "
           "rtps_pair1_minimal_double, RMS 3.647131; "
           "rtps_pairs2_distinct_double, RMS 4.159985) have a real, "
           "modest, measured residual, not floating-point noise -- the "
           "round-2 follow-up captures (rtps_coplanar3_distinct_double, "
           "rtps_pairs2_distinct_double, rtps_pairs3_distinct_double) "
           "were captured specifically to isolate WHY, and narrowed it "
           "precisely: the threshold is the number of DISTINCT landmark "
           "pairs, not coplanarity and not raw pair count. "
           "rtps_coplanar3_distinct_double (3 distinct pairs, all "
           "sources coplanar) reproduces EXACTLY (RMS 8.15e-13), ruling "
           "out coplanarity as a cause -- an earlier hypothesis here, now "
           "corrected. rtps_pairs3_distinct_double (3 distinct, "
           "well-spread pairs) is likewise exact -- RMS 5.26e-12 on "
           "macOS arm64, 6.79e-12 on Linux x86_64 (both platforms are "
           "genuine floating-point noise at this magnitude; the bound in "
           "tests/tReferenceBounded.m is the MAXIMUM of the two "
           "measurements, not a single-platform number, since "
           "ThinPlateSplineKernelTransform's vnl_svd solve runs through "
           "each platform's own LAPACK/BLAS). "
           "rtps_pairs2_distinct_double (only 2 distinct pairs) has a "
           "real residual (RMS 4.159985), comparable in kind to "
           "rtps_pair1_minimal_double's single pair. "
           "rtps_pairs4_identity_double's four interleaved pairs collapse "
           "to only TWO distinct (source,target) pairs, each supplied "
           "twice (verified directly: pair 1 == pair 3 and pair 2 == pair "
           "4 exactly) -- consistent with this same threshold, since it "
           "carries the same distinct-pair count (2) as "
           "rtps_pairs2_distinct_double and a residual of the same order "
           "of magnitude. **The threshold for exact reproduction is 3 or "
           "more DISTINCT landmark pairs; fewer (whether from a genuinely "
           "small landmark count or from duplicate pairs reducing the "
           "effective count) leaves the augmented least-squares system "
           "underdetermined enough that ITK's SVD-based pseudo-inverse "
           "resolves it slightly differently between 2.4 (the original's "
           "build) and 5.4** -- the same upstream-numerics-evolution "
           "category as FCA/SNC/SWS elsewhere in this project, not a "
           "wiring error: five captures spanning coplanar and "
           "non-coplanar, identity and translation, and symmetric and "
           "asymmetric volumes all reproduce exactly under the identical "
           "wiring, which rules out a systematic error as the source of "
           "the remaining three residuals. This is a THRESHOLD, not a "
           "gradual improvement: the s14 round-2 plan predicted the "
           "residual would shrink monotonically as pair count rose from "
           "1 toward 4+, and that prediction FAILED -- 2 distinct pairs "
           "(rtps_pairs2_distinct_double, RMS 4.159985) is measurably "
           "WORSE than 1 (rtps_pair1_minimal_double, RMS 3.647131), not "
           "smaller, before reproduction jumps straight to the noise "
           "floor at 3 distinct pairs. Recorded here as a disproven "
           "assumption on purpose, the same way FDMV's accessor guess and "
           "SOT's inside-value default were recorded once measurement "
           "contradicted them. All eight successful captures and "
           "both rejections (the original single-seed fixture "
           "rtps_tps_volB_seedS1_double, and rtps_odd3_reject_double, "
           "three landmarks) are asserted in tests/tReferenceBounded.m / "
           "tests/tReferenceRejections.m. Only double has been captured; "
           "single/uint8/int32 carry no agreement claim and promote to "
           "float internally. No cap is placed on the landmark count: "
           "ThinPlateSplineKernelTransform's own ComputeWMatrix solves an "
           "augmented (N+D+1)x(N+D+1) system whose cost is O(N^3) in the "
           "number of landmark PAIRS, measured directly at N=100 (0.125s), "
           "N=300 (1.6s), N=800 (33.2s), and still running past 40s at "
           "N=2000 -- a real, deterministic cost curve a caller with a very "
           "large landmark set should expect, not a hang or a memory-safety "
           "issue (no crash or unbounded memory growth was observed at any "
           "size tested). An arbitrary cap was considered and rejected: the "
           "original's own behaviour at large N is unknown, and refusing an "
           "input the original might well have accepted would be the wrong "
           "direction for this project's accept-strictly-more policy.";
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
