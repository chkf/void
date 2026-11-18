import * as esbuild from "esbuild-wasm/lib/browser.js";
import { compileProject, toBase64 } from "./compiler.mjs";

async function buildProject(input) {
  const [, types, versions] = await Promise.all([
    esbuild.initialize({ wasmURL: "esbuild.wasm", worker: false }),
    fetch("types.json").then(response => response.json()),
    fetch("versions.json").then(response => response.json())
  ]);
  const files = Object.create(null);
  for (let offset = 0; offset < input.paths.length; offset += 6) {
    await Promise.all(input.paths.slice(offset, offset + 6).map(async key => {
      const response = await fetch("source/" + key.split("/").map(encodeURIComponent).join("/"));
      if (!response.ok) throw new Error("构建快照读取失败 " + response.status);
      files[key] = new Uint8Array(await response.arrayBuffer());
    }));
  }
  const output = await compileProject(esbuild, { ...input, files }, types, versions);
  // Unchanged published assets already exist in the native snapshot. Return their keys only.
  const originals = new Map(Object.entries(files).map(([key, bytes]) => [bytes, key]));
  const generated = Object.create(null), copied = Object.create(null);
  for (const [key, bytes] of Object.entries(output.files)) {
    if (originals.has(bytes)) copied[key] = originals.get(bytes);
    else generated[key] = toBase64(bytes);
  }
  return { entry: output.entry, files: generated, copied };
}

self.onmessage = async event => {
  try { self.postMessage(await buildProject(event.data)); }
  catch (error) { self.postMessage({ failure: String(error.message || error) }); }
};
