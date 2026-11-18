import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { webcrypto } from "node:crypto";
import { readFile } from "node:fs/promises";
import * as esbuild from "esbuild-wasm";
import { compileProject } from "../runtime/compiler.mjs";

const root = new URL("../ios/", import.meta.url);
const read = path => readFile(new URL(path, root));
const types = JSON.parse(await read("Toolchain/types.json"));
const versions = JSON.parse(await read("Toolchain/versions.json"));
const libraries = await read("Toolchain/libraries.js");
const nativeFiles = Object.fromEntries(await Promise.all(["app/package.json", "app/manifest.json", "app/src/main.tsx"].map(async path => [path, await read("StarterProject/" + path)])));
const template = { files: nativeFiles, entry: "src/main.tsx", mode: "native" };
const compile = input => compileProject(esbuild, input, types, versions);

test("原生模板离线编译、输出 Source Map，真实 React 状态随开关事件提交新树", async () => {
  const product = await compile(template);
  assert.ok(product.files["bundle/main.js.map"]);
  const trees = [];
  const context = vm.createContext({
    setTimeout, clearTimeout, console, crypto: webcrypto,
    webkit: { messageHandlers: { voidRPC: { async postMessage(message) {
      if (message.method === "ui.commit") trees.push(message.params);
      return { id: message.id, result: { success: true, data: null } };
    } } } }
  });
  vm.runInContext(libraries.toString(), context);
  vm.runInContext(new TextDecoder().decode(product.files["bundle/main.js"]), context);
  const section = trees[0].nodes[0].children[0];
  assert.equal(section.type, "Section");
  const toggle = section.children.find(node => node.type === "Toggle");
  assert.equal(section.children.at(-1).props.value, "你好");
  context.__voidEvent({ id: toggle.id, name: "onChange", value: false, sequence: 1 });
  assert.equal(trees.at(-1).nodes[0].children[0].children.length, 2);
  assert.equal(trees.at(-1).eventSequence, 1);
  assert.equal(trees.at(-1).nodes[0].children[0].children[1].id, toggle.id);
});

test("类型诊断保留 TSX 文件和行列", async () => {
  const files = { ...nativeFiles, "app/src/main.tsx": Buffer.from("const n: number = '无效';") };
  await assert.rejects(compile({ ...template, files }), /app\/src\/main.tsx:1:\d+ TS2322/);
});

test("已有 HTML 项目编译模块、CSS 和资源，并隔离共享数据", async () => {
  const files = {
    "app/index.html": Buffer.from('<link rel="stylesheet" href="style.css"><script type="module" src="main.js"></script>'),
    "app/style.css": Buffer.from("body {color: red}"), "app/main.js": Buffer.from("globalThis.answer = 42;"),
    "assets/logo.png": Buffer.from([1, 2, 3]), "data/private.txt": Buffer.from("私人数据")
  };
  const product = await compile({ mode: "web", entry: "index.html", files });
  assert.equal(product.entry, "index.html");
  assert.ok(product.files["bundle/entry-0.css"]);
  assert.ok(product.files["bundle/entry-1.js"]);
  assert.ok(product.files["assets/logo.png"]);
  assert.ok(!product.files["data/private.txt"]);
  files["app/main.js"] = Buffer.from("import secret from '../data/private.txt'; console.log(secret)");
  await assert.rejects(compile({ mode: "web", entry: "index.html", files }), /找不到模块/);
});

test("缺失或不兼容的依赖会中止构建", async () => {
  const files = { ...nativeFiles, "app/package.json": Buffer.from('{"dependencies":{"react":"99"}}') };
  await assert.rejects(compile({ ...template, files }), /react@99/);
});
