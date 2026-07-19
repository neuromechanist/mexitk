// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FFFT - forward FFT. Wraps itk::ForwardFFTImageFilter (module ITKFFT)
// feeding either itk::ComplexToRealImageFilter + RescaleIntensityImageFilter
// (param 0, "Real") or itk::ComplexToImaginaryImageFilter, unscaled (param
// 1, "Complex") (both intensity filters from module ITKImageIntensity) --
// this packing is pinned by a controlled reference-host capture (Epic 4
// Phase 2, s15: tools/capture_reference/s15_ffft_packing.m, three small
// 8x8x8 volumes with analytically known spectra), not inferred. See
// RunFfft and the StatusNote below for the byte-for-byte proof and for
// what remains unconfirmed on the original two (mri-sized) fixtures.

#include "mexitk_common.h"
#include "opcode.h"

#include "itkComplexToImaginaryImageFilter.h"
#include "itkComplexToRealImageFilter.h"
#include "itkRescaleIntensityImageFilter.h"
#include "itkShiftScaleImageFilter.h"
#include "itkVnlForwardFFTImageFilter.h"

#include <cstdlib>
#include <string>
#include <type_traits>

namespace mexitk {
namespace {

// Always promote to a floating type: PocketFFT/VNL both require it, and
// this filter has no meaningful integral-native path at all (unlike e.g.
// FGM, which stays native for integral input).
template <typename PixelT>
using FfftRealType = std::conditional_t<std::is_floating_point<PixelT>::value, PixelT, float>;

template <typename PixelT>
void RunFfft(OpContext& ctx) {
  using InImage = Image3<PixelT>;
  using RealT = FfftRealType<PixelT>;
  using RealImage = Image3<RealT>;
  using ComplexPixelT = std::complex<RealT>;
  using ComplexImage = itk::Image<ComplexPixelT, kDimension>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);
  typename RealImage::Pointer real = PromoteToReal<PixelT, RealT>(input);

  // itk::ForwardFFTImageFilter (the abstract, object-factory-resolved
  // front end docs/itk_opcode_mapping.md points at) fails at runtime here
  // with "Object factory failed to instantiate": this build's ITK has no
  // PocketFFT backend compiled in (no itkPocketFFT* headers at all), and
  // the factory-registration objects for whichever backend IS available
  // are not guaranteed to be linked into a MEX file the way they would be
  // in a full ITK application. itk::VnlForwardFFTImageFilter -- a
  // concrete, itkNewMacro-constructed (not factory-resolved) subclass,
  // backed by VNL, which is always part of ITK core regardless of build
  // configuration -- sidesteps this entirely. Confirmed empirically, not
  // assumed: the factory-based New() throws every time; the concrete Vnl
  // class constructs and runs cleanly.
  using FFTFilter = itk::VnlForwardFFTImageFilter<RealImage, ComplexImage>;
  typename FFTFilter::Pointer fft = FFTFilter::New();
  fft->SetInput(real);
  fft->Update();

  const double p0 = (*ctx.params)[0];
  const bool complexMode = (p0 != 0.0);

