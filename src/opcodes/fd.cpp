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

  // The 2006 original maps X-named parameters to MATLAB dim 2 (ITK axis 1)
  // and Y-named parameters to MATLAB dim 1 (ITK axis 0); Z is unchanged.
  // SETDIRECTION follows the same swap: original [order=1, direction=0] is
  // BIT-EXACT equal to mexitk's [order=1, direction=1], and original
  // [1,1] == mexitk's [1,0] (order 0 is exact regardless, a derivative of
  // order 0 does not depend on direction). See docs/COMPATIBILITY.md,
  // second capture campaign findings.
  unsigned int direction = CastParam<unsigned int>(p[1], "FD", "SETDIRECTION");
  if (direction == 0) {
    direction = 1;
  } else if (direction == 1) {
    direction = 0;
  }
  filter->SetDirection(direction);
  filter->Update();

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(filter->GetOutput());
  } else {
    // ClampExport saturates into [lowest, max] of the target pixel type and
    // maps non-finite values to 0, instead of itk::ClampImageFilter's plain
    // static_cast fallthrough for NaN (undefined behaviour). In-range
    // values are unaffected: this is the same bounds check and the same
    // in-range cast ITK's own Clamp functor performs. Only uint8 takes
    // this path (see FdRealType).
    ctx.plhs[0] = ClampExport<PixelT, RealT>(filter->GetOutput());
  }
}

class FdOpcode : public Opcode {
 public:
  const char* Name() const override { return "FD"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override { return "Directional derivative of a given order"; }
  Status GetStatus() const override { return Status::kValidated; }
  const char* StatusNote() const override {
    return "bit-identical to the original on every fixture where the "
           "original itself succeeded (double/single, both SETDIRECTION "
           "values captured), asserted by tests/tReferenceExact.m. The "
           "original rejects uint8/int32 input outright; mexitk accepts "
           "both (uint8 promoted to float for the derivative and cast "
           "back, since ITK's DerivativeImageFilter requires a signed "
           "output pixel type; int32 runs natively) and returns a defined "
           "result, with no agreement claim for that pixel-type pair (see "
           "tests/tReferenceRejections.m). SETDIRECTION is axis-swapped "
           "(0<->1, 2 unchanged); see the axis-mapping comment in this "
           "file and docs/COMPATIBILITY.md.";
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
