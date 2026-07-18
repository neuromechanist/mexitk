// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FCA - curvature anisotropic diffusion.
// Wraps itk::CurvatureAnisotropicDiffusionImageFilter (module ITKAnisotropicSmoothing).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkCastImageFilter.h"
#include "itkCurvatureAnisotropicDiffusionImageFilter.h"

#include <type_traits>

namespace mexitk {
namespace {

// ITK's dense finite-difference solvers require a floating-point pixel type, so
// integral input is promoted to float for the diffusion and cast back on the
// way out. The original supported "unsigned char mode" for FCA and must have
// promoted similarly, but no reference capture exists for integral input, so
// the choice of float (rather than double) as the promotion target is
// unverified. See StatusNote.
template <typename PixelT>
using FcaRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunFca(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = FcaRealType<PixelT>;
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

  using FilterType = itk::CurvatureAnisotropicDiffusionImageFilter<RealImage, RealImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(real);
  // SetNumberOfIterations is declared IdentifierType on the
  // FiniteDifferenceImageFilter base (itkFiniteDifferenceImageFilter.h:186),
  // not unsigned int; matches FCF/FAAB, which take the same base's setter.
  filter->SetNumberOfIterations(
      CastParam<itk::IdentifierType>(p[0], "FCA", "numberOfIterations"));
  // ITK warns (itkWarningMacro) but proceeds when timeStep exceeds the
  // stability bound minSpacing/2^(dim+1), which is 0.0625 in 3-D at unit
  // spacing. The reference binary proceeds silently at that value; it is
  // exactly ITK's own 3-D default, sitting on the boundary rather than past it.
  // A NEGATIVE timeStep is a different problem: it runs the diffusion
  // backward in time, which is ill-posed (the original's behaviour on a
  // negative timeStep is unknown and unreproducible), so it is rejected
  // rather than reproduced; timeStep == 0 stays accepted as a defined no-op.
  if (p[1] < 0.0) {
    throw OpcodeError("mexitk:FCA:timeStep", "timeStep must not be negative.");
  }
  filter->SetTimeStep(p[1]);
  filter->SetConductanceParameter(p[2]);
  filter->Update();

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(filter->GetOutput());
  } else {
    // ClampExport saturates into [lowest, max] of the target pixel type and
    // maps non-finite values to 0, instead of itk::ClampImageFilter's plain
    // static_cast fallthrough for NaN (undefined behaviour; reachable via
    // an unstable timeStep). In-range values are unaffected: this is the
    // same bounds check and the same in-range cast ITK's own Clamp functor
    // performs. Only uint8/int32 take this path (see FcaRealType).
    ctx.plhs[0] = ClampExport<PixelT, RealT>(filter->GetOutput());
  }
}

class FcaOpcode : public Opcode {
 public:
  const char* Name() const override { return "FCA"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Curvature anisotropic diffusion (edge-preserving smoothing)";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "does NOT match the original bit-for-bit: ITK's diffusion numerics "
           "changed between 2.4 and 5.x. On the reference volume, 1 iteration "
           "gives RMS 2.6e-3 / max 4.7e-2 over a 0-88 intensity range; error "
           "compounds with iteration count (5 iterations: RMS 5.7e-3, max 1.6). "
           "uint8/int32 promote to float internally and have no reference";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"numberOfIterations", nullptr},
        {"timeStep", "0.0625"},
        {"conductance", "3.0"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFca<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFcaOpcode() {
  static const FcaOpcode op;
  return &op;
}

}  // namespace mexitk
