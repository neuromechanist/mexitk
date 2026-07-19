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

#include <cmath>
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
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "bit-identical to the original on int32 at sigma=2 (see "
           "tests/tReferenceExact.m); double/single have a residual at the "
           "floating-point noise floor (RMS order 1e-8 to 1e-7) across "
           "sigma 1/2/4; uint8's own residual is much larger (RMS about "
           "98.7) because its clamp-back export saturates the signed "
           "Laplacian field's negative half to 0, amplifying the "
           "underlying tiny numeric difference into a binary sign flip at "
           "many voxels near the zero crossing. All measured numbers are "
           "in tests/tReferenceBounded.m. uint8/int32 promote to float "
           "internally; the Laplacian is signed, so on uint8 input "
           "negative response saturates to 0 on export (int32 keeps sign).";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"sigma", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    // sigma <= 0 is already caught by RecursiveGaussianImageFilter's own
    // itkExceptionMacro ("Sigma must be greater than zero.",
    // itkRecursiveGaussianImageFilter.hxx:330-333, surfaced here as
    // mexitk:itkException) -- that constraint is unchanged. But that
    // exception's own guard is `m_Sigma <= 0.0`, which does not catch NaN
    // (confirmed empirically: a NaN sigma instead silently returned an
    // all-NaN output, no exception), so only the non-finite gap is closed
    // here, param-guard hardening pass.
    if (!std::isfinite((*ctx.params)[0])) {
      throw OpcodeError("mexitk:FLS:sigma", "sigma must be finite.");
    }
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
