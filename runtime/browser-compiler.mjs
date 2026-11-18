import * as esbuild from "esbuild-wasm/lib/browser.js";
import { compileProject, toBase64 } from "./compiler.mjs";

async function buildProject(input) {
  const [types, versions] = await Promise.all([
    fetch("types.json").then(response => response.json()),
    fetch("versions.json").then(response => response.json())
  ]);
  const files = Object.create(null);
  async function fetchSource(key) {
    const response = await fetch("source/" + key.split("/").map(encodeURIComponent).join("/"));
    if (!response.ok) throw new Error("构建快照读取失败 " + response.status);
    return new Uint8Array(await response.arrayBuffer());
  }
  // A distinct marker lets unchanged binary assets pass through by name. Only
  // esbuild imports need their bytes in this process; type checking uses text.
  const texts = new Set(input.paths.filter(key => /\.(?:[cm]?[jt]sx?|json)$/i.test(key) ||
    (input.mode === "web" && key.startsWith("app/") && /\.html?$/i.test(key))));
  for (const key of input.paths) files[key] = new Uint8Array(0);
  const names = [...texts];
  for (let offset = 0; offset < names.length; offset += 6) {
    await Promise.all(names.slice(offset, offset + 6).map(async key => {
      files[key] = await fetchSource(key);
    }));
  }
  const readSource = key => texts.has(key) ? files[key] : fetchSource(key);
  const bundler = { async build(options) {
    await esbuild.initialize({ wasmURL: "esbuild.wasm", worker: false });
    return esbuild.build(options);
  } };
  const output = await compileProject(bundler, { ...input, files, readSource }, types, versions);
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
