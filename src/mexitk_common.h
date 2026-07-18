// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// Pixel-type dispatch and the mxArray <-> itk::Image bridge.

#ifndef MEXITK_COMMON_H
#define MEXITK_COMMON_H

#include "mex.h"

#include "itkImage.h"
#include "itkImportImageFilter.h"

#include <algorithm>
#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>

namespace mexitk {

constexpr unsigned int kDimension = 3;

// Raised by parameter or semantic validation inside Opcode::Execute. mexFunction's
// outer try/catch runs around Execute() to report ITK and STL failures as
// mexitk:itkException / mexitk:exception, so a plain mexErrMsgIdAndTxt call made
// from inside Execute() would be caught there too and its specific identifier
// and message discarded in favour of that generic wrapper. OpcodeError carries
// its own id through that catch instead, so callers of mexErrMsgIdAndTxt-style
// validation from within Execute() (CastParam, per-opcode semantic checks) throw
// this rather than calling mexErrMsgIdAndTxt directly.
class OpcodeError : public std::runtime_error {
 public:
  OpcodeError(std::string id, const std::string& message)
      : std::runtime_error(message), id_(std::move(id)) {}
  const std::string& Id() const { return id_; }

 private:
  std::string id_;
};

// printf-style formatting into an owned std::string, for OpcodeError messages
// (unlike mexErrMsgIdAndTxt, its constructor cannot take the format args directly).
inline std::string FormatMessage(const char* fmt, ...) {
  char buf[512];
  va_list args;
  va_start(args, fmt);
  std::vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);
  return std::string(buf);
}

// Casts a parameter (already a validated double from ToDoubleVector) down to
// the narrower type an ITK setter expects. Integral T is where the original's
// own truncating behaviour lives (e.g. 255.9 -> 255 for uint8), and that
// in-range behaviour is preserved here; only casts that would be undefined
// behaviour in C++ (out of range, NaN, infinite) are rejected. Floating T
// mostly passes through unchanged: a double is always in range of itself,
// but casting a finite double beyond a narrower float's range (T = float) is
// itself undefined behaviour per the standard, so that one case is guarded
// too. Inf and NaN are both exactly representable in float, unlike an
// out-of-range finite value, so they deliberately pass through unrejected,
// matching what the original accepted.
template <typename T>
T CastParam(double v, const char* opcode, const char* param) {
  if constexpr (std::is_floating_point<T>::value) {
    if (std::isfinite(v) && (v < static_cast<double>(std::numeric_limits<T>::lowest()) ||
                             v > static_cast<double>(std::numeric_limits<T>::max()))) {
      throw OpcodeError("mexitk:paramRange",
                        FormatMessage("%s: parameter %s = %g is out of range for its target type.",
                                      opcode, param, v));
    }
    return static_cast<T>(v);
  } else {
    // 2^53 is the largest integer a double represents exactly; clamping the
    // upper bound to it keeps this comparison itself exact even when T is a
    // 64-bit integer whose own max() a double cannot represent precisely.
    // Only affects 64-bit T, and a value that large would fail volume
    // allocation anyway.
    constexpr double kMaxExactDouble = 9007199254740992.0;  // 2^53
    const double upper =
        std::min(static_cast<double>(std::numeric_limits<T>::max()), kMaxExactDouble);
    const double lower = static_cast<double>(std::numeric_limits<T>::lowest());
    if (!std::isfinite(v) || std::trunc(v) < lower || std::trunc(v) > upper) {
      throw OpcodeError("mexitk:paramRange",
                        FormatMessage("%s: parameter %s = %g is out of range for its target type.",
                                      opcode, param, v));
    }
    return static_cast<T>(v);
  }
}

// ---------------------------------------------------------------------------
// Pixel types
// ---------------------------------------------------------------------------

// The original MATITK dispatches on the MATLAB class of the input volume and
// instantiates ITK on that exact type. Reproducing that choice is not cosmetic:
// ITK's histogram binning differs between integral and floating pixel types, so
// FOMT genuinely returns different thresholds for uint8 than for double. An
// implementation that promoted everything to float would silently disagree with
// the reference on integral input.
template <typename T>
struct TypeTag {
  using type = T;
};

template <typename T>
struct PixelTraits;

template <>
struct PixelTraits<double> {
  static constexpr mxClassID kClassId = mxDOUBLE_CLASS;
  // Name as the original prints it in "executing ... in <name> mode".
  static constexpr const char* kName = "double";
};
template <>
struct PixelTraits<float> {
  static constexpr mxClassID kClassId = mxSINGLE_CLASS;
  static constexpr const char* kName = "float";
};
template <>
struct PixelTraits<std::uint8_t> {
  static constexpr mxClassID kClassId = mxUINT8_CLASS;
  static constexpr const char* kName = "unsigned char";
};
template <>
struct PixelTraits<std::int32_t> {
  static constexpr mxClassID kClassId = mxINT32_CLASS;
  static constexpr const char* kName = "int";
};

