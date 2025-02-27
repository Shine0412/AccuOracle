// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Fuzzilli

fileprivate let ForceDFGCompilationGenerator = CodeGenerator("ForceDFGCompilationGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.buildRepeatLoop(n: 10) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate let ForceFTLCompilationGenerator = CodeGenerator("ForceFTLCompilationGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.buildRepeatLoop(n: 100) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

// fileprivate let GcGenerator = CodeGenerator("GcGenerator") { b in
//     b.callFunction(b.createNamedVariable(forBuiltin: "gc"))
// }

let jscProfile = Profile(
    processArgs: { randomize in
        var args = [
            "--validateOptions=true",
            // No need to call functions thousands of times before they are JIT compiled
            "--thresholdForJITSoon=10",
            "--thresholdForJITAfterWarmUp=10",
            "--thresholdForOptimizeAfterWarmUp=100",
            "--thresholdForOptimizeAfterLongWarmUp=100",
            "--thresholdForOptimizeSoon=100",
            "--thresholdForFTLOptimizeAfterWarmUp=1000",
            "--thresholdForFTLOptimizeSoon=1000",
            // Enable bounds check elimination validation
            "--validateBCE=true",
            "--reprl"]

        guard randomize else { return args }

        args.append("--useBaselineJIT=\(probability(0.9) ? "true" : "false")")
        args.append("--useDFGJIT=\(probability(0.9) ? "true" : "false")")
        args.append("--useFTLJIT=\(probability(0.9) ? "true" : "false")")
        args.append("--useRegExpJIT=\(probability(0.9) ? "true" : "false")")
        args.append("--useTailCalls=\(probability(0.9) ? "true" : "false")")
        args.append("--optimizeRecursiveTailCalls=\(probability(0.9) ? "true" : "false")")
        args.append("--useObjectAllocationSinking=\(probability(0.9) ? "true" : "false")")
        args.append("--useArityFixupInlining=\(probability(0.9) ? "true" : "false")")
        args.append("--useValueRepElimination=\(probability(0.9) ? "true" : "false")")
        args.append("--useArchitectureSpecificOptimizations=\(probability(0.9) ? "true" : "false")")
        args.append("--useAccessInlining=\(probability(0.9) ? "true" : "false")")

        return args
    },

    processEnv: ["UBSAN_OPTIONS":"handle_segv=0"],

    maxExecsBeforeRespawn: 1000,

    timeout: 600,

    codePrefix: """
const builtins = [
  URIError, Math, Reflect, Uint8ClampedArray, isNaN, TypeError, Number, eval, NaN, Int8Array, AggregateError, 
  Int16Array, Symbol, Set, Object, EvalError, RangeError, String, Uint32Array, RegExp, isFinite, Promise, 
  DataView, Float64Array, WeakMap, BigInt, parseFloat, WeakSet, Uint16Array, Map, Array, Int32Array, ReferenceError, 
  Boolean, SyntaxError, Function, Error, Proxy, parseInt, ArrayBuffer, Infinity, Uint8Array, JSON, Float32Array];
  
function guard() {
  Math.random = () => 1;

  const OriginalDate = Date;
  const fixedTime = new OriginalDate('2025-01-01T00:00:00Z').getTime();
  Date.now = () => fixedTime;
  globalThis.Date = new Proxy(Date, {
    construct(target, args) { return new target(fixedTime); },
    apply(target, thisArg, args) { return fixedTime; }
  });
  Date.prototype.constructor = function Date(...args) {
    if (!(this instanceof Date)) { return new OriginalDate(fixedTime).toString(); }
    return new OriginalDate(fixedTime);
  };

  for (let k in builtins) {
    Object.freeze(builtins[k]);
    Object.freeze(builtins[k].prototype);
  }
}

function classOf(object) {
  var string = Object.prototype.toString.call(object);
  return string.substring(8, string.length - 1);
}

function deepObjectEquals(a, b) {
  var aProps = Object.keys(a);
  aProps.sort();
  var bProps = Object.keys(b);
  bProps.sort();
  if (!deepEquals(aProps, bProps)) {
    return false;
  }
  for (var i = 0; i < aProps.length; i++) {
    if (!deepEquals(a[aProps[i]], b[aProps[i]])) {
      return false;
    }
  }
  return true;
}

function deepEquals(a, b) {
  if (a === undefined && b === undefined) return false;
  if (a === b) {
    if (a === 0) return (1 / a) === (1 / b);
    return true;
  }
  if (typeof a != typeof b) return false;
  if (typeof a == 'number') return (isNaN(a) && isNaN(b)) || (a===b);
  if (typeof a !== 'object' && typeof a !== 'function' && typeof a !== 'symbol') return false;
  var objectClass = classOf(a);
  if (objectClass === 'Array') {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }                
  if (objectClass !== classOf(b)) return false;
  if (objectClass === 'RegExp') {
    return (a.toString() === b.toString());
  }
  if (objectClass === 'Function') return true;
 
  if (objectClass == 'String' || objectClass == 'Number' ||
      objectClass == 'Boolean' || objectClass == 'Date') {
    if (a.valueOf() !== b.valueOf()) return false;
  }
  return deepObjectEquals(a, b);
}

function opt(opt_param){
  "use strict";
                """,

    codeSuffix: """
}

guard();
let jit_0 = opt(true);
let jit_1 = opt(true);
if (deepEquals(jit_0, jit_1)) {
  for(let i = 0; i < 0x10; i++) {
    opt(false);
  }
  let jit_2 = opt(true);
  if (deepEquals(jit_0, jit_2)) {
    for(let i = 0; i < 0x200; i++) {
      opt(false);
    }
    let jit_3 = opt(true);
    if (!deepEquals(jit_0, jit_3)) {
      fuzzilli('FUZZILLI_CRASH', 0);
    }
  }
}
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    startupTests: [
        // Check that the fuzzilli integration is available.
        ("fuzzilli('FUZZILLI_PRINT', 'test')", .shouldSucceed),

        // Check that common crash types are detected.
        ("fuzzilli('FUZZILLI_CRASH', 0)", .shouldCrash),
        ("fuzzilli('FUZZILLI_CRASH', 1)", .shouldCrash),
        ("fuzzilli('FUZZILLI_CRASH', 2)", .shouldCrash),

        // TODO we could try to check that OOM crashes are ignored here ( with.shouldNotCrash).
    ],

    additionalCodeGenerators: [
        // (ForceDFGCompilationGenerator, 5),
        // (ForceFTLCompilationGenerator, 5),
        // (GcGenerator,                  5),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        // "gc"                  : .function([] => .undefined),
        // "transferArrayBuffer" : .function([.object(ofGroup: "ArrayBuffer")] => .undefined),
        // "noInline"            : .function([.function()] => .undefined),
        // "noFTL"               : .function([.function()] => .undefined),
        // "createGlobalObject"  : .function([] => .object()),
        // "OSRExit"             : .function([] => .anything),
        // "drainMicrotasks"     : .function([] => .anything),
        // "runString"           : .function([.string] => .anything),
        // "makeMasquerader"     : .function([] => .anything),
        // "fullGC"              : .function([] => .undefined),
        // "edenGC"              : .function([] => .undefined),
        // "fiatInt52"           : .function([.number] => .number),
        // "forceGCSlowPaths"    : .function([] => .anything),
        // "ensureArrayStorage"  : .function([] => .anything),
    ],

    additionalObjectGroups: [],

    optionalPostProcessor: nil
)