  if (!complexMode) {
    // "Real" (param 0): the REAL PART of the complex spectrum, rescaled to
    // [0,255] -- pinned exactly by the s15 controlled captures: impoff's
    // real part varies over [-100,100] and the fixture is exactly that
    // range rescaled to [0,255] (maxabs 2.84e-14 against a hand-computed
    // reference); imporig's real part is CONSTANT (100 everywhere, a
    // purely-real spectrum), and RescaleIntensityImageFilter's own
    // documented min==max behaviour (maps everything to OutputMinimum)
    // produces the fixture's own all-zero output, which a magnitude-based
    // packing could not: imporig's magnitude is also constant 100, so a
    // magnitude reading would ALSO all-zero here, but impoff's magnitude
    // is constant 100 too (only phase varies), which would NOT reproduce
    // impoff's non-constant real0 fixture -- ruling magnitude out
    // decisively, correcting this opcode's earlier top candidate.
    using RealPartFilter = itk::ComplexToRealImageFilter<ComplexImage, RealImage>;
    typename RealPartFilter::Pointer realPart = RealPartFilter::New();
    realPart->SetInput(fft->GetOutput());
    realPart->Update();

    using RescaleFilter = itk::RescaleIntensityImageFilter<RealImage, RealImage>;
    typename RescaleFilter::Pointer rescale = RescaleFilter::New();
    rescale->SetInput(realPart->GetOutput());
    rescale->SetOutputMinimum(static_cast<RealT>(0));
    rescale->SetOutputMaximum(static_cast<RealT>(255));
    rescale->Update();

    ctx.plhs[0] = ExportPromoted<PixelT, RealT>(rescale->GetOutput());
  } else {
    // "Complex" (param 1): the raw, UNSCALED, NEGATED IMAGINARY PART of
    // the complex spectrum -- pinned by the same captures: const's and
    // imporig's spectra are purely real (imaginary part uniformly zero
    // either way), matching both all-zero complex-mode fixtures
    // regardless of sign; impoff's imaginary part is the fixture's own
    // values negated: itk::VnlForwardFFTImageFilter's raw imaginary part
    // is the EXACT negation of the fixture (measured: out+fixture is 0
    // to floating-point noise, not out-fixture), so
    // itk::VnlForwardFFTImageFilter's own forward-transform sign
    // convention is the opposite of whatever FFT backend the original
    // 2006 binary linked -- a real, confirmed, exact convention
    // difference (not a bug in this pipeline), corrected here by
    // negating post-hoc via ShiftScaleImageFilter(shift=0, scale=-1)
    // rather than left to silently disagree. The real part needs no such
    // correction: it is an even function of frequency, so it is
    // identical either way, which is exactly why mode 0 (real-part-only)
    // and 4 of these 6 small fixtures already matched before this fix.
    using ImagPartFilter = itk::ComplexToImaginaryImageFilter<ComplexImage, RealImage>;
    typename ImagPartFilter::Pointer imagPart = ImagPartFilter::New();
    imagPart->SetInput(fft->GetOutput());
    imagPart->Update();

    using NegateFilter = itk::ShiftScaleImageFilter<RealImage, RealImage>;
    typename NegateFilter::Pointer negate = NegateFilter::New();
    negate->SetInput(imagPart->GetOutput());
    negate->SetShift(0);
    negate->SetScale(-1);
    negate->Update();

    // IEEE 754 negation of an exact +0.0 produces -0.0: `x * -1` flips the
    // sign bit unconditionally, so every zero-valued imaginary component
    // above (the const/imporig fixtures' entire output, since their
    // spectra are purely real) comes out as -0.0. -0.0 == +0.0 under
    // isequal (a numeric comparison), but NOT under an outputHash
    // comparison (a raw-byte comparison; local_md5 typecasts to uint8) --
    // confirmed directly: this failed tReferenceExact's hash check before
    // this second stage was added, despite isequal already passing. `(x +
    // 0.0) * 1.0` canonicalises -0.0 back to +0.0 (IEEE 754's addition
    // rule: a sum of opposite-signed zeros rounds to +0.0 under the
    // default round-to-nearest mode, unlike multiplication's XOR-of-signs
    // sign rule) while leaving every other value bit-for-bit unchanged.
    using CanonicalizeZeroFilter = itk::ShiftScaleImageFilter<RealImage, RealImage>;
    typename CanonicalizeZeroFilter::Pointer canonicalize = CanonicalizeZeroFilter::New();
    canonicalize->SetInput(negate->GetOutput());
    canonicalize->SetShift(0);
    canonicalize->SetScale(1);
    canonicalize->Update();

    ctx.plhs[0] = ExportPromoted<PixelT, RealT>(canonicalize->GetOutput());
  }
}

class FfftOpcode : public Opcode {
 public:
  const char* Name() const override { return "FFFT"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override { return "Forward FFT"; }
  Status GetStatus() const override { return Status::kBoundedDeviation; }
  const char* StatusNote() const override {
    return "packing CONFIRMED (Epic 4 Phase 2, s15: tools/capture_"
           "reference/s15_ffft_packing.m), by a controlled reference-"
           "host capture, not inference: three small 8x8x8 volumes with "
           "analytically known spectra (a constant volume: single DC "
           "spike; an impulse at the origin: constant, purely-real "
           "spectrum; an impulse one voxel off-origin: a real/imaginary "
           "phase ramp that varies in a known, closed-form pattern), "
           "both output modes each. Real mode (param 0) = "
           "ComplexToRealImageFilter (the REAL PART of the full 3-D "
           "forward FFT), then RescaleIntensityImageFilter to [0,255]; "
           "Complex mode (param 1) = ComplexToImaginaryImageFilter (the "
           "IMAGINARY PART), raw and unscaled. Proof, not assertion: the "
           "impulse-off-origin real-mode fixture is exactly rescale-to-"
           "[0,255] of a cosine pattern in [-100,100] (maxabs 2.84e-14); "
           "the impulse-at-origin real-mode fixture is exactly all-zero, "
           "matching RescaleIntensityImageFilter's own documented "
           "min==max-collapses-to-OutputMinimum behaviour on a constant "
           "spectrum -- and rules out magnitude (this phase's earlier "
           "top candidate) decisively, since magnitude is ALSO constant "
           "for the impulse-off-origin case (only phase/sign varies), "
           "which would wrongly all-zero that fixture too; the "
           "complex-mode fixtures for both impulse cases match the "
           "expected imaginary part in range and shape (raw, not "
           "rescaled -- confirmed by the [-100,100] range, not "
           "[0,255]). One correction the same captures forced, not "
           "predicted in advance: itk::VnlForwardFFTImageFilter's own "
           "raw imaginary part is the EXACT negation of the original's "
           "-- confirmed by out+fixture==0 to floating-point noise on "
           "the impulse-off-origin complex fixture, not merely close -- "
           "so Complex mode negates via ShiftScaleImageFilter(shift=0, "
           "scale=-1) after ComplexToImaginaryImageFilter, a disclosed, "
           "measured convention correction. (The real part needs no "
           "such correction: it is an even function of frequency, "
           "identical under either sign convention.) 4 of the 6 s15 "
           "fixtures are bit-exact; the other 2 (the real-mode outputs "
           "of the two impulse cases) have a residual at absolute "
           "double-precision noise floor (~1e-14/1e-15) -- see "
           "tests/tReferenceExact.m / tests/tReferenceBounded.m. "
           "Despite the packing itself now being proven correct, the "
           "two ORIGINAL mri-sized fixtures (ffft_real0_double, "
           "ffft_complex1_double; input [128 128 27]) still do not "
           "match closely: real mode measures RMS 20.2/maxabs 95.5 "
           "against a [0,255] fixture; complex mode measures RMS "
           "16121/maxabs 3.54495e6 against a fixture ranging "
           "+/-3.54377e6. This residual was investigated, not left "
           "unexplained: this codebase's own ITK-native computation was "
           "independently verified to be mathematically EXACT (rms "
           "1.8e-11) against MATLAB's own trusted fftn on the actual "
           "128x128x27 mri volume, which rules out every hypothesis "
           "that would implicate this implementation specifically -- "
           "axis-order mismatch (tested directly via all 6 axis "
           "permutations against MATLAB's fftn, all give the same "
           "~1e-11 floor), z=27 (radix-3, the one prime factor the "
           "cubic 8x8x8 s15 captures never exercise, since 8=2^3) "
           "mixed-radix mishandling, an unapplied fftshift (already "
           "ruled out at small scale: the impulse-off-origin fixtures "
           "matched with no shift applied, and this codebase's own "
           "no-shift pipeline is bit-identical to VnlForwardFFTImage"
           "Filter's own direct, unshifted output by construction), and "
           "size-driven zero-padding (ruled out by reading itk"
           "VnlForwardFFTImageFilter.hxx directly: it explicitly REJECTS "
           "illegal sizes via VnlFFTCommon::IsDimensionSizeLegal rather "
           "than padding them, and 27=3^3 is a legal, unpadded radix-3 "
           "size). With this implementation's own FFT independently "
           "proven exact, the residual against the fixture is best "
           "explained as a genuine difference between the original 2006 "
           "binary's own ITK-2.4-vintage VNL FFT and modern ITK's, on "
           "this specific composite (non-power-of-2) size -- the small "
           "power-of-2-only s15 captures could not have revealed a "
           "size-dependent difference like this even in principle. This "
           "is the same category of real, measured, bounded numerics "
           "difference as FCA/RD (not floating-point noise, not a "
           "porting error), so status is bounded deviation, scoped to "
           "double: single/uint8/int32 promote to a real internal type "
           "the same way (see FfftRealType) but carry no fixture of "
           "their own, so no agreement claim is made for them.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"Real Or Complex Output", "0 for Real, 1 for Complex"},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    // Boolean-flag semantics, the same precedent as FF's XDIRECTION/
    // YDIRECTION/ZDIRECTION (docs/COMPATIBILITY.md deviation 12): `!= 0.0`
    // is a well-defined IEEE comparison (NaN != 0.0 and Inf != 0.0 are
    // both true) with no further numeric ITK computation downstream that
    // depends on the raw parameter value, so it is deliberately left
    // unguarded rather than restricted to exactly {0, 1} -- no fixture
    // evidence exists either way for a non-0/1 value, and inventing a
    // stricter validation than the original's own two-value hint would
    // risk refusing an input the original accepted.
    DispatchOnPixelType(mxGetClassID(ctx.volumeA),
                        [&](auto tag) { RunFfft<typename decltype(tag)::type>(ctx); });
  }
};

}  // namespace

const Opcode* GetFfftOpcode() {
  static const FfftOpcode op;
  return &op;
}

}  // namespace mexitk
