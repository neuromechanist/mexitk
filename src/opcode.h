// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// The opcode registry.
//
// The original MATITK was generated from ITK's example files by a Perl script.
// mexitk uses a hand-written registry instead: each opcode is a small
// translation unit describing its parameters and running its ITK pipeline, and
// the table below is the single source of truth for dispatch, for the `?`
// listing, for parameter validation, and for the published validation status.
// Adding an opcode is one file plus one line in RegisterBuiltinOpcodes().

#ifndef MEXITK_OPCODE_H
#define MEXITK_OPCODE_H

#include "mex.h"

#include <string>
#include <vector>

namespace mexitk {

enum class Category { kFilter, kSegmentation, kRegistration };

// How far an opcode has been checked against the original binary. This is
// published verbatim by mexitk('?') and by the README table, which is generated
// from this registry so the documentation cannot drift from the code.
enum class Status {
  // Reproduces captured output from the original matitk binary bit-for-bit,
  // asserted by a test against a stored reference fixture.
  kValidated,
  // Compared against a reference fixture and does NOT match bit-for-bit. The
  // difference is a measured, bounded consequence of ITK's own evolution
  // between 2.4 (the original's build) and 5.x, not a porting error. The bound
  // is asserted by a test and stated in docs/COMPATIBILITY.md. This is a
  // distinct claim from kValidated and must never be conflated with it.
  kBoundedDeviation,
  // Runs and returns plausible output, but no reference capture exists.
  kSmokeTested,
  // Implemented from the ITK mapping only; never executed against a reference.
  kUntested,
};

struct ParamSpec {
  const char* name;
  // The original's own "(which usually has value equal to ...)" hint, kept
  // verbatim so mexitk's help text matches matitk's. nullptr when it had none.
  const char* hint;
};

struct OpContext {
  const std::vector<double>* params;
  const mxArray* volumeA;
  const mxArray* volumeB;  // nullptr when not supplied or empty
  const std::vector<double>* seeds;
  int nargout;
  mxArray** plhs;
};

class Opcode {
 public:
  virtual ~Opcode() = default;

  virtual const char* Name() const = 0;
  virtual Category GetCategory() const = 0;
  virtual const char* Description() const = 0;
  virtual Status GetStatus() const = 0;
  // Free-text caveat shown in the docs, e.g. which pixel types are unverified.
  virtual const char* StatusNote() const { return nullptr; }

  virtual const std::vector<ParamSpec>& Params() const = 0;

  // Number of output volumes this call must produce. Defaults to one; FOMT
  // overrides it because its output count is a function of a parameter.
  virtual int OutputCount(const std::vector<double>& params) const {
    (void)params;
    return 1;
  }

  virtual void Execute(OpContext& ctx) const = 0;
};

void RegisterOpcode(const Opcode* op);
void RegisterBuiltinOpcodes();

// Case-insensitive, matching the original (it accepts 'fomt' and 'FOMT').
const Opcode* FindOpcode(const std::string& name);
const std::vector<const Opcode*>& AllOpcodes();

const char* StatusName(Status s);
const char* CategoryName(Category c);

}  // namespace mexitk

#endif  // MEXITK_OPCODE_H
