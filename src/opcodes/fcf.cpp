// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FCF - curvature flow.
// Wraps itk::CurvatureFlowImageFilter (module ITKCurvatureFlow).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkCastImageFilter.h"
#include "itkClampImageFilter.h"
#include "itkCurvatureFlowImageFilter.h"

#include <type_traits>

namespace mexitk {
namespace {

// "This filter also requires that the output image pixels are of a floating
// point type" (itkCurvatureFlowImageFilter.h:68-70) and "TOutputImage's
// pixel type must be a real number type" (:86-87) -- documented, not
// concept-enforced: its concept checks (:145-151) are arithmetic/
// convertibility checks an integral pixel type would also satisfy. Promoted
// per the FCA-family precedent; see FcaRealType's comment in fca.cpp.
template <typename PixelT>
using FcfRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunFcf(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = FcfRealType<PixelT>;
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

  using FilterType = itk::CurvatureFlowImageFilter<RealImage, RealImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(real);
  // SetNumberOfIterations is declared IdentifierType on the
  // FiniteDifferenceImageFilter base (itkFiniteDifferenceImageFilter.h:186),
  // not unsigned int; verified against the header.
  filter->SetNumberOfIterations(
      CastParam<itk::IdentifierType>(p[0], "FCF", "numberOfIterations"));
  // 0.0625 is again exactly ITK's 3-D-stable CFL boundary value; see the
  // timeStep comment in fca.cpp for the same arithmetic.
  filter->SetTimeStep(p[1]);
  filter->Update();

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(filter->GetOutput());
  } else {
    // See FcaRealType's comment in fca.cpp for the saturation rationale.
    using ClampOut = itk::ClampImageFilter<RealImage, InImage>;
    typename ClampOut::Pointer back = ClampOut::New();
    back->SetInput(filter->GetOutput());
    back->Update();
    ctx.plhs[0] = ExportVolume<PixelT>(back->GetOutput());
  }
}

class FcfOpcode : public Opcode {
 public:
  const char* Name() const override { return "FCF"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Curvature flow (edge-preserving smoothing)";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists. "
           "uint8/int32 promote to float internally and have no reference.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"numberOfIterations", "10"},
        {"timeStep", "0.0625"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFcf<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFcfOpcode() {
  static const FcfOpcode op;
  return &op;
}

}  // namespace mexitk
