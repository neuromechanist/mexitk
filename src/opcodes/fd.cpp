// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FD - directional derivative.
// Wraps itk::DerivativeImageFilter (module ITKImageFeature).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkCastImageFilter.h"
#include "itkDerivativeImageFilter.h"

#include <type_traits>

namespace mexitk {
namespace {

// itk::DerivativeImageFilter requires a signed output pixel type
// (itkConceptMacro(SignedOutputPixelType, Concept::Signed<OutputPixelType>),
// itkDerivativeImageFilter.h:85). uint8 is unsigned and fails that check;
// int32/float/double are signed and instantiate natively. So the promotion
// predicate is signedness, not floating-pointness, unlike FCA.
template <typename PixelT>
using FdRealType = std::conditional_t<std::is_signed<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunFd(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = FdRealType<PixelT>;
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

  using FilterType = itk::DerivativeImageFilter<RealImage, RealImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(real);
  filter->SetOrder(CastParam<unsigned int>(p[0], "FD", "SETORDER"));
  filter->SetDirection(CastParam<unsigned int>(p[1], "FD", "SETDIRECTION"));
  filter->Update();

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(filter->GetOutput());
  } else {
    using CastOut = itk::CastImageFilter<RealImage, InImage>;
    typename CastOut::Pointer back = CastOut::New();
    back->SetInput(filter->GetOutput());
    back->Update();
    ctx.plhs[0] = ExportVolume<PixelT>(back->GetOutput());
  }
}

class FdOpcode : public Opcode {
 public:
  const char* Name() const override { return "FD"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override { return "Directional derivative of a given order"; }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "uint8 input is promoted to float for the derivative and cast back, "
           "because ITK's DerivativeImageFilter requires a signed output pixel "
           "type; int32/float/double run natively. No reference capture exists.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"SETORDER", nullptr},
        {"SETDIRECTION", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFd<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFdOpcode() {
  static const FdOpcode op;
  return &op;
}

}  // namespace mexitk
