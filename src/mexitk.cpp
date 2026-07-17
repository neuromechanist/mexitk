// SPDX-License-Identifier: BSD-3-Clause
//
// Copyright (c) 2026, Seyed Yahya Shirazi <shirazi@ieee.org>
// Swartz Center for Computational Neuroscience (SCCN),
// Institute for Neural Computation (INC), UC San Diego.
//
// Part of mexitk, a MATLAB <-> ITK bridge. See LICENSE for BSD-3-Clause text.
//
// MEX entry point.
//
// Implements the MATITK calling convention:
//   mexitk(operationName, [parameters], [inputArray1], [inputArray2],
//          [seed(s)Array], [Image(s)Spacing])
//
// The convention (argument order, parameter lists, output arity, diagnostic
// wording) originates with MATITK by Vincent Chu and Ghassan Hamarneh (Simon
// Fraser University, 2005-2006). mexitk is a clean-room reimplementation of
// that convention against modern ITK; no MATITK source was available or used.
// Deviations from the original are enumerated in docs/COMPATIBILITY.md.

#include "mex.h"

#include "itkVersion.h"

#include "mexitk_common.h"
#include "opcode.h"

#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

namespace {

using mexitk::AllOpcodes;
using mexitk::Category;
using mexitk::CategoryName;
using mexitk::FindOpcode;
using mexitk::Opcode;
using mexitk::OpContext;
using mexitk::ParamSpec;
using mexitk::PixelTypeName;
using mexitk::RegisterBuiltinOpcodes;
using mexitk::StatusName;

constexpr const char* kVersion = "0.1.0";
constexpr const char* kUsage =
    "mexitk(operationName,[parameters],[inputArray1],[inputArray2],"
    "[seed(s)Array],[Image(s)Spacing])";

void PrintBanner() {
  mexPrintf("\nmexitk v.%s (BSD-3-Clause)\n", kVersion);
  mexPrintf("A MATLAB <-> ITK bridge built against ITK v.%s (https://www.itk.org)\n",
            itk::Version::GetITKVersion());
  mexPrintf(
      "Compatible with the MATITK calling convention by Vincent Chu and "
      "Ghassan Hamarneh (SFU, 2005-2006).\n");
  mexPrintf("For a list of allowed operations, type mexitk('?')\n");
}

void PrintOpcodeListing() {
  PrintBanner();
  const Category kOrder[] = {Category::kFilter, Category::kSegmentation,
                             Category::kRegistration};
  for (Category cat : kOrder) {
    bool header = false;
    for (const Opcode* op : AllOpcodes()) {
      if (op->GetCategory() != cat) {
        continue;
      }
      if (!header) {
        mexPrintf("\n--- %s ---\n", CategoryName(cat));
        header = true;
      }
      mexPrintf("  %-6s [%s] %s\n", op->Name(), StatusName(op->GetStatus()),
                op->Description());
      if (op->StatusNote() != nullptr) {
        mexPrintf("         note: %s\n", op->StatusNote());
      }
    }
  }
  mexPrintf(
      "\nStatus vocabulary:\n"
      "  validated         bit-identical to the original matitk binary,\n"
      "                    asserted by a test against a stored reference.\n"
      "  bounded-deviation compared against a reference and does NOT match\n"
      "                    bit-for-bit; the difference is a measured, bounded\n"
      "                    consequence of ITK's evolution from 2.4 to 5.x.\n"
      "                    The bound is asserted by a test. See the note.\n"
      "  smoke-tested      runs, but no reference capture exists.\n"
      "  untested          never run against a reference.\n"
      "See docs/COMPATIBILITY.md for the full record.\n");
  mexPrintf("\nExample:\n  load mri; V = squeeze(D);\n");
  mexPrintf("  b = mexitk('FCA',[5 0.0625 3.0], double(V));\n");
  mexPrintf("  [c1 c2] = mexitk('FOMT',[2 128], double(V));\n\n");
}

// Prints the per-opcode parameter list in the original's format, e.g.
//   numberOfIterations,
//   timeStep (which usually has value equal to 0.0625),
//   conductance (which usually has value equal to 3.0)
void PrintParamList(const Opcode* op) {
  mexPrintf(
      "You must supply parameters for this function in an array, with the "
      "elements in this order:\n");
  const std::vector<ParamSpec>& params = op->Params();
  for (size_t i = 0; i < params.size(); ++i) {
    mexPrintf("%s", params[i].name);
    if (params[i].hint != nullptr) {
      mexPrintf(" (which usually has value equal to %s)", params[i].hint);
    }
    mexPrintf(i + 1 < params.size() ? ",\n" : "\n");
  }
}

// Accepts a char array (as the original demanded) and additionally a string
// object. The original rejects "FCA" with "Opcode input field must be of type
// string." because MATLAB's string class postdates it by a decade; accepting
// both is a strict superset of the original's behaviour, so no working call
// changes meaning.
std::string GetOpcodeString(const mxArray* a) {
  if (mxIsChar(a)) {
    char* s = mxArrayToString(a);
    if (s == nullptr) {
      mexErrMsgIdAndTxt("mexitk:opcode", "Could not read operationName.");
    }
    std::string out(s);
    mxFree(s);
    return out;
  }
  if (mxIsClass(a, "string")) {
    mxArray* result[1] = {nullptr};
    mxArray* in[1] = {const_cast<mxArray*>(a)};
    if (mexCallMATLAB(1, result, 1, in, "char") == 0 && result[0] != nullptr &&
        mxIsChar(result[0])) {
      char* s = mxArrayToString(result[0]);
      std::string out(s == nullptr ? "" : s);
      mxFree(s);
      mxDestroyArray(result[0]);
      return out;
    }
  }
  mexErrMsgIdAndTxt("mexitk:opcode",
                    "operationName must be a char array or a string.");
  return {};
}

// Converts any real numeric mxArray to a double vector.
std::vector<double> ToDoubleVector(const mxArray* a, const char* what) {
  if (a == nullptr || mxIsEmpty(a)) {
    return {};
  }
  if (!mxIsNumeric(a) || mxIsComplex(a)) {
    mexErrMsgIdAndTxt("mexitk:args", "%s must be a real numeric array.", what);
  }
  const size_t n = mxGetNumberOfElements(a);
  std::vector<double> out(n);
  const bool ok = mexitk::DispatchOnPixelType(mxGetClassID(a), [&](auto tag) {
    using T = typename decltype(tag)::type;
    const T* p = static_cast<const T*>(mxGetData(a));
    for (size_t i = 0; i < n; ++i) {
      out[i] = static_cast<double>(p[i]);
    }
  });
  if (!ok) {
    mexErrMsgIdAndTxt("mexitk:args",
                      "%s must be of class double, single, uint8 or int32.", what);
  }
  return out;
}

const mxArray* OptionalVolume(int nrhs, const mxArray* prhs[], int index) {
  if (nrhs <= index || mxIsEmpty(prhs[index])) {
    return nullptr;
  }
  return prhs[index];
}

}  // namespace

