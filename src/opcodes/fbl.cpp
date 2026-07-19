// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FBL - bilateral filter.
// Wraps itk::BilateralImageFilter (module ITKImageFeature).

#include "mexitk_common.h"
#include "opcode.h"

#include "itkBilateralImageFilter.h"

namespace mexitk {
namespace {

// No promotion: the only concept check is OutputHasNumericTraitsCheck
// (itkBilateralImageFilter.h:174), satisfied by all four supported types,
// and there is no float requirement anywhere in the class documentation.
// The output is a normalised weighted average of in-range input values, so
// a native integral output cannot leave the input's own value range -- for
// IN-RANGE sigma values. Out-of-range sigma is a different, more severe
// problem: see the guards in FblOpcode::Execute below, neither of which
// ClampExport can help with, because both failures happen INSIDE ITK's own
// filter execution, before mexitk's export step ever runs.
template <typename PixelT>
void RunFbl(OpContext& ctx) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  const std::vector<double>& p = *ctx.params;

  using FilterType = itk::BilateralImageFilter<InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);
  filter->SetDomainSigma(p[0]);  // scalar double overload, fills all axes
  filter->SetRangeSigma(p[1]);
  filter->Update();

  ctx.plhs[0] = ExportVolume<PixelT>(filter->GetOutput());
}

class FblOpcode : public Opcode {
 public:
  const char* Name() const override { return "FBL"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override { return "Bilateral filter (edge-preserving smoothing)"; }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "bit-identical to the original on int32/single/uint8 (see "
           "tests/tReferenceExact.m); double has a residual at the "
           "floating-point noise floor (RMS order 1e-13 to 1e-12) across "
           "all three captured double fixtures, asserted by "
           "tests/tReferenceBounded.m. Not classified as validated overall "
           "because of that double-only residual.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"domainSigma", "5"},
        {"rangeSigma", "5"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    const std::vector<double>& p = *ctx.params;
    // domainSigma <= 0 fails through two distinct mechanisms:
    //  - domainSigma < 0: BilateralImageFilter::GenerateInputRequestedRegion
    //    computes its neighborhood radius as
    //    (SizeValueType)std::ceil(m_DomainMu * m_DomainSigma[i] / spacing[i])
    //    (itkBilateralImageFilter.hxx:79,145) -- a raw C-style cast of a
    //    negative double into an UNSIGNED integral type (m_DomainMu is a
    //    fixed positive 2.5), which is undefined behaviour: a negative
    //    floating value has no representation in an unsigned type.
    //  - domainSigma == 0: the filter's Gaussian kernel is populated via
    //    GaussianSpatialFunction::Evaluate, which at every non-center
    //    kernel position divides by "2 * m_Sigma[i] * m_Sigma[i]"
    //    (itkGaussianSpatialFunction.hxx:44-55, the division on line 52).
    //    With domainSigma == 0 that denominator is 0.0, and the numerator
    //    is a nonzero squared offset, so the kernel weight itself becomes
    //    a division producing NaN (Inf for the ratio's magnitude, but the
    //    zero-offset center position hits 0.0/0.0 == NaN directly), which
    //    then propagates through the filter's weighted-average
    //    normalization -- silently, with no exception, confirmed live
    //    (mexitk('FBL',[0 5],V) returns all-NaN on double, uniformly zero
    //    on uint8, no error). Same family as FDG's non-positive-variance
    //    guard either way.
    if (p[0] <= 0.0) {
      throw OpcodeError("mexitk:FBL:domainSigma", "domainSigma must be positive.");
    }
    // rangeSigma <= 0: m_DynamicRangeUsed = m_RangeMu * m_RangeSigma
    // (m_RangeMu is a fixed positive 4.0) becomes <= 0, which is used
    // directly as rangeDistanceThreshold; since rangeDistance is always
    // >= 0, the "rangeDistance < rangeDistanceThreshold" test that gates
    // every accumulation into val/normFactor then never succeeds for any
    // neighbour, so normFactor stays exactly 0.0 and "val /= normFactor"
    // is 0.0/0.0 = NaN, written with a raw static_cast<OutputPixelType>
    // straight into the (native, non-promoted) integer output buffer
    // INSIDE ITK's own DynamicThreadedGenerateData
    // (itkBilateralImageFilter.hxx:296-311) -- before mexitk's export step
    // ever runs, so ClampExport cannot intervene here the way it can for
    // the promoted opcodes.
    if (p[1] <= 0.0) {
      throw OpcodeError("mexitk:FBL:rangeSigma", "rangeSigma must be positive.");
    }
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFbl<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFblOpcode() {
  static const FblOpcode op;
  return &op;
}

}  // namespace mexitk
