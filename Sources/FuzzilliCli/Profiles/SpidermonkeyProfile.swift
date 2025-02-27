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

fileprivate let ForceSpidermonkeyIonGenerator = CodeGenerator("ForceSpidermonkeyIonGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.buildRepeatLoop(n: 100) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate let GcGenerator = CodeGenerator("GcGenerator") { b in
    b.callFunction(b.createNamedVariable(forBuiltin: "gc"))
}

let spidermonkeyProfile = Profile(
    processArgs: { randomize in
        var args = [
            "--baseline-warmup-threshold=10",
            "--ion-warmup-threshold=50",
            "--ion-check-range-analysis",
            "--ion-extra-checks",
            "--fuzzing-safe",
            "--disable-oom-functions",
            "--reprl"]

        guard randomize else { return args }

        args.append("--small-function-length=\(1<<Int.random(in: 7...12))")
        args.append("--inlining-entry-threshold=\(1<<Int.random(in: 2...10))")
        args.append("--gc-zeal=\(probability(0.5) ? UInt32(0) : UInt32(Int.random(in: 1...24)))")
        args.append("--ion-scalar-replacement=\(probability(0.9) ? "on": "off")")
        args.append("--ion-pruning=\(probability(0.9) ? "on": "off")")
        args.append("--ion-range-analysis=\(probability(0.9) ? "on": "off")")
        args.append("--ion-inlining=\(probability(0.9) ? "on": "off")")
        args.append("--ion-gvn=\(probability(0.9) ? "on": "off")")
        args.append("--ion-osr=\(probability(0.9) ? "on": "off")")
        args.append("--ion-edgecase-analysis=\(probability(0.9) ? "on": "off")")
        args.append("--nursery-size=\(1<<Int.random(in: 0...5))")
        args.append("--nursery-strings=\(probability(0.9) ? "on": "off")")
        args.append("--nursery-bigints=\(probability(0.9)  ? "on": "off")")
        args.append("--spectre-mitigations=\(probability(0.1) ? "on": "off")")
        if probability(0.1) {
            args.append("--no-native-regexp")
        }
        args.append("--ion-optimize-shapeguards=\(probability(0.9) ? "on": "off")")
        args.append("--ion-licm=\(probability(0.9) ? "on": "off")")
        args.append("--ion-instruction-reordering=\(probability(0.9) ? "on": "off")")
        args.append("--cache-ir-stubs=\(probability(0.9) ? "on": "off")")
        args.append(chooseUniform(from: ["--no-sse3", "--no-ssse3", "--no-sse41", "--no-sse42", "--enable-avx"]))
        if probability(0.1) {
            args.append("--ion-regalloc=testbed")
        }
        args.append(probability(0.9) ? "--enable-watchtower" : "--disable-watchtower")
        args.append("--ion-sink=\(probability(0.0) ? "on": "off")") // disabled
        return args
    },

    processEnv: ["UBSAN_OPTIONS": "handle_segv=0"],

    maxExecsBeforeRespawn: 1000,

    timeout: 250,

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
                  // If called directly, a string with a fixed time is returned. 
                  // If called through new, a Date object with a fixed time is returned.
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
                if (jit_0===jit_1) {
                  for (let i = 0; i < 55; i++) {
                    opt(false);
                  }
                  let jit_2 = opt(true);
                  if (!deepEquals(jit_0, jit_2)) {
                    fuzzilli('FUZZILLI_CRASH', 0);
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
        // (ForceSpidermonkeyIonGenerator, 10),
        // (GcGenerator,                   10),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        // "gc"            : .function([] => .undefined),
        // "enqueueJob"    : .function([.function()] => .undefined),
        // "drainJobQueue" : .function([] => .undefined),
        // "bailout"       : .function([] => .undefined),

    ],

    additionalObjectGroups: [],

    optionalPostProcessor: nil
)
