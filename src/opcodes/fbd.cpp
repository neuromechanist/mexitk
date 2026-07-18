// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FBD - binary dilation.
// Wraps itk::BinaryDilateImageFilter (module ITKBinaryMathematicalMorphology).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkBinaryBallStructuringElement.h"
#include "itkBinaryDilateImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunFbd(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  // The ball structuring element is dense, not sparse: SetRadius allocates a
  // (2r+1)^3-element buffer, and CreateStructuringElement builds a second,
  // separate (2r+1)^3 itk::FlatStructuringElement internally and copies it
  // in (itkBinaryBallStructuringElement.hxx). There is no upper bound on the
  // radius parameter, so a huge value means a multi-GB allocation and O(r^3)
  // work with no cap, matching the original's own unbounded parameter (the
  // same policy as FD's unbounded derivative order): the radius is a plain
  // user-supplied number, not something mexitk clamps.
  using KernelType = itk::BinaryBallStructuringElement<PixelT, kDimension>;
  KernelType kernel;
  kernel.SetRadius(CastParam<itk::SizeValueType>(p[0], "FBD", "DilationRadius"));
  kernel.CreateStructuringElement();

  using FilterType = itk::BinaryDilateImageFilter<InImage, InImage, KernelType>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);
  filter->SetKernel(kernel);
  filter->SetDilateValue(
      CastParam<PixelT>(p[1], "FBD", "ValueOverWhichDilateWillApply"));
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class FbdOpcode : public Opcode {
 public:
  const char* Name() const override { return "FBD"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Binary dilation by a ball structuring element";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"DilationRadius", nullptr},
        {"ValueOverWhichDilateWillApply", "255"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFbd<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFbdOpcode() {
  static const FbdOpcode op;
  return &op;
}

}  // namespace mexitk
