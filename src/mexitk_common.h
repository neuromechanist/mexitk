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

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace mexitk {

constexpr unsigned int kDimension = 3;

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

}  // namespace mexitk

#endif  // MEXITK_COMMON_H
