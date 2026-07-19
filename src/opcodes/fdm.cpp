// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FDM / FDMV - Danielsson distance map.
// Wraps itk::DanielssonDistanceMapImageFilter (module ITKDistanceMap), plus
// itk::PermuteAxesImageFilter (module ITKImageGrid) and
// itk::RescaleIntensityImageFilter (module ITKImageIntensity).
//
// FDM and FDMV are the same filter read via two different accessors:
// GetDistanceMap() (== GetOutput(), output 0) for FDM, GetVoronoiMap()
// (output 1) for FDMV. See FdmvOpcode::StatusNote for the FDMV accessor
// caveat.
//
// Reimplemented (Epic 2 Phase 3) to reproduce the original's actual
// pipeline, fixture-verified rather than assumed:
//   1. Permute the input's X/Y axes (order [1,0,2]) before running
//      Danielsson. The original computes distance in its own import
//      orientation, which is dim2-fastest -- the same underlying X-named-
//      to-MATLAB-dim-2/Y-named-to-dim-1 convention documented for
//      FF/FD/FMEDIAN/FMEAN/SNC/FVBIH, but FDM/FDMV take no X/Y-named
//      parameter to swap, so the swap is applied structurally to the whole
//      volume instead. The permutation is applied again (same order --
//      a single-transposition permutation is its own inverse) on the way
//      out.
//   2. Danielsson runs NATIVELY at the input's own pixel type -- NOT
//      promoted to float for integral input. This was verified, not
//      assumed: a float-promoted intermediate (matching the pattern used
//      elsewhere in this codebase for FCA/FD/etc.) reproduces double and
//      single exactly but disagrees with the original on ~47-61% of
//      voxels for uint8/int32; the native-pixel-type computation instead
//      reproduces int32 BIT-EXACT and uint8 to within a small measured
//      residual (see FdmOpcode::StatusNote). The original was generated
//      from an ITK 2.4 example that instantiates
//      DanielssonDistanceMapImageFilter on a single pixel type throughout
//      (input == output == Voronoi), and this codebase now matches that
//      instantiation pattern exactly.
//   3. FDM reads GetDistanceMap(); FDMV builds a label image (sequential
//      IDs in the permuted image's own scan order, which IS dim2-fastest
//      relative to the original) and reads GetVoronoiMap() from a second
//      Danielsson pass over that label image.
//   4. Export: FDM, and FDMV for double/single/int32, rescale the raw ITK
//      output to a FIXED range via itk::RescaleIntensityImageFilter:
//      [0, 65535] for double/single/int32 output, [0, 255] for uint8's FDM
//      -- the original's own fixed "typeMax" convention, NOT
//      NumericTraits<PixelT>::max() (which would give realmax('double') on
//      double, wrong). FDMV's uint8 output is the one exception: it is
//      NOT linearly rescaled at all. It is a direct narrowing cast of the
//      raw sequential Voronoi id (minus one) into uint8, wrapping via
//      standard unsigned overflow -- verified against fixtures (see
//      FdmvOpcode::StatusNote); the original evidently took a different
//      code path for its uint8 instantiation than for the other three
//      types, plausible given the original was Perl-generated per pixel
//      type from an ITK 2.4 example rather than hand-written once.

#include "mexitk_common.h"
#include "opcode.h"

#include "itkDanielssonDistanceMapImageFilter.h"
#include "itkImageRegionConstIterator.h"
#include "itkPermuteAxesImageFilter.h"
#include "itkRescaleIntensityImageFilter.h"

#include <cstdint>
#include <type_traits>

