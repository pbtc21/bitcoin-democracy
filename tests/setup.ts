import { expect } from "vitest";
import { Cl, ClarityValue, ClarityType, isClarityType } from "@stacks/transactions";

// Custom matchers for Clarity values
expect.extend({
  toBeOk(received: ClarityValue, expected?: ClarityValue) {
    if (received.type !== ClarityType.ResponseOk) {
      return {
        pass: false,
        message: () => `Expected (ok ...) but got: ${Cl.prettyPrint(received)}`,
      };
    }
    if (expected !== undefined) {
      const innerMatch = Cl.prettyPrint(received.value) === Cl.prettyPrint(expected);
      return {
        pass: innerMatch,
        message: () =>
          `Expected (ok ${Cl.prettyPrint(expected)}) but got (ok ${Cl.prettyPrint(received.value)})`,
      };
    }
    return { pass: true, message: () => "" };
  },

  toBeErr(received: ClarityValue, expected?: ClarityValue) {
    if (received.type !== ClarityType.ResponseErr) {
      return {
        pass: false,
        message: () => `Expected (err ...) but got: ${Cl.prettyPrint(received)}`,
      };
    }
    if (expected !== undefined) {
      const innerMatch = Cl.prettyPrint(received.value) === Cl.prettyPrint(expected);
      return {
        pass: innerMatch,
        message: () =>
          `Expected (err ${Cl.prettyPrint(expected)}) but got (err ${Cl.prettyPrint(received.value)})`,
      };
    }
    return { pass: true, message: () => "" };
  },

  toBeBool(received: ClarityValue, expected: boolean) {
    const pass =
      received.type === ClarityType.BoolTrue
        ? expected === true
        : received.type === ClarityType.BoolFalse
        ? expected === false
        : false;
    return {
      pass,
      message: () => `Expected ${expected} but got ${Cl.prettyPrint(received)}`,
    };
  },

  toBeUint(received: ClarityValue, expected: number | bigint) {
    const pass =
      received.type === ClarityType.UInt && received.value === BigInt(expected);
    return {
      pass,
      message: () => `Expected u${expected} but got ${Cl.prettyPrint(received)}`,
    };
  },

  toBeSome(received: ClarityValue, expected?: ClarityValue) {
    if (received.type !== ClarityType.OptionalSome) {
      return {
        pass: false,
        message: () => `Expected (some ...) but got: ${Cl.prettyPrint(received)}`,
      };
    }
    return { pass: true, message: () => "" };
  },

  toBeNone(received: ClarityValue) {
    return {
      pass: received.type === ClarityType.OptionalNone,
      message: () => `Expected none but got ${Cl.prettyPrint(received)}`,
    };
  },
});

// Type augmentation
declare module "vitest" {
  interface Assertion<T = any> {
    toBeOk(expected?: ClarityValue): void;
    toBeErr(expected?: ClarityValue): void;
    toBeBool(expected: boolean): void;
    toBeUint(expected: number | bigint): void;
    toBeSome(expected?: ClarityValue): void;
    toBeNone(): void;
  }
}
