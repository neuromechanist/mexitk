// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.

#include "opcode.h"

#include "mexitk_common.h"

#include <algorithm>
#include <cctype>

namespace mexitk {

namespace {

std::vector<const Opcode*>& MutableRegistry() {
  static std::vector<const Opcode*> registry;
  return registry;
}

std::string ToUpper(const std::string& s) {
  std::string out = s;
  std::transform(out.begin(), out.end(), out.begin(),
                 [](unsigned char c) { return static_cast<char>(std::toupper(c)); });
  return out;
}

}  // namespace

void RegisterOpcode(const Opcode* op) { MutableRegistry().push_back(op); }

const Opcode* FindOpcode(const std::string& name) {
  const std::string key = ToUpper(name);
  for (const Opcode* op : MutableRegistry()) {
    if (ToUpper(op->Name()) == key) {
      return op;
    }
  }
  return nullptr;
}

const std::vector<const Opcode*>& AllOpcodes() { return MutableRegistry(); }

const char* StatusName(Status s) {
  switch (s) {
    case Status::kValidated:
      return "validated";
    case Status::kBoundedDeviation:
      return "bounded-deviation";
    case Status::kSmokeTested:
      return "smoke-tested";
    case Status::kUntested:
      return "untested";
  }
  return "unknown";
}

const char* CategoryName(Category c) {
  switch (c) {
    case Category::kFilter:
      return "filtering";
    case Category::kSegmentation:
      return "segmentation";
    case Category::kRegistration:
      return "registration";
  }
  return "unknown";
}

const char* PixelTypeName(mxClassID id) {
  switch (id) {
    case mxDOUBLE_CLASS:
      return PixelTraits<double>::kName;
    case mxSINGLE_CLASS:
      return PixelTraits<float>::kName;
    case mxUINT8_CLASS:
      return PixelTraits<std::uint8_t>::kName;
    case mxINT32_CLASS:
      return PixelTraits<std::int32_t>::kName;
    default:
      return "unsupported";
  }
}

// Declared by each opcode's translation unit.
const Opcode* GetFbbOpcode();
const Opcode* GetFbtOpcode();
const Opcode* GetFcaOpcode();
const Opcode* GetFdOpcode();
const Opcode* GetFdgOpcode();
const Opcode* GetFfOpcode();
const Opcode* GetFgaOpcode();
const Opcode* GetFmeanOpcode();
const Opcode* GetFmedianOpcode();
const Opcode* GetFomtOpcode();
const Opcode* GetFsnOpcode();
const Opcode* GetSwsOpcode();

// Registration is explicit rather than via static initialisers in each opcode
// file. Static self-registration is fragile the moment these objects live in a
// static library (the linker may drop an object file nothing references) and it
// leaves the listing order dependent on link order. One line per opcode is a
// small price for deterministic, debuggable behaviour.
void RegisterBuiltinOpcodes() {
  static bool registered = false;
  if (registered) {
    return;
  }
  registered = true;

  RegisterOpcode(GetFbbOpcode());
  RegisterOpcode(GetFbtOpcode());
  RegisterOpcode(GetFcaOpcode());
  RegisterOpcode(GetFdOpcode());
  RegisterOpcode(GetFdgOpcode());
  RegisterOpcode(GetFfOpcode());
  RegisterOpcode(GetFgaOpcode());
  RegisterOpcode(GetFmeanOpcode());
  RegisterOpcode(GetFmedianOpcode());
  RegisterOpcode(GetFomtOpcode());
  RegisterOpcode(GetFsnOpcode());
  RegisterOpcode(GetSwsOpcode());
}

}  // namespace mexitk