namespace mexitk {
namespace {

const std::vector<ParamSpec>& DanielssonParams() {
  static const std::vector<ParamSpec> kNoParams = {};
  return kNoParams;
}

// The original's own fixed rescale ceiling: 65535 for double/single/int32
// output, 255 for uint8. NOT itk::NumericTraits<PixelT>::max() -- that
// would give realmax('double') on double output, which the reference
// fixtures disprove.
template <typename PixelT>
constexpr double RescaleCeiling() {
  return std::is_same<PixelT, std::uint8_t>::value ? 255.0 : 65535.0;
}

// Applies the X/Y-swap permutation (order [1,0,2]); self-inverse, so the
// same helper both permutes into the original's import orientation and
// permutes the final result back out of it.
template <typename PixelT>
typename Image3<PixelT>::Pointer PermuteXY(const Image3<PixelT>* img) {
  using ImageT = Image3<PixelT>;
  using PermuteFilter = itk::PermuteAxesImageFilter<ImageT>;
  typename PermuteFilter::Pointer permute = PermuteFilter::New();
  permute->SetInput(img);
  typename PermuteFilter::PermuteOrderArrayType order;
  order[0] = 1;
  order[1] = 0;
  order[2] = 2;
  permute->SetOrder(order);
  permute->Update();
  return permute->GetOutput();
}

// Rescales a source image to [0, RescaleCeiling] in the target PixelT,
// mirroring the original's own affine-then-truncate export:
// RescaleIntensityImageFilter auto-computes the source's actual min/max
// from the data (not something this code sets), computes
// out = (x - inMin) * scale + outMin in its internal RealType, and casts
// to PixelT via static_cast (truncation toward zero for positive values),
// which is exactly what the fixtures show.
template <typename PixelT, typename SrcPixelT>
typename Image3<PixelT>::Pointer RescaleTo(const Image3<SrcPixelT>* src) {
  using SrcImage = Image3<SrcPixelT>;
  using DstImage = Image3<PixelT>;
  using RescaleFilter = itk::RescaleIntensityImageFilter<SrcImage, DstImage>;
  typename RescaleFilter::Pointer rescale = RescaleFilter::New();
  rescale->SetInput(src);
  rescale->SetOutputMinimum(static_cast<PixelT>(0));
  rescale->SetOutputMaximum(static_cast<PixelT>(RescaleCeiling<PixelT>()));
  rescale->Update();
  return rescale->GetOutput();
}

// FDMV's uint8 export: a direct narrowing cast of (id - 1), NOT a linear
// rescale -- see the file header comment. Wraps via standard unsigned
// overflow (well-defined in C++, unlike a signed narrowing cast). Every
// Voronoi map value is >= 1 (no background 0 remains once every voxel is
// assigned to its nearest object; see the FDMV pipeline comment), so
// value - 1 is always non-negative and this never depends on
// implementation-defined negative-to-unsigned conversion.
template <typename PixelT, typename SrcPixelT>
typename Image3<PixelT>::Pointer WrapNarrow(const Image3<SrcPixelT>* src) {
  using SrcImage = Image3<SrcPixelT>;
  using DstImage = Image3<PixelT>;
  typename DstImage::Pointer out = DstImage::New();
  out->SetRegions(src->GetLargestPossibleRegion());
  out->Allocate();
  const SrcPixelT* srcBuf = src->GetBufferPointer();
  PixelT* dstBuf = out->GetBufferPointer();
  const itk::SizeValueType n = src->GetLargestPossibleRegion().GetNumberOfPixels();
  for (itk::SizeValueType i = 0; i < n; ++i) {
    dstBuf[i] = static_cast<PixelT>(srcBuf[i] - SrcPixelT{1});
  }
  return out;
}

// Both FDM and FDMV refuse an all-background input: the original's
// distance/Voronoi computation over zero objects is meaningless (measured:
// an all-zero uint8 volume on this project's reference geometry yields
// distances of roughly 294 to 443, an artifact of the filter's internal
// initialization when nothing is closer, not a defined answer to "distance
// to the nearest object" when there is no object). See deliberate
// deviation entry in docs/COMPATIBILITY.md.
template <typename PixelT>
void RequireAtLeastOneObjectVoxel(const Image3<PixelT>* img) {
  itk::ImageRegionConstIterator<Image3<PixelT>> it(img, img->GetLargestPossibleRegion());
  for (it.GoToBegin(); !it.IsAtEnd(); ++it) {
    if (it.Get() != PixelT{}) {
      return;
    }
  }
  throw OpcodeError("mexitk:fdm:noObject",
                    "FDM/FDMV require at least one nonzero voxel in the input volume.");
}

template <typename PixelT>
void RunFdm(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);
  RequireAtLeastOneObjectVoxel<PixelT>(input);

  typename InImage::Pointer permuted = PermuteXY<PixelT>(input);

