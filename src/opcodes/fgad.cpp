// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FGAD - gradient anisotropic diffusion.
// Wraps itk::GradientAnisotropicDiffusionImageFilter (module ITKAnisotropicSmoothing).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkCastImageFilter.h"
#include "itkGradientAnisotropicDiffusionImageFilter.h"

#include <type_traits>

namespace mexitk {
namespace {

// Same base class as FCA (AnisotropicDiffusionImageFilter): the concept
// check is only UpdateBufferHasNumericTraitsCheck
// (itkGradientAnisotropicDiffusionImageFilter.h:77), but the shared base's
// own documentation states "these filters expect images of real-valued
// types. This means pixel types of floats, doubles, or a user-defined type
// with floating point accuracy" (itkAnisotropicDiffusionImageFilter.h:37-40)
// -- documented, not concept-enforced. FCA's promotion precedent applies
// verbatim; see FcaRealType's comment in fca.cpp.
template <typename PixelT>
using FgadRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunFgad(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = FgadRealType<PixelT>;
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

  using FilterType = itk::GradientAnisotropicDiffusionImageFilter<RealImage, RealImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(real);
  // SetNumberOfIterations is IdentifierType on the FiniteDifferenceImageFilter
  // base (itkFiniteDifferenceImageFilter.h:186), same as FCA/FCF/FAAB.
  filter->SetNumberOfIterations(
      CastParam<itk::IdentifierType>(p[0], "FGAD", "numberOfIterations"));
  // Time-step stability: same CFL bound and warn-but-proceed behaviour as
  // FCA via the shared AnisotropicDiffusionImageFilter base; see the
  // timeStep comment in fca.cpp. A negative timeStep runs the diffusion
  // backward in time (ill-posed); rejected for the same reason as FCA's
  // guard. timeStep == 0 stays accepted as a defined no-op.
  if (p[1] < 0.0) {
    throw OpcodeError("mexitk:FGAD:timeStep", "timeStep must not be negative.");
  }
  filter->SetTimeStep(p[1]);
  filter->SetConductanceParameter(p[2]);
  filter->Update();

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(filter->GetOutput());
  } else {
    // See FcaRealType's comment in fca.cpp for the saturation rationale.
    ctx.plhs[0] = ClampExport<PixelT, RealT>(filter->GetOutput());
  }
}

class FgadOpcode : public Opcode {
 public:
  const char* Name() const override { return "FGAD"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Gradient anisotropic diffusion (edge-preserving smoothing)";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "does not reproduce the original bit-for-bit: "
           "GradientAnisotropicDiffusionImageFilter's numerics moved "
           "between ITK 2.4 and 5.x, the same class of upstream evolution "
           "as FCA (its curvature-conductance sibling; the two differ on "
           "identical parameters by design). Measured RMS on double/single "
           "ranges from about 5e-5 to 0.35 depending on iteration count/"
           "conductance; uint8/int32 promote to float internally and have "
           "a larger measured residual (RMS up to about 11.7 on uint8). "
           "See tests/tReferenceBounded.m for the exact measured numbers "
           "per fixture.";
  }

  const std::vector<ParamSpec>& Params() const override {
    // Registry shows NO hints for FGAD (unlike FCA's 0.0625/3.0).
    static const std::vector<ParamSpec> kParams = {
        {"numberOfIterations", nullptr},
        {"timeStep", nullptr},
        {"conductance", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFgad<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFgadOpcode() {
  static const FgadOpcode op;
  return &op;
}

}  // namespace mexitk
