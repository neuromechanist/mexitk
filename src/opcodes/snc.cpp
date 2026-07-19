// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// SNC - neighborhood-connected region growing.
// Wraps itk::NeighborhoodConnectedImageFilter (module ITKRegionGrowing).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkNeighborhoodConnectedImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunSnc(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  using FilterType = itk::NeighborhoodConnectedImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);

  const std::vector<double>& p = *ctx.params;
  // The 2006 original maps X-named parameters to MATLAB dim 2 (ITK axis 1)
  // and Y-named parameters to MATLAB dim 1 (ITK axis 0); Z is unchanged.
  // Applied here for family consistency with FMEDIAN/FMEAN/FVBIH, which
  // share the same XRADIUS/YRADIUS-style registry naming and are all
  // fixture-proven bit-exact under this exact swap. Seeds are NOT affected
  // by this convention -- they stay matrix-order via SeedPointsToIndices,
  // unchanged below.
  //
  // Unlike its box-filter siblings, SNC does NOT reach bit-exactness even
  // with the swap applied: a symmetric-radius fixture where the swap is a
  // total no-op (snc_r0_band_seedS1_double, radius [0,0,0]) still deviates
  // on 36573/442368 voxels, so a separate, axis-order-independent
  // divergence exists in NeighborhoodConnectedImageFilter itself between
  // ITK 2.4 and 5.4 -- the same class of upstream-algorithm evolution
  // already documented for FCA/SWS. Radius [1,1,1] and the base threshold
  // fixtures ARE bit-exact; see docs/COMPATIBILITY.md for the full
  // per-fixture measurement.
  typename InImage::SizeType radius;
  // Validate in declared parameter order; as call arguments the evaluation
  // order (and so which name an error cites) would be unspecified.
  const auto rx = CastParam<itk::SizeValueType>(p[0], "SNC", "RadiusX");
  const auto ry = CastParam<itk::SizeValueType>(p[1], "SNC", "RadiusY");
  const auto rz = CastParam<itk::SizeValueType>(p[2], "SNC", "RadiusZ");
  AssignSwappedXY(radius, rx, ry, rz);
  filter->SetRadius(radius);
  filter->SetLower(CastParam<PixelT>(p[3], "SNC", "LowerThreshold"));
  filter->SetUpper(CastParam<PixelT>(p[4], "SNC", "UpperThreshold"));
  filter->SetReplaceValue(CastParam<PixelT>(p[5], "SNC", "ReplaceValue"));

  for (const auto& idx :
       SeedPointsToIndices(*ctx.seeds, input->GetLargestPossibleRegion().GetSize())) {
    filter->AddSeed(idx);
  }

  filter->Update();
  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class SncOpcode : public Opcode {
 public:
  const char* Name() const override { return "SNC"; }
  Category GetCategory() const override { return Category::kSegmentation; }
  const char* Description() const override {
    return "Neighborhood-connected region growing from seed(s)";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "bit-exact against radius [1,1,1] and the base threshold "
           "fixtures, asserted by tests/tReferenceExact.m; RadiusX maps "
           "onto ITK axis 1 (MATLAB dim 2), RadiusY onto ITK axis 0 "
           "(MATLAB dim 1), matching the original. Other radii have a "
           "measured, bounded residual, asserted by "
           "tests/tReferenceBounded.m: NeighborhoodConnectedImageFilter "
           "itself diverges from the original independent of axis order "
           "(measured on a swap-invariant symmetric-radius fixture), so "
           "this opcode is not bit-exact overall. See "
           "docs/COMPATIBILITY.md for the measured bounds. An empty seed "
           "list yields an all-zero output; the captured "
           "snc_emptyseed_double fixture is NOT a counterexample to that "
           "-- see tests/tReferenceRejections.m for why.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"RadiusX", "2"},
        {"RadiusY", "2"},
        {"RadiusZ", "2"},
        {"LowerThreshold", nullptr},
        {"UpperThreshold", nullptr},
        {"ReplaceValue", "255"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunSnc<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetSncOpcode() {
  static const SncOpcode op;
  return &op;
}

}  // namespace mexitk
