import { build } from "esbuild-wasm";
import { createHash } from "node:crypto";
import { copyFile, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { resolve, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const output = resolve(root, "ios/Toolchain");
await mkdir(output, { recursive: true });
const deps = JSON.parse(await readFile(join(root, "package.json"), "utf8")).devDependencies;
const versions = { react: deps.react, "react-dom": deps["react-dom"], "@runtime/ui": "1.0.0", "@runtime/sdk": "1.1.0" };
await copyFile(join(root, "runtime/sdk-api.json"), join(output, "sdk-api.json"));
await copyFile(join(root, "runtime/sdk.d.ts"), join(output, "sdk.d.ts"));
const reference = (await readFile(join(root, "docs/SDK_REFERENCE.md"), "utf8"))
  .replace("(../runtime/sdk.d.ts)", "(types/runtime-sdk.d.ts)")
  .replace("(BUILD.md)", "(https://github.com/chkf/void/blob/main/docs/BUILD.md)")
  .replace("(LIMITATIONS.md)", "(https://github.com/chkf/void/blob/main/docs/LIMITATIONS.md)");
await writeFile(join(output, "sdk-reference.md"), reference);
const types = Object.create(null);
async function declarations(dir, virtual, filter) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!entry.name.startsWith("ts") && entry.name !== "node_modules") await declarations(path, virtual + "/" + entry.name, filter);
    } else if (filter.test(entry.name)) {
      types[virtual + "/" + entry.name] = await readFile(path, "utf8");
    }
  }
}
await declarations(join(root, "node_modules/typescript/lib"), "/lib", /^lib\..*\.d\.ts$/);
for (const name of ["@types/react", "@types/react-dom", "@types/prop-types", "csstype"]) {
  await declarations(join(root, "node_modules", name), "/node_modules/" + name, /(?:\.d\.ts$|^package\.json$)/);
}
for (const name of ["ui", "sdk"]) {
  types["/node_modules/@runtime/" + name + "/index.d.ts"] = await readFile(join(root, "runtime/" + name + ".d.ts"), "utf8");
}
await writeFile(join(output, "types.json"), JSON.stringify(types));
await writeFile(join(output, "versions.json"), JSON.stringify(versions));
for (const [entry, name] of [["libraries.js", "libraries.js"], ["browser-compiler.mjs", "compiler.js"]]) {
  await build({
    entryPoints: [join(root, "runtime", entry)], outfile: join(output, name),
    platform: "browser", format: "iife", bundle: true, minify: true, target: "safari17",
    define: { "process.env.NODE_ENV": '"production"' }
  });
}
await copyFile(join(root, "node_modules/esbuild-wasm/esbuild.wasm"), join(output, "esbuild.wasm"));
await copyFile(join(root, "runtime/compiler-client.js"), join(output, "compiler-client.js"));
await writeFile(join(output, "index.html"), '<!doctype html><meta charset="utf-8"><script src="compiler-client.js"></script>');
const licenses = [];
for (const name of [...Object.keys(deps).filter(n => !n.includes("openspec")), "scheduler", "csstype", "@types/prop-types", "entities", "loose-envify", "js-tokens"]) {
  const dir = join(root, "node_modules", name);
  const file = (await readdir(dir)).find(path => /^licen[sc]e(?:\.|$)/i.test(path));
  if (!file) throw new Error("缺少许可证 " + name);
  licenses.push(name + "\n" + await readFile(join(dir, file), "utf8"));
}
await writeFile(join(output, "LICENSES.txt"), licenses.join("\n\n"));
const hash = createHash("sha256");
for (const file of ["compiler-client.js", "compiler.js", "esbuild.wasm", "libraries.js", "types.json", "versions.json"]) {
  hash.update(await readFile(join(output, file)));
}
await writeFile(join(output, "build-id.txt"), hash.digest("hex"));
console.log("iOS 离线工具链已生成");
