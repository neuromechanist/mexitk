// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FMEDIAN - median filter.
// Wraps itk::MedianImageFilter (module ITKSmoothing).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkMedianImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunFmedian(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::MedianImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);

  // The 2006 original maps X-named parameters to MATLAB dim 2 (ITK axis 1)
  // and Y-named parameters to MATLAB dim 1 (ITK axis 0); Z is unchanged.
  // Proven by fixture evidence: fmedian_r3_1_1 (XRADIUS=3, asymmetric)
  // deviates under the unswapped mapping, while fmedian_r1_1_3 (XRADIUS=
  // YRADIUS=1, symmetric so the swap is a no-op) is already exact. See
  // docs/COMPATIBILITY.md, second capture campaign findings.
  typename FilterType::RadiusType radius;
  radius[0] = CastParam<itk::SizeValueType>(p[1], "FMEDIAN", "YRADIUS");
  radius[1] = CastParam<itk::SizeValueType>(p[0], "FMEDIAN", "XRADIUS");
  radius[2] = CastParam<itk::SizeValueType>(p[2], "FMEDIAN", "ZRADIUS");
  filter->SetRadius(radius);
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class FmedianOpcode : public Opcode {
 public:
  const char* Name() const override { return "FMEDIAN"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Median filter over a rectangular neighbourhood";
  }
  Status GetStatus() const override { return Status::kValidated; }
  const char* StatusNote() const override {
    return "bit-identical to the original on every captured fixture (10 of "
           "10, all four pixel types), asserted by tests/tReferenceExact.m. "
           "XRADIUS/YRADIUS are axis-swapped; see the axis-mapping comment "
           "in this file and docs/COMPATIBILITY.md.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"XRADIUS", nullptr},
        {"YRADIUS", nullptr},
        {"ZRADIUS", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFmedian<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFmedianOpcode() {
  static const FmedianOpcode op;
  return &op;
}

}  // namespace mexitk