const char* PixelTypeName(mxClassID id);

// Invokes fn(TypeTag<T>{}) for the pixel type matching `id`.
// Returns false if `id` is not one of the four supported classes.
template <typename Fn>
bool DispatchOnPixelType(mxClassID id, Fn&& fn) {
  switch (id) {
    case mxDOUBLE_CLASS:
      fn(TypeTag<double>{});
      return true;
    case mxSINGLE_CLASS:
      fn(TypeTag<float>{});
      return true;
    case mxUINT8_CLASS:
      fn(TypeTag<std::uint8_t>{});
      return true;
    case mxINT32_CLASS:
      fn(TypeTag<std::int32_t>{});
      return true;
    default:
      return false;
  }
}

// ---------------------------------------------------------------------------
// mxArray <-> itk::Image
// ---------------------------------------------------------------------------

template <typename PixelT>
using Image3 = itk::Image<PixelT, kDimension>;

// Wraps a MATLAB volume as an itk::Image without copying.
//
// MATLAB is column-major and itk::ImportImageFilter's buffer order is likewise
// fastest-varying-first, so size=(nx,ny,nz) lines up with no transpose.
//
// Spacing is deliberately fixed at unit isotropic and the caller's arg6 is not
// applied. This matches the reference binary, where spacing provably has no
// effect: FCA/FOMT/SWS return bit-identical results for [1 1 2] and [1 1 1].
// See docs/COMPATIBILITY.md ("spacing is accepted and ignored").
//
// The const_cast is safe because imported images are only ever consumed as
// filter inputs; ITK does not write through an input buffer.
template <typename PixelT>
typename Image3<PixelT>::Pointer ImportVolume(const mxArray* arr) {
  using ImportFilterType = itk::ImportImageFilter<PixelT, kDimension>;
  typename ImportFilterType::Pointer importer = ImportFilterType::New();

  const mwSize* dims = mxGetDimensions(arr);
  typename ImportFilterType::SizeType size;
  size[0] = dims[0];
  size[1] = dims[1];
  size[2] = dims[2];

  typename ImportFilterType::IndexType start;
  start.Fill(0);

  typename ImportFilterType::RegionType region;
  region.SetIndex(start);
  region.SetSize(size);
  importer->SetRegion(region);

  typename ImportFilterType::SpacingType spacing;
  spacing.Fill(1.0);
  importer->SetSpacing(spacing);

  typename ImportFilterType::OriginType origin;
  origin.Fill(0.0);
  importer->SetOrigin(origin);

  const itk::SizeValueType numPixels =
      static_cast<itk::SizeValueType>(dims[0]) * dims[1] * dims[2];

  PixelT* data = static_cast<PixelT*>(mxGetData(const_cast<mxArray*>(arr)));
  importer->SetImportPointer(data, numPixels, /*LetFilterManageMemory=*/false);
  importer->Update();
  return importer->GetOutput();
}

// Copies an itk::Image back into a freshly allocated MATLAB array of the
// corresponding class.
template <typename PixelT>
mxArray* ExportVolume(const Image3<PixelT>* img) {
  const auto size = img->GetLargestPossibleRegion().GetSize();
  const mwSize dims[kDimension] = {static_cast<mwSize>(size[0]),
                                   static_cast<mwSize>(size[1]),
                                   static_cast<mwSize>(size[2])};
  mxArray* out =
      mxCreateNumericArray(kDimension, dims, PixelTraits<PixelT>::kClassId, mxREAL);
  const itk::SizeValueType numPixels =
      static_cast<itk::SizeValueType>(size[0]) * size[1] * size[2];
  std::memcpy(mxGetData(out), img->GetBufferPointer(), sizeof(PixelT) * numPixels);
  return out;
}

