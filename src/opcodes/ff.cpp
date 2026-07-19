// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FF - flip along selected axes.
// Wraps itk::FlipImageFilter (module ITKImageGrid).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkFlipImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunFf(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::FlipImageFilter<InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);

  // The 2006 original maps X-named parameters to MATLAB dim 2 (ITK axis 1)
  // and Y-named parameters to MATLAB dim 1 (ITK axis 0); Z is unchanged.
  // Verified bit-exact against the reference: original XDIRECTION=1 ==
  // flip(vin,2), original YDIRECTION=1 == flip(vin,1) (see
  // docs/COMPATIBILITY.md, second capture campaign findings).
  typename FilterType::FlipAxesArrayType axes;
  AssignSwappedXY(axes, p[0] != 0.0, p[1] != 0.0, p[2] != 0.0);
  filter->SetFlipAxes(axes);
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class FfOpcode : public Opcode {
 public:
  const char* Name() const override { return "FF"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override { return "Flip image along selected axes"; }
  Status GetStatus() const override { return Status::kValidated; }
  const char* StatusNote() const override {
    return "bit-identical to the original on every captured fixture (12 of "
           "12, all four pixel types), asserted by tests/tReferenceExact.m. "
           "XDIRECTION/YDIRECTION are axis-swapped relative to their "
           "registry order; see the axis-mapping comment in this file and "
           "docs/COMPATIBILITY.md.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"XDIRECTION", nullptr},
        {"YDIRECTION", nullptr},
        {"ZDIRECTION", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFf<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFfOpcode() {
  static const FfOpcode op;
  return &op;
}

}  // namespace mexitk
