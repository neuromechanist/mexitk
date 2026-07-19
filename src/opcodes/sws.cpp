// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// SWS - watershed segmentation.
// Wraps itk::WatershedImageFilter (module ITKWatersheds).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkCastImageFilter.h"
#include "itkWatershedImageFilter.h"

#include <cmath>
#include <type_traits>

namespace mexitk {
namespace {

template <typename PixelT>
using SwsRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunSws(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = SwsRealType<PixelT>;
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

  // The reference feeds the raw volume straight to the watershed; it does not
  // compute a gradient-magnitude edge map first, even though ITK's own examples
  // do. NFT relies on this, passing an inverted intensity volume (mb-double(b3))
  // rather than a gradient. Adding a gradient stage here would silently change
  // every existing caller's segmentation.
  using WatershedType = itk::WatershedImageFilter<RealImage>;
  typename WatershedType::Pointer watershed = WatershedType::New();
  watershed->SetInput(real);
  watershed->SetLevel(p[0]);
  watershed->SetThreshold(p[1]);
  watershed->Update();

  // Watershed labels are itk::IdentifierType (64-bit); the original returns
  // them in the input's own class, so a double input yields a double label
  // image.
  using LabelImage = typename WatershedType::OutputImageType;
  using CastOut = itk::CastImageFilter<LabelImage, InImage>;
  typename CastOut::Pointer cast = CastOut::New();
  cast->SetInput(watershed->GetOutput());
  cast->Update();
  ctx.plhs[0] = ExportVolume<PixelT>(cast->GetOutput());
}

class SwsOpcode : public Opcode {
 public:
  const char* Name() const override { return "SWS"; }
  Category GetCategory() const override { return Category::kSegmentation; }
  const char* Description() const override {
    return "Watershed segmentation; returns a label image";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "region COUNT matches the original exactly at every tested setting, "
           "and at level=0.5 the partition is identical up to relabeling, but "
           "label images are not bit-identical at fine levels. For the "
           "extract-region-at-seed pattern (c==c(seed)), 11 of 16 tested "
           "seed/parameter combinations reproduce the region exactly; worst "
           "observed Dice was 0.718. seed argument is accepted and ignored, "
           "matching the original";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"SETLEVEL", "0.0-1.0"},
        {"SETTHRESHOLD", "0.0-1.0"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    // Neither level nor threshold has a prior mexitk-level sign/range
    // constraint (the "0.0-1.0" registry hint above is documentation, not
    // an enforced range, and is left that way here too -- only the
    // non-finite gap is closed, nothing tightened beyond it). Re-verified
    // empirically for this hardening pass, per param, in isolated runs:
    // level=NaN and level=+Inf each silently returned a defined-looking
    // but degenerate labeling (no exception); threshold=NaN silently
    // returned a defined-looking labeling too; threshold=+Inf was the one
    // combination already caught, by luck rather than design, by ITK's own
    // internal consistency check inside WatershedSegmentTreeGenerator
    // (surfaced as mexitk:itkException) -- not a guarantee for the other
    // three non-finite cases, which this guard now covers uniformly and
    // predictably instead of relying on that inconsistent side effect.
    const std::vector<double>& p = *ctx.params;
    if (!std::isfinite(p[0])) {
      throw OpcodeError("mexitk:SWS:level", "level must be finite.");
    }
    if (!std::isfinite(p[1])) {
      throw OpcodeError("mexitk:SWS:threshold", "threshold must be finite.");
    }
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunSws<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetSwsOpcode() {
  static const SwsOpcode op;
  return &op;
}

}  // namespace mexitk
