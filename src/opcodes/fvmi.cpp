// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FVMI - vesselness measure (Hessian eigenvalues, Sato).
// Wraps itk::HessianRecursiveGaussianImageFilter feeding
// itk::Hessian3DToVesselnessMeasureImageFilter (module ITKImageFeature).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkCastImageFilter.h"
#include "itkHessian3DToVesselnessMeasureImageFilter.h"
#include "itkHessianRecursiveGaussianImageFilter.h"

#include <type_traits>

namespace mexitk {
namespace {

// Hessian3DToVesselnessMeasureImageFilter<TPixel> hardcodes its input type as
// ImageToImageFilter<Image<SymmetricSecondRankTensor<double,3>,3>,
// Image<TPixel,3>> (itkHessian3DToVesselnessMeasureImageFilter.h:76-78,85).
// HessianRecursiveGaussianImageFilter's second template argument defaults to
// Image<SymmetricSecondRankTensor<NumericTraits<PixelType>::RealType,Dim>,Dim>
// (itkHessianRecursiveGaussianImageFilter.h:42-46), and
// NumericTraits<float>::RealType and NumericTraits<double>::RealType are both
// double (itkNumericTraits.h:1355-1356 float specialization). So for
// RealT = float OR double, the DEFAULT second template argument already IS
// the double-tensor image the vesselness stage requires: no explicit
// tensor-image instantiation is needed. Promotion itself follows the same
// float-for-integral-input policy as the rest of this file set; the Hessian
// stage additionally computes its own recursive passes in
// InternalRealType = float regardless of RealT (:74), which is ITK's own
// internal design, not something mexitk chooses.
template <typename PixelT>
using FvmiRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunFvmi(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = FvmiRealType<PixelT>;
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

  using HessianFilterType = itk::HessianRecursiveGaussianImageFilter<RealImage>;
  typename HessianFilterType::Pointer hessian = HessianFilterType::New();
  hessian->SetInput(real);
  hessian->SetSigma(p[0]);

  using VesselnessFilterType = itk::Hessian3DToVesselnessMeasureImageFilter<RealT>;
  typename VesselnessFilterType::Pointer vesselness = VesselnessFilterType::New();
  vesselness->SetInput(hessian->GetOutput());
  vesselness->SetAlpha1(p[1]);
  vesselness->SetAlpha2(p[2]);
  vesselness->Update();

  if constexpr (std::is_same<PixelT, RealT>::value) {
    ctx.plhs[0] = ExportVolume<RealT>(vesselness->GetOutput());
  } else {
    // See FcaRealType's comment in fca.cpp for the saturation rationale.
    ctx.plhs[0] = ClampExport<PixelT, RealT>(vesselness->GetOutput());
  }
}

class FvmiOpcode : public Opcode {
 public:
  const char* Name() const override { return "FVMI"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Vesselness measure (Hessian eigenvalues, Sato)";
  }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "does not reproduce the original bit-for-bit: both stages' "
           "internal numerics (HessianRecursiveGaussianImageFilter, "
           "Hessian3DToVesselnessMeasureImageFilter) moved between ITK 2.4 "
           "and 5.x. Measured RMS ranges from about 0.08 to 0.51 across "
           "the captured double/single/int32/uint8 fixtures, with max "
           "absolute differences around 1-10 -- large relative to the "
           "vesselness measure's own typical range, so this is a real "
           "algorithmic drift, not noise. See tests/tReferenceBounded.m "
           "for the exact measured numbers per fixture. "
           "The three registry parameters land on two different ITK filters "
           "(SetSigma on HessianRecursiveGaussianImageFilter; SetAlpha1/"
           "SetAlpha2 on Hessian3DToVesselnessMeasureImageFilter); the "
           "Hessian stage computes internally in float regardless of pixel "
           "type (ITK hardwires InternalRealType = float); non-vessel "
           "voxels are exactly 0.";
  }

  const std::vector<ParamSpec>& Params() const override {
    // Registry-verbatim parameter names (the original's own dump literally
    // uses the setter names, not descriptive parameter names).
    static const std::vector<ParamSpec> kParams = {
        {"SetSigma", nullptr},
        {"SetAlpha1", nullptr},
        {"SetAlpha2", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFvmi<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFvmiOpcode() {
  static const FvmiOpcode op;
  return &op;
}

}  // namespace mexitk
