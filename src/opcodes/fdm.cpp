// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// FDM / FDMV - Danielsson distance map.
// Wraps itk::DanielssonDistanceMapImageFilter (module ITKDistanceMap).
//
// FDM and FDMV are the same filter read via two different accessors:
// GetDistanceMap() (== GetOutput(), output 0) for FDM, GetVoronoiMap()
// (output 1) for FDMV. See FdmvOpcode::StatusNote for the FDMV accessor
// caveat.

#include "mexitk_common.h"
#include "opcode.h"

#include "itkDanielssonDistanceMapImageFilter.h"

namespace mexitk {
namespace {

const std::vector<ParamSpec>& DanielssonParams() {
  static const std::vector<ParamSpec> kNoParams = {};
  return kNoParams;
}

// Voronoi image type defaults to InImage: the distance map is instantiated at
// the input pixel type so it truncates exactly as the original's same-pixel-type
// codegen did. All optional flags (SquaredDistance/InputIsBinary/UseImageSpacing)
// are left at their ITK defaults.
template <typename PixelT>
void RunDanielsson(OpContext& ctx, bool wantVoronoi) {
  using InImage = Image3<PixelT>;

  typename InImage::Pointer input = ImportVolume<PixelT>(ctx.volumeA);

  using FilterType = itk::DanielssonDistanceMapImageFilter<InImage, InImage, InImage>;
  typename FilterType::Pointer filter = FilterType::New();
  filter->SetInput(input);
  filter->Update();

  ctx.plhs[0] = wantVoronoi ? ExportVolume<PixelT>(filter->GetVoronoiMap())
                            : ExportVolume<PixelT>(filter->GetDistanceMap());
}

class FdmOpcode : public Opcode {
 public:
  const char* Name() const override { return "FDM"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Danielsson distance map (distance output)";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists";
  }

  const std::vector<ParamSpec>& Params() const override { return DanielssonParams(); }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA), [&](auto tag) {
      RunDanielsson<typename decltype(tag)::type>(ctx, /*wantVoronoi=*/false);
    });
  }
};

class FdmvOpcode : public Opcode {
 public:
  const char* Name() const override { return "FDMV"; }
  Category GetCategory() const override { return Category::kFilter; }
  const char* Description() const override {
    return "Danielsson distance map (Voronoi output)";
  }
  Status GetStatus() const override { return Status::kSmokeTested; }
  const char* StatusNote() const override {
    return "runs and returns plausible output; no reference capture exists. The "
           "\"V = Voronoi (not Vector) map\" accessor identification rests on "
           "secondary sourcing (a Vincent Chu opcode table) and is unconfirmed "
           "against MATITK source; itk::DanielssonDistanceMapImageFilter also "
           "exposes a distinct third accessor, GetVectorDistanceMap(), on the "
           "same class. See docs/itk_opcode_mapping.md (FDMV, Drift/risk).";
  }

  const std::vector<ParamSpec>& Params() const override { return DanielssonParams(); }

  void Execute(OpContext& ctx) const override {
    DispatchOnPixelType(mxGetClassID(ctx.volumeA), [&](auto tag) {
      RunDanielsson<typename decltype(tag)::type>(ctx, /*wantVoronoi=*/true);
    });
  }
};

}  // namespace

const Opcode* GetFdmOpcode() {
  static const FdmOpcode op;
  return &op;
}

const Opcode* GetFdmvOpcode() {
  static const FdmvOpcode op;
  return &op;
}

}  // namespace mexitk
