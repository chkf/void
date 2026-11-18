import * as esbuild from "esbuild-wasm/lib/browser.js";
import { compileProject, fromBase64, toBase64 } from "./compiler.mjs";

let ready;
globalThis.buildProject = async input => {
  ready ??= Promise.all([
    esbuild.initialize({ wasmURL: "esbuild.wasm", worker: false }),
    fetch("types.json").then(response => response.json()),
    fetch("versions.json").then(response => response.json())
  ]);
  const [, types, versions] = await ready;
  const files = Object.fromEntries(Object.entries(input.files).map(([key, value]) => [key, fromBase64(value)]));
  const output = await compileProject(esbuild, { ...input, files }, types, versions);
  return { entry: output.entry, files: Object.fromEntries(Object.entries(output.files).map(([key, bytes]) => [key, toBase64(bytes)])) };
};