  // Native pixel type throughout (input == output == Voronoi); see the
  // file header comment for why this replaced an earlier float-promoted
  // design.
  using FilterType = itk::DanielssonDistanceMapImageFilter<InImage, InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(permuted);
  filter->Update();

  typename InImage::Pointer rescaled = RescaleTo<PixelT, PixelT>(filter->GetDistanceMap());
  typename InImage::Pointer restored = PermuteXY<PixelT>(rescaled);

  ctx.plhs[0] = ExportVolume<PixelT>(restored);
}

template <typename PixelT>
void RunFdmv(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  // Label image type: sequential object-voxel IDs. int32_t comfortably
  // holds N (the object-voxel count) for any volume this project handles;
  // it is a local computation detail never exposed to MATLAB, so it does
  // not need to match PixelT.
  using LabelT = std::int32_t;
  using LabelImage = Image3<LabelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);
  RequireAtLeastOneObjectVoxel<PixelT>(input);

  typename InImage::Pointer permuted = PermuteXY<PixelT>(input);

  // Sequential IDs assigned in the permuted image's own scan order --
  // which is dim2-fastest relative to the original, matching the
  // original's own import orientation for this opcode pair.
  typename LabelImage::Pointer labelImg = LabelImage::New();
  labelImg->SetRegions(permuted->GetLargestPossibleRegion());
  labelImg->Allocate();

  const PixelT* srcBuf = permuted->GetBufferPointer();
  LabelT* dstBuf = labelImg->GetBufferPointer();
  const itk::SizeValueType numPixels =
      permuted->GetLargestPossibleRegion().GetNumberOfPixels();
  LabelT nextId = 1;
  for (itk::SizeValueType i = 0; i < numPixels; ++i) {
    if (srcBuf[i] != PixelT{}) {
      dstBuf[i] = nextId;
      ++nextId;
    } else {
      dstBuf[i] = LabelT{};
    }
  }

  // Native label pixel type throughout, matching FDM's own native-type
  // finding: the distance-map output (unused here; only GetVoronoiMap()
  // is read) stays at LabelT rather than a separately promoted type.
  using FilterType = itk::DanielssonDistanceMapImageFilter<LabelImage, LabelImage, LabelImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(labelImg);
  // The label image already carries distinct per-object IDs as its own
  // pixel values; InputIsBinary (default off) must stay off so the filter
  // uses those IDs directly as Voronoi labels instead of auto-generating
  // its own. Explicit for clarity, even though it matches ITK's default.
  // (ITK 5.4's own InputIsBinary=true path does not actually assign a
  // unique id per object voxel -- checked directly in
  // itkDanielssonDistanceMapImageFilter.hxx, its PrepareData() sets every
  // foreground voxel to the SAME constant label under that flag -- so it
  // could not have reproduced the original's per-object Voronoi partition
  // even if used.)
  filter->InputIsBinaryOff();
  filter->Update();

  // uint8 output does not go through the linear rescale: see the file
  // header comment and WrapNarrow's own comment.
  typename InImage::Pointer rescaled;
  if constexpr (std::is_same<PixelT, std::uint8_t>::value) {
    rescaled = WrapNarrow<PixelT, LabelT>(filter->GetVoronoiMap());
  } else {
    rescaled = RescaleTo<PixelT, LabelT>(filter->GetVoronoiMap());
  }
  typename InImage::Pointer restored = PermuteXY<PixelT>(rescaled);

  ctx.plhs[0] = ExportVolume<PixelT>(restored);
}

