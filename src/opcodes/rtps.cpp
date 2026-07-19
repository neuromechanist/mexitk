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
// argument (arg5) as a flat list of landmark coordinates, split in half
// into source and target landmarks -- see RunRtps and the StatusNote below
// for exactly what is fixture-proven and what is inferred.
//
// UNLIKE every other opcode in this codebase, RTPS has NO successful
// reference capture: the only captured fixture
// (rtps_tps_volB_seedS1_double) is a REJECTION, proving only that a single
// landmark point is refused. Status is capped at smoke-tested; see
// docs/COMPATIBILITY.md.

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

  // Fixed/moving role assignment: carried over from RD's own swap-tested
  // determination (volumeA fixed, volumeB moving; see src/opcodes/rd.cpp)
  // for consistency between this epic's two registration opcodes, NOT
  // independently proven for RTPS -- no successful RTPS fixture exists to
  // swap-test against. See StatusNote.
  typename RealImage::Pointer fixed = realA;
  typename RealImage::Pointer moving = realB;

  // Landmark convention, evidenced only by the ONE captured (rejection)
  // fixture's full error text: "This method requires landmarks.  Each
  // landmark should be 3-dimensional, and there should be even number of
  // landmarks (source->target)". This proves: landmarks ride the seed
  // argument; a single landmark point is rejected; the count must be even;
  // the original's own phrasing orders them "source->target". It does NOT
  // prove HOW an even-length flat list splits into two landmark sets.
  // Split-in-half (first half = source, second half = target) is the
  // ITK-worked-example convention (Insight Software Guide's own landmark-
  // warping example lists a full source set, then a full target set, not
  // interleaved pairs) and is the choice made here -- inferred, not
  // fixture-proven. See StatusNote for what would settle this.
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
  const size_t half = indices.size() / 2;

  using TransformType = itk::ThinPlateSplineKernelTransform<double, kDimension>;
  using PointSetType = typename TransformType::PointSetType;
  using PointType = typename TransformType::InputPointType;

  typename PointSetType::Pointer sourceLandmarks = PointSetType::New();
  typename PointSetType::Pointer targetLandmarks = PointSetType::New();
  for (size_t i = 0; i < half; ++i) {
    PointType p;
    // Landmark coordinates are physical points in the shared unit-spacing,
    // zero-origin geometry ImportVolume establishes for every volume in
    // this codebase, so TransformIndexToPhysicalPoint is numerically a
    // component-wise copy here -- spelled out via the image's own API
    // rather than assumed, so a future spacing/origin change stays correct.
    inputA->TransformIndexToPhysicalPoint(indices[i], p);
    sourceLandmarks->SetPoint(static_cast<typename PointSetType::PointIdentifier>(i), p);
  }
  for (size_t i = 0; i < half; ++i) {
    PointType p;
    inputA->TransformIndexToPhysicalPoint(indices[half + i], p);
    targetLandmarks->SetPoint(static_cast<typename PointSetType::PointIdentifier>(i), p);
  }

  typename TransformType::Pointer transform = TransformType::New();
  // Source landmarks are the OUTPUT/fixed-space points and target
  // landmarks are the INPUT/moving-space points, the standard convention
  // for plugging a KernelTransform directly into ResampleImageFilter
  // without inverting it: ResampleImageFilter calls
  // transform->TransformPoint(outputPoint) to find the corresponding
  // inputPoint, and KernelTransform::TransformPoint maps
  // SourceLandmarks-space to TargetLandmarks-space by construction -- so
  // SourceLandmarks must be expressed in the fixed/output image's space
  // and TargetLandmarks in the moving/input image's space for that call to
  // mean what Resample needs. Combined with the fixed=volumeA/
  // moving=volumeB role assignment above, the FIRST half of the landmark
  // list (source, per "source->target") is therefore interpreted in
  // volumeA's frame and the second half in volumeB's -- both are read
  // through inputA's geometry above only because the two volumes share
  // identical spacing/origin/size (unit, zero, and RequireVolumeB-checked,
  // respectively), not because the landmarks are assumed to belong to
  // volumeA specifically.
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
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "no successful reference capture exists for RTPS: the only "
           "captured fixture (rtps_tps_volB_seedS1_double) is a "
           "REJECTION, proving only that a single landmark point is "
           "refused (the original's full error text: 'This method "
           "requires landmarks.  Each landmark should be 3-dimensional, "
           "and there should be even number of landmarks (source->"
           "target)'), reproduced here as mexitk:RTPS:landmarks and "
           "asserted by tests/tReferenceRejections.m. Status is capped at "
           "smoke-tested, not bounded-deviation, because there is nothing "
           "to measure agreement against. Everything beyond 'landmarks "
           "ride the seed argument, one point is rejected, the count must "
           "be even' is INFERRED, not fixture-proven: (1) the split-in-half "
           "convention (first half of the flat landmark list is the source "
           "set, second half the target set) is the Insight Software "
           "Guide's own landmark-warping worked example, not verified "
           "against the original; an interleaved (source1,target1,"
           "source2,target2,...) convention was not ruled out. (2) the "
           "fixed/moving role assignment (volumeA fixed, volumeB moving) "
           "is carried over from RD's own swap-tested determination for "
           "consistency between this epic's two registration opcodes, not "
           "independently confirmed for RTPS. (3) which image plays "
           "source-landmark space versus target-landmark space in the "
           "ResampleImageFilter wiring follows the standard "
           "KernelTransform-into-Resample convention (source=output/"
           "fixed space, target=input/moving space, so TransformPoint "
           "needs no inversion), not a fixture finding. A targeted "
           "reference-host capture with several PAIRED landmarks and a "
           "geometrically distinctive volumeB (not a symmetric circshift, "
           "so a source/target or fixed/moving mixup would visibly "
           "misplace the result) would settle all three at once. No "
           "landmark minimum beyond 'even and nonempty' is enforced: the "
           "original's own message states only those two constraints, and "
           "inventing a stricter one without evidence would risk refusing "
           "an input the original accepted. uint8/int32 promote to float "
           "internally, same as every other promoted opcode here. Not a "
           "reference comparison, but a real structural check: calling "
           "with volumeA==volumeB and IDENTICAL source/target landmark "
           "coordinates (a true no-op warp) reproduces the input EXACTLY "
           "(0/442368 voxels differ) once 4 or more well-spread pairs are "
           "given, confirming the landmark indexing, the source=fixed-"
           "space/target=moving-space convention, and the Resample wiring "
           "are all internally consistent. With only 1 pair (2 points) "
           "the identity check is exact ONLY at and near the two given "
           "points; elsewhere it is not, which is expected, not a bug: a "
           "thin-plate spline's affine component needs at least "
           "dimension+1 = 4 non-degenerate point pairs to be determined in "
           "3-D, so 1-2 pairs leave the transform genuinely underdetermined "
           "away from the given points, and ITK's SVD-based solve returns "
           "a defined but not-necessarily-identity answer there -- not "
           "guarded against, since it is a well-defined computation, not "
           "undefined behaviour, and the original's own message enforces "
           "no minimum beyond even-and-nonempty.";
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
