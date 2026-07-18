// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FLS - Laplacian via recursive Gaussian.
// Wraps itk::LaplacianRecursiveGaussianImageFilter (module ITKImageFeature).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkCastImageFilter.h"
#include "itkLaplacianRecursiveGaussianImageFilter.h"

#include <type_traits>

namespace mexitk {
namespace {

// The header declares zero itkConceptMacro checks at all (grep-verified), so
// nothing hard-enforces a float pixel type, but internals hardwire
// InternalRealType = float (itkLaplacianRecursiveGaussianImageFilter.h:69)
// and the final stage is a raw itk::CastImageFilter from that internal float
// image into the output type (.hxx:155). A Laplacian is also genuinely
// signed, so a native unsigned instantiation would raw-cast negative floats
// into an unsigned type. Promoting and clamping back replaces that
// undefined-adjacent narrowing with defined saturation: on uint8 export, the
// entire negative half of the response saturates to 0, a large and
// deliberate, documented effect (see StatusNote), not an edge case.
template <typename PixelT>
using FlsRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunFls(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = FlsRealType<PixelT>;
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

  using FilterType = itk::LaplacianRecursiveGaussianImageFilter<RealImage, RealImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(real);
  filter->SetSigma(p[0]);
  filter->Update();

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(filter->GetOutput());
  } else {
    // See FcaRealType's comment in fca.cpp for the saturation rationale.
    ctx.plhs[0] = ClampExport<PixelT, RealT>(filter->GetOutput());
  }
}

class FlsOpcode : public Opcode {
 public:
  const char* Name() const override { return "FLS"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Laplacian (recursive Gaussian second derivative)";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists. "
           "uint8/int32 promote to float internally. The Laplacian is "
           "signed, so on uint8 input negative response saturates to 0 on "
           "export (int32 keeps sign).";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"sigma", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFls<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFlsOpcode() {
  static const FlsOpcode op;
  return &op;
}

}  // namespace mexitk
