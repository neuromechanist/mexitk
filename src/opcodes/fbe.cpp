// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FBE - binary erosion.
// Wraps itk::BinaryErodeImageFilter (module ITKBinaryMathematicalMorphology).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkBinaryBallStructuringElement.h"
#include "itkBinaryErodeImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunFbe(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  using KernelType = itk::BinaryBallStructuringElement<PixelT, kDimension>;
  KernelType kernel;
  kernel.SetRadius(CastParam<itk::SizeValueType>(p[0], "FBE", "ErosionRadius"));
  kernel.CreateStructuringElement();

  using FilterType = itk::BinaryErodeImageFilter<InImage, InImage, KernelType>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);
  filter->SetKernel(kernel);
  filter->SetErodeValue(
      CastParam<PixelT>(p[1], "FBE", "ValueOverWhichErodeWillApply"));
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class FbeOpcode : public Opcode {
 public:
  const char* Name() const override { return "FBE"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Binary erosion by a ball structuring element";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"ErosionRadius", nullptr},
        {"ValueOverWhichErodeWillApply", "255"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFbe<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFbeOpcode() {
  static const FbeOpcode op;
  return &op;
}

}  // namespace mexitk
