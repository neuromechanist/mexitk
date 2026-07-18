// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FDM / FDMV - Danielsson distance map.
// Wraps itk::DanielssonDistanceMapImageFilter (module ITKDistanceMap).
//
// FDM and FDMV are the same filter read via two different accessors:
// GetDistanceMap() (== GetOutput(), output 0) for FDM, GetVoronoiMap()
// (output 1) for FDMV. See FdmvOpcode::StatusNote for the FDMV accessor
// caveat.

#include "mexitk_common.h"
#include "opcode.h"

#include "itkDanielssonDistanceMapImageFilter.h"

#include <type_traits>

namespace mexitk {
namespace {

const std::vector<ParamSpec>& DanielssonParams() {
  static const std::vector<ParamSpec> kNoParams = {};
  return kNoParams;
}

// The distance map (docs/itk_opcode_mapping.md: "typically float") is always
// computed at a floating-point type, matching FCA's promotion predicate: a
// distance can exceed an integral PixelT's range even for a modest volume
// (e.g. ~443 across this project's 128x128x27 reference volume's diagonal),
// and casting an out-of-range value into an integral type is undefined
// behaviour in C++, not merely lossy. float/double input compute natively.
template <typename PixelT>
using FdmRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

// Voronoi image type defaults to InImage regardless of PixelT: Voronoi labels
// are drawn from the input's own pixel values (docs/itk_opcode_mapping.md),
// so they are always in range and need no promotion or clamping. All
// optional flags (SquaredDistance/InputIsBinary/UseImageSpacing) are left at
// their ITK defaults.
template <typename PixelT>
void RunDanielsson(OpContext& ctx, bool wantVoronoi) {
  using InImage = Image3<PixelT>;
  using RealT = FdmRealType<PixelT>;
  using RealImage = Image3<RealT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  using FilterType = itk::DanielssonDistanceMapImageFilter<InImage, RealImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);
  filter->Update();

  if (wantVoronoi) {
    ctx.plhs[0] = ExportVolume<PixelT>(filter->GetVoronoiMap());
    return;
  }

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(filter->GetDistanceMap());
  } else {
    // ClampExport saturates into [lowest, max] of the target pixel type and
    // maps non-finite values to 0, instead of itk::ClampImageFilter's plain
    // static_cast fallthrough for NaN (undefined behaviour). In-range
    // distances are unaffected: this is the same bounds check and the same
    // in-range cast ITK's own Clamp functor performs.
    ctx.plhs[0] = ClampExport<PixelT, RealT>(filter->GetDistanceMap());
  }
}

class FdmOpcode : public Opcode {
 public:
  const char* Name() const override { return "FDM"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Danielsson distance map (distance output)";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists. "
           "Distance is computed in float and saturates at the pixel-type "
           "max on integral (uint8/int32) input.";
  }

  const std::vector<ParamSpec>& Params() const override { return DanielssonParams(); }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA), [&](auto tag) {
      RunDanielsson<typename decltype(tag)::type>(ctx, /*wantVoronoi=*/false);
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
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists. The "
           "\"V = Voronoi (not Vector) map\" accessor identification rests on "
           "secondary sourcing (a Vincent Chu opcode table) and is unconfirmed "
           "against MATITK source; itk::DanielssonDistanceMapImageFilter also "
           "exposes a distinct third accessor, GetVectorDistanceMap(), on the "
           "same class. See docs/itk_opcode_mapping.md (FDMV, Drift/risk).";
  }

  const std::vector<ParamSpec>& Params() const override { return DanielssonParams(); }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA), [&](auto tag) {
      RunDanielsson<typename decltype(tag)::type>(ctx, /*wantVoronoi=*/true);
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
