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
#include "itkCurvatureFlowImageFilter.h"

#include <cmath>
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
  // timeStep comment in fca.cpp for the same arithmetic. A negative
  // timeStep runs the flow backward in time (ill-posed); rejected for the
  // same reason as FCA's guard. timeStep == 0 stays accepted as a defined
  // no-op. Non-finite (NaN/Inf) is rejected too, not just negative:
  // measured directly, a NaN or +Inf timeStep propagates through
  // CurvatureFlowFunction's update with no exception, silently returning
  // an all-NaN output on every voxel -- a `< 0.0` comparison alone would
  // not catch this, since NaN compares false against every ordered
  // relational operator.
  if (!std::isfinite(p[1]) || p[1] < 0.0) {
    throw OpcodeError("mexitk:FCF:timeStep",
                      "timeStep must be finite and not negative.");
  }
  filter->SetTimeStep(p[1]);
  filter->Update();

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(filter->GetOutput());
  } else {
    // See FcaRealType's comment in fca.cpp for the saturation rationale.
    ctx.plhs[0] = ClampExport<PixelT, RealT>(filter->GetOutput());
  }
}

class FcfOpcode : public Opcode {
 public:
  const char* Name() const override { return "FCF"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Curvature flow (edge-preserving smoothing)";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "does not reproduce the original bit-for-bit: "
           "CurvatureFlowImageFilter's numerics moved between ITK 2.4 and "
           "5.x, the same class of upstream evolution as FCA. Measured "
           "residual on double is at the floating-point noise floor (RMS "
           "order 1e-15); single is small (order 1e-7); uint8/int32 "
           "promote to float internally and have a much larger measured "
           "residual (RMS up to about 7.3 on uint8). See "
           "tests/tReferenceBounded.m for the exact measured numbers per "
           "fixture.";
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