class FdmOpcode : public Opcode {
 public:
  const char* Name() const override { return "FDM"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Danielsson distance map (distance output)";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "bit-exact against every double/single/int32 fixture, asserted "
           "by tests/tReferenceExact.m; uint8 has a small measured, "
           "bounded residual, asserted by tests/tReferenceBounded.m -- not "
           "a validated claim overall because of that uint8 gap. "
           "Reproduces the original's own "
           "pipeline: X/Y axes permuted before and after the Danielsson "
           "pass (see docs/COMPATIBILITY.md, second capture campaign "
           "findings), distance computed NATIVELY at the input's own pixel "
           "type (no float promotion), then rescaled via "
           "RescaleIntensityImageFilter to a FIXED ceiling -- 65535 for "
           "double/single/int32 output, 255 for uint8 -- not the pixel "
           "type's own max. double/single/int32 are bit-exact against "
           "every captured fixture; uint8 has a small measured residual "
           "(around 0.2% of voxels, max absolute difference 6), likely "
           "reflecting a lower-precision internal distance representation "
           "in the original's own uint8 instantiation -- see "
           "docs/COMPATIBILITY.md for the exact measured numbers. "
           "All-background input (no nonzero voxel) is rejected "
           "(mexitk:fdm:noObject): the original's own distance field over "
           "zero objects is a meaningless artifact of its internal "
           "initialization, not a defined answer.";
  }

  const std::vector<ParamSpec>& Params() const override { return DanielssonParams(); }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA), [&](auto tag) {
      RunFdm<typename decltype(tag)::type>(ctx);
    });
  }
};

class FdmvOpcode : public Opcode {
 public:
  const char* Name() const override { return "FDMV"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Danielsson distance map (Voronoi output)";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "bit-exact against every single/int32 fixture, asserted by "
           "tests/tReferenceExact.m; double and uint8 each have a small "
           "measured, bounded residual (different mechanisms -- see "
           "below), asserted by tests/tReferenceBounded.m -- not a "
           "validated claim overall because of those gaps. The \"V = Voronoi (not "
           "Vector) map\" accessor identification is now fixture-"
           "confirmed, not just secondary-sourced: verified formula at "
           "object voxels is output = (id-1) * typeMax/(N-1) for "
           "double/single/int32, where id is the 1-based sequential number "
           "of the object voxel in the permuted image's own (dim2-fastest) "
           "scan order and N is the object-voxel count -- this disproves "
           "an earlier assumption that Voronoi labels were drawn from the "
           "input's own pixel values; every object voxel gets a distinct "
           "sequential ID regardless of its input intensity. single and "
           "int32 are bit-exact against every captured fixture; double has "
           "a tiny measured residual (RMS around 3e-12, max absolute "
           "difference around 7e-12, on roughly a third of voxels) that "
           "persists under an alternative, manually-ordered rescale "
           "computation too, consistent with floating-point op-order "
           "non-associativity right at double precision's own limit rather "
           "than a wrong formula -- int32's floor-cast and single's "
           "float32 precision both absorb the same tiny difference "
           "invisibly, only double's full precision surfaces it. See "
           "docs/COMPATIBILITY.md for the exact measured numbers. uint8 "
           "output does NOT follow that rescale: it is a direct "
           "narrowing cast of (id-1) into uint8 with standard unsigned "
           "wraparound (mod 256), matched to 99.4% of voxels on the "
           "reference volume; the remaining residual is consistent with "
           "ITK 2.4-vs-5.4 Voronoi tie-break divergence at equidistant "
           "background voxels (the fixture picks an adjacent object id, "
           "off by exactly one, at every inspected residual voxel), not a "
           "formula error -- see docs/COMPATIBILITY.md. Pipeline: X/Y axes "
           "permuted, a sequential-ID label image built in scan order, a "
           "second Danielsson pass over that label image (native pixel "
           "type, no float promotion, matching FDM's own finding) with "
           "InputIsBinary off, GetVoronoiMap() exported per the rule "
           "above, axes permuted back. All-background input is rejected "
           "the same way as FDM (mexitk:fdm:noObject). N==1 (a single "
           "object voxel) is a degenerate rescale (inMin==inMax) on the "
           "double/single/int32 path; RescaleIntensityImageFilter maps "
           "that to OutputMinimum by its own defined behaviour -- no "
           "fixture covers this case, so no agreement claim is made for "
           "it.";
  }

  const std::vector<ParamSpec>& Params() const override { return DanielssonParams(); }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA), [&](auto tag) {
      RunFdmv<typename decltype(tag)::type>(ctx);
    });
  }
};

}  // namespace

const Opcode* GetFdmOpcode() {
  static const FdmOpcode op;
  return &op;
}

const Opcode* GetFdmvOpcode() {
  static const FdmvOpcode op;
  return &op;
}

}  // namespace mexitk