void mexFunction(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[]) {
  RegisterBuiltinOpcodes();

  if (nrhs < 1) {
    PrintBanner();
    mexErrMsgIdAndTxt("mexitk:usage", "%s", kUsage);
  }

  const std::string opcodeName = GetOpcodeString(prhs[0]);

  if (opcodeName == "?") {
    PrintOpcodeListing();
    return;
  }

  const Opcode* op = FindOpcode(opcodeName);
  if (op == nullptr) {
    PrintOpcodeListing();
    mexErrMsgIdAndTxt("mexitk:unknownOpcode", "Unknown operation '%s'.\n%s",
                      opcodeName.c_str(), kUsage);
  }

  const std::vector<double> params = ToDoubleVector(nrhs > 1 ? prhs[1] : nullptr, "parameters");

  mexPrintf("\n%s is being executed...\n", opcodeName.c_str());

  const size_t required = op->Params().size();
  if (params.size() < required) {
    PrintParamList(op);
    mexPrintf("%zu parameters must be supplied.  You supplied %zu.\n", required,
              params.size());
    mexErrMsgIdAndTxt("mexitk:params",
                      "Correct number of parameters must be supplied.  At least "
                      "one image volume has to be supplied.");
  }
  if (params.size() > required) {
    // Matches the original, which warns and proceeds rather than erroring.
    mexWarnMsgIdAndTxt("mexitk:tooManyParams",
                       "Too many parameters supplied.  Are you sure you're "
                       "calling the right method? Proceeding anyway...");
  }

  const mxArray* volumeA = OptionalVolume(nrhs, prhs, 2);
  if (volumeA == nullptr) {
    mexErrMsgIdAndTxt("mexitk:noInput",
                      "At least one image volume has to be supplied.");
  }
  if (mxGetNumberOfDimensions(volumeA) != mexitk::kDimension) {
    mexErrMsgIdAndTxt("mexitk:not3D", "Input volume A must be a 3D image.");
  }
  if (mxIsComplex(volumeA) || PixelTypeName(mxGetClassID(volumeA)) == std::string("unsupported")) {
    mexErrMsgIdAndTxt("mexitk:pixelType",
                      "Input volume A must be real and of class double, single, "
                      "uint8 or int32.");
  }

  const mxArray* volumeB = OptionalVolume(nrhs, prhs, 3);
  if (volumeB != nullptr && mxGetNumberOfDimensions(volumeB) != mexitk::kDimension) {
    mexErrMsgIdAndTxt("mexitk:not3D", "Input volume B must be a 3D image.");
  }

  const std::vector<double> seeds =
      ToDoubleVector(nrhs > 4 ? prhs[4] : nullptr, "seed(s)Array");
  if (!seeds.empty() && seeds.size() % mexitk::kDimension != 0) {
    mexErrMsgIdAndTxt("mexitk:seeds",
                      "seed(s)Array length must be a multiple of 3 ([x1 y1 z1 "
                      "x2 y2 z2 ...]).");
  }
  for (double s : seeds) {
    if (s < 1.0) {
      mexErrMsgIdAndTxt("mexitk:seeds",
                        "Seed coordinates are 1-based; please note that array "
                        "in matlab starts from 1.");
    }
  }

  // Argument 6 (spacing) is parsed for call-compatibility but not applied: the
  // reference binary returns bit-identical output for [1 1 2] and [1 1 1], so
  // honouring it here would diverge from every existing caller. Validated so a
  // malformed value is still reported rather than silently swallowed.
  const std::vector<double> spacing =
      ToDoubleVector(nrhs > 5 ? prhs[5] : nullptr, "Image(s)Spacing");
  if (!spacing.empty() && spacing.size() != mexitk::kDimension) {
    mexErrMsgIdAndTxt("mexitk:spacing", "Image(s)Spacing must have 3 elements.");
  }

  mexPrintf("Image input of type %s detected, executing mexitk in %s mode\n",
            PixelTypeName(mxGetClassID(volumeA)), PixelTypeName(mxGetClassID(volumeA)));

  // MATLAB reports nlhs==0 for a bare statement call, which conventionally
  // still yields one value via ans.
  const int nargout = std::max(nlhs, 1);
  const int expected = op->OutputCount(params);
  if (nargout != expected) {
    mexPrintf("Expected number of output(s): %d.  Supplied output(s): %d\n", expected,
              nargout);
    mexErrMsgIdAndTxt("mexitk:nargout", "Mismatch number of output arguments.");
  }

  OpContext ctx;
  ctx.params = &params;
  ctx.volumeA = volumeA;
  ctx.volumeB = volumeB;
  ctx.seeds = &seeds;
  ctx.nargout = nargout;
  ctx.plhs = plhs;

  try {
    op->Execute(ctx);
  } catch (const itk::ExceptionObject& err) {
    // The original catches this same class of ITK failure and then dies: an SWS
    // overthresholding exception takes the whole MATLAB process down with a
    // segmentation violation. Reporting it as a MATLAB error instead is a
    // deliberate deviation; see docs/COMPATIBILITY.md.
    mexErrMsgIdAndTxt("mexitk:itkException", "ITK exception in %s: %s",
                      opcodeName.c_str(), err.what());
  } catch (const std::exception& err) {
    mexErrMsgIdAndTxt("mexitk:exception", "Exception in %s: %s", opcodeName.c_str(),
                      err.what());
  }

  mexPrintf("%s has completed.\n\n", opcodeName.c_str());
}
