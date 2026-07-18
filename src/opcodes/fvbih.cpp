// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FVBIH - iterative binary voting hole filling.
// Wraps itk::VotingBinaryIterativeHoleFillingImageFilter (module ITKLabelVoting).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkVotingBinaryIterativeHoleFillingImageFilter.h"

namespace mexitk {
namespace {

template <typename PixelT>
void RunFvbih(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::VotingBinaryIterativeHoleFillingImageFilter<InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);

  typename FilterType::InputSizeType radius;
  radius[0] = CastParam<itk::SizeValueType>(p[0], "FVBIH", "radiusX");
  radius[1] = CastParam<itk::SizeValueType>(p[1], "FVBIH", "radiusY");
  radius[2] = CastParam<itk::SizeValueType>(p[2], "FVBIH", "radiusZ");
  filter->SetRadius(radius);
  filter->SetBackgroundValue(
      CastParam<PixelT>(p[3], "FVBIH", "binaryImageBackgroundColor"));
  filter->SetForegroundValue(
      CastParam<PixelT>(p[4], "FVBIH", "binaryImageForegroundColor"));
  // MajorityThreshold is an OFFSET above 50% of the neighborhood, not an
  // absolute vote count. Internally (itkVotingBinaryHoleFillingImageFilter.hxx):
  // let N = full neighborhood size including the center pixel, i.e.
  // prod(2*radius[i]+1); birthThreshold = floor((N-1)/2) + MajorityThreshold,
  // and an OFF pixel flips ON only once its ON-neighbor count reaches
  // birthThreshold. So for radius [1 1 1] (N=27), MajorityThreshold=1 needs
  // floor(26/2)+1 = 14 ON neighbors out of 26. A large MajorityThreshold
  // silently makes the filter a no-op (birthThreshold exceeds any achievable
  // neighbor count) rather than erroring; this is legitimate ITK/original
  // semantics and is reproduced on purpose, not a bug. See the same formula
  // recorded in docs/itk_opcode_mapping.md (FVBIH).
  filter->SetMajorityThreshold(
      CastParam<unsigned int>(p[5], "FVBIH", "SetMajorityThreshold"));
  filter->SetMaximumNumberOfIterations(
      CastParam<unsigned int>(p[6], "FVBIH", "numberOfIterations"));
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class FvbihOpcode : public Opcode {
 public:
  const char* Name() const override { return "FVBIH"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Iterative binary voting hole filling";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"radiusX", nullptr},
        {"radiusY", nullptr},
        {"radiusZ", nullptr},
        {"binaryImageBackgroundColor", nullptr},
        {"binaryImageForegroundColor", nullptr},
        {"SetMajorityThreshold", nullptr},
        {"numberOfIterations", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA), [&](auto tag) {
      RunFvbih<typename decltype(tag)::type>(ctx);
    });
  }
};

}  // namespace

const Opcode* GetFvbihOpcode() {
  static const FvbihOpcode op;
  return &op;
}

}  // namespace mexitk