// Exports a floating-point (RealT) itk::Image into a freshly allocated
// MATLAB array of an integral PixelT, saturating out-of-range values and
// mapping non-finite ones to zero instead of casting them with undefined
// behaviour. This is the export half of every promote-and-clamp opcode
// (see FcaRealType's comment in fca.cpp): it replaces the earlier
// itk::ClampImageFilter-based cast-back, whose own Functor::Clamp falls
// through to a plain static_cast for NaN (itkClampImageFilter.h:96-106:
// `dA < m_LowerBound` and `dA > m_UpperBound` are both false for NaN, since
// every ordered comparison against NaN is false, so neither bound triggers
// and the raw cast runs) -- undefined behaviour, reachable in practice via
// an unstable diffusion timeStep or a 0/0 in FVMI's vesselness measure.
//
// The bounds comparison below mirrors ITK's own Functor::Clamp exactly
// (promote to double, compare against the target type's bounds promoted to
// double, cast the ORIGINAL RealT value on the in-range path), with only
// one addition: an explicit isnan check ahead of it. This keeps every
// in-range result bit-identical to the previous ClampImageFilter-based
// path; only the previously-undefined non-finite case changes, and it
// changes from UB to a defined, documented 0. +Inf/-Inf are not "non-finite"
// in the sense that matters here: they still compare ordered against the
// bounds (dA < lowerBound is true for -Inf, dA > upperBound is true for
// +Inf), so they saturate to lowest()/max() through the same bounds checks
// as any other out-of-range finite value, and only actual NaN takes the
// explicit zero path.
template <typename PixelT, typename RealT>
mxArray* ClampExport(const Image3<RealT>* img) {
  static_assert(std::is_integral<PixelT>::value,
               "ClampExport is for the integral cast-back path only; native "
               "float/double export uses ExportVolume directly, where NaN "
               "staying NaN is defined and faithful.");

  const auto size = img->GetLargestPossibleRegion().GetSize();
  const mwSize dims[kDimension] = {static_cast<mwSize>(size[0]),
                                   static_cast<mwSize>(size[1]),
                                   static_cast<mwSize>(size[2])};
  mxArray* out =
      mxCreateNumericArray(kDimension, dims, PixelTraits<PixelT>::kClassId, mxREAL);
  const itk::SizeValueType numPixels =
      static_cast<itk::SizeValueType>(size[0]) * size[1] * size[2];

  const RealT* src = img->GetBufferPointer();
  PixelT* dst = static_cast<PixelT*>(mxGetData(out));
  const double lowerBound = static_cast<double>(std::numeric_limits<PixelT>::lowest());
  const double upperBound = static_cast<double>(std::numeric_limits<PixelT>::max());
  for (itk::SizeValueType i = 0; i < numPixels; ++i) {
    const RealT v = src[i];
    const double dv = static_cast<double>(v);
    if (std::isnan(dv)) {
      dst[i] = PixelT{};
    } else if (dv < lowerBound) {
      dst[i] = std::numeric_limits<PixelT>::lowest();
    } else if (dv > upperBound) {
      dst[i] = std::numeric_limits<PixelT>::max();
    } else {
      dst[i] = static_cast<PixelT>(v);
    }
  }
  return out;
}

// Converts the flat, 1-based seed vector ([d1 d2 d3 d1 d2 d3 ...], already
// validated centrally in mexFunction to be a multiple of kDimension in
// length) into itk::Index<kDimension> values.
//
// Axis mapping is a direct, zero-transpose pass-through: seed triplet
// (d1,d2,d3) maps onto ITK axes (0,1,2) as index {d1-1, d2-1, d3-1}. This is
// the same convention ImportVolume uses (MATLAB column-major lines up with
// ITK's fastest-varying-first buffer order with no transpose, so a MATLAB
// subscript (r,c,p) is ITK index (r-1,c-1,p-1)). The axis order matching the
// volume's own dimension order is an interpretation: it is consistent with
// the import convention but is not verifiable against MATITK source (none
// exists). See docs/COMPATIBILITY.md.
//
// Every coordinate is validated in the double domain BEFORE any cast to an
// integral type; this helper does not trust the central check in
// mexFunction (`s < 1.0`) to have established a safe domain, because it
// hasn't: that check passes NaN and +Inf through unrejected (IEEE unordered
// comparisons are false), and a huge-but-finite coordinate would overflow
// itk::IndexValueType on a raw static_cast, which is undefined behaviour in
// C++ -- platform-dependent in a way that stayed hidden until it was
// checked on more than one architecture: ARM64's saturating convert masks
// it locally (the garbage result still fails the old bounds check), but
// x86 wraps to INT64_MIN, where the subsequent "-1" base shift is a second,
// independent signed-overflow UB. So here: truncate toward zero first
// (matching CastParam's truncation philosophy), then require the truncated
// value to be finite and within [1, size[axis]] -- only then is it cast.
// Anything else (non-finite, or truncating outside that range) throws
// OpcodeError("mexitk:seeds", ...) before any cast happens, so there is one
// identifier for every seed problem rather than splitting non-finite seeds
// off under a different one.
inline std::vector<itk::Index<kDimension>> SeedPointsToIndices(
    const std::vector<double>& seeds, const itk::Size<kDimension>& size) {
  std::vector<itk::Index<kDimension>> indices;
  indices.reserve(seeds.size() / kDimension);
  for (size_t i = 0; i + kDimension <= seeds.size(); i += kDimension) {
    itk::Index<kDimension> idx;
    for (unsigned int axis = 0; axis < kDimension; ++axis) {
      const double s = seeds[i + axis];
      const double t = std::trunc(s);
      if (!std::isfinite(s) || t < 1.0 || t > static_cast<double>(size[axis])) {
        throw OpcodeError(
            "mexitk:seeds",
            FormatMessage("Seed coordinate %g on axis %u is outside the volume "
                          "(1..%lu).",
                          s, axis + 1, static_cast<unsigned long>(size[axis])));
      }
      idx[axis] = static_cast<itk::IndexValueType>(t) - 1;
    }
    indices.push_back(idx);
  }
  return indices;
}

}  // namespace mexitk

#endif  // MEXITK_COMMON_H
