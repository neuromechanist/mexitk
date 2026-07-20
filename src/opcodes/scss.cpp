// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// SCSS - a deliberate, documented REFUSAL, not an implementation.
//
// docs/itk_opcode_mapping.md's own SCSS entry (the highest-risk opcode in
// the whole set) maps this to itk::bio::CellularAggregate + itk::bio::CellBase
// (module BioCell, an opt-in ITK REMOTE module, EXCLUDE_FROM_DEFAULT, not
// built into mexitk): a stateful mitosis/chemotaxis simulation driven by
// static, process-wide CellBase::SetChemoAttractantLowThreshold/
// SetChemoAttractantHighThreshold calls and a loop of
// CellularAggregate::AdvanceTimeStep(), whose native output is a
// triangulated surface MESH, not an image -- unlike every other opcode in
// this codebase. The captured fixture confirms this directly:
// scss_scss_20_60_10_seedS1_double's output is a [10 1] column of ones (one
// entry per AdvanceTimeStep() iteration, numberOfIterations=10), not an
// image of any size or shape mexitk's calling convention expects.
//
// This opcode registers and appears in mexitk('?'), but Execute() always
// throws. This is not a missing implementation: shipping something that
// LOOKS like a segmentation mask under the SCSS name, when the real
// computation is a biological growth simulation with no faithful modern
// equivalent, would be exactly the kind of "subtly different result under a
// familiar name" this project exists to avoid (see docs/itk_opcode_mapping.md's
// own recommendation to treat SCSS as a product decision, and
// docs/COMPATIBILITY.md's SCSS deviation row for the full rationale).

#include "mexitk_common.h"
#include "opcode.h"

namespace mexitk {
namespace {

class ScssOpcode : public Opcode {
 public:
  const char* Name() const override { return "SCSS"; }
  Category GetCategory() const override { return Category::kSegmentation; }
  const char* Description() const override {
    return "Cellular Segmentation - refused, not implemented (see StatusNote)";
  }
  Status GetStatus() const override { return Status::kUnsupported; }
  const char* StatusNote() const override {
    return "deliberately unsupported, not a missing implementation: maps to "
           "itk::bio::CellularAggregate + itk::bio::CellBase (module "
           "BioCell, an opt-in ITK remote module not built into mexitk), a "
           "stateful mitosis/chemotaxis simulation driven by static, "
           "process-wide CellBase setters and a loop of "
           "AdvanceTimeStep(), whose output is a triangulated surface MESH, "
           "not an image -- unlike every other opcode here. The captured "
           "fixture (scss_scss_20_60_10_seedS1_double) confirms this "
           "directly: the original's own output is a [10 1] column of "
           "ones, one entry per AdvanceTimeStep() iteration "
           "(numberOfIterations=10), not an image mexitk's calling "
           "convention could return under this name without misleading a "
           "caller. Calling SCSS always throws mexitk:SCSS:unsupported. "
           "The fixture is recorded as a deliberate refuse-to-reproduce "
           "case in tests/tReferenceRejections.m and "
           "docs/COMPATIBILITY.md's deviation table -- the original "
           "'succeeded' on this input in the sense of returning without "
           "error, but what it returned is not a value mexitk can "
           "faithfully stand behind under the SCSS name. See "
           "docs/itk_opcode_mapping.md's own SCSS entry for the full "
           "risk writeup (opt-in remote module, global static state, "
           "output-type mismatch, and no drop-in modern equivalent for the "
           "underlying biological simulation) and its own recommendation "
           "to treat this as a product decision rather than a routine "
           "class-mapping exercise.";
  }

  const std::vector<ParamSpec>& Params() const override {
    static const std::vector<ParamSpec> kParams = {
        {"SetChemoAttractantLowThreshold", nullptr},
        {"SetChemoAttractantHighThreshold", nullptr},
        {"numberOfIterations", nullptr},
    };
    return kParams;
  }

  void Execute(OpContext& ctx) const override {
    (void)ctx;
    throw OpcodeError(
        "mexitk:SCSS:unsupported",
        "SCSS is deliberately unsupported: it maps to itk::bio::CellularAggregate, a "
        "stateful biological growth simulation in ITK's opt-in BioCell remote module "
        "(not built into mexitk) whose native output is a triangulated surface mesh, "
        "not an image. mexitk refuses to fabricate an image-shaped substitute under "
        "this name; see docs/COMPATIBILITY.md and docs/itk_opcode_mapping.md for the "
        "full rationale.");
  }
};

}  // namespace

const Opcode* GetScssOpcode() {
  static const ScssOpcode op;
  return &op;
}

}  // namespace mexitk
