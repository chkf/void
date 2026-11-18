import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { webcrypto } from "node:crypto";
import { readFile } from "node:fs/promises";
import * as esbuild from "esbuild-wasm";
import ts from "typescript";
import { compileProject } from "../runtime/compiler.mjs";

const root = new URL("../ios/", import.meta.url);
const read = path => readFile(new URL(path, root));
const types = JSON.parse(await read("Toolchain/types.json"));
const versions = JSON.parse(await read("Toolchain/versions.json"));
const libraries = await read("Toolchain/libraries.js");
const nativeFiles = Object.fromEntries(await Promise.all(["app/package.json", "app/manifest.json", "app/src/main.tsx"].map(async path => [path, await read("TSXProject/" + path)])));
const template = { files: nativeFiles, entry: "src/main.tsx", mode: "native" };
const compile = input => compileProject(esbuild, input, types, versions);

test("取消的编译会终止工作线程，迟到的回调不能交付到下一次构建", async () => {
  const workers = [];
  class Worker {
    constructor(path) { assert.equal(path, "compiler.js"); this.stops = 0; workers.push(this); }
    postMessage(input) { this.input = input; }
    terminate() { this.stops++; }
  }
  const context = vm.createContext({ Worker });
  vm.runInContext((await read("Toolchain/compiler-client.js")).toString(), context);
  const input = { paths: ["app/有 空格.tsx"], entry: "有 空格.tsx", mode: "native" };
  const first = context.buildProject(input);
  const rejected = assert.rejects(first, /已取消编译/);
  context.cancelVoidBuild();
  await rejected;
  const next = context.buildProject(input);
  workers[0].onmessage({ data: { entry: "stale" } });
  workers[1].onmessage({ data: { entry: "new" } });
  assert.equal((await next).entry, "new");
  assert.equal(workers[1].input.paths[0], input.paths[0]);
  assert.deepEqual(workers.map(w => w.stops), [1, 1]);
});

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

test("18 组原生接口的 TypeScript、运行时和 IPA 注册表逐项一致", async () => {
  const catalog = JSON.parse(await read("Toolchain/sdk-api.json"));
  const context = vm.createContext({ setTimeout, clearTimeout, console, crypto: webcrypto });
  vm.runInContext(libraries.toString(), context);
  const sdk = context.__voidLibraries["@runtime/sdk"].ios;
  const source = ts.createSourceFile("sdk.d.ts", types["/node_modules/@runtime/sdk/index.d.ts"], ts.ScriptTarget.Latest, true);
  const declaration = source.statements.find(node => ts.isInterfaceDeclaration(node) && node.name.text === "NativeSDK");
  const reference = (await read("Toolchain/sdk-reference.md")).toString();
  const documented = {};
  let group;
  for (const line of reference.split(/\r?\n/)) {
    const header = line.match(/^\| 权限 \| `ios\.(\w+)` 方法 \|/);
    if (header) { group = header[1]; documented[group] = {}; continue; }
    const row = line.match(/^\| (?:项目基础能力|`([\w.]+)`) \| (.*) \|$/);
    if (row && group) {
      for (const match of row[2].matchAll(/`(\w+)`/g)) documented[group][match[1]] = row[1] ?? "";
    }
  }
  assert.deepEqual(documented, catalog, "每个接口的离线说明和权限都应与应用一致");
  assert.equal(Object.keys(catalog).length, 18);
  for (const [group, methods] of Object.entries(catalog)) {
    const names = Object.keys(methods).sort();
    const field = declaration.members.find(node => node.name.text === group);
    assert.deepEqual(field.type.members.map(node => node.name.text).sort(), names, group);
    assert.deepEqual(Object.keys(sdk[group]).sort(), names, group);
  }
  assert.equal(sdk.version, versions["@runtime/sdk"]);
  const files = { ...nativeFiles, "app/src/main.tsx": Buffer.from('import {ios} from "@runtime/sdk"; async function save(){ const res = await ios.fs.writeFile({path:"data/name.txt",data:"名字"}); if (!res.success) throw Error(res.error.code); } void save();') };
  assert.ok((await compile({ ...template, files })).files["bundle/main.js"]);
  files["app/package.json"] = Buffer.from('{"dependencies":{"@runtime/sdk":"1.0.0"}}');
  assert.ok((await compile({ ...template, files })).files["bundle/main.js"]);
  files["app/src/main.tsx"] = Buffer.from('import {ios} from "@runtime/sdk"; ios.fs.writeFile({path:9,data:"x"});');
  await assert.rejects(compile({ ...template, files }), /TS2322/);
});

test("中止、超时与事件退订使用所属页面的桥接会话", async () => {
  const messages = [];
  const context = vm.createContext({ setTimeout, clearTimeout, console, crypto:webcrypto,
    webkit:{messageHandlers:{voidRPC:{postMessage(message) {
      messages.push(message);
      return message.method === "sdk.cancel" ? Promise.resolve({id:message.id}) : new Promise(() => {});
    }}}} });
  vm.runInContext(libraries.toString(), context);
  const sdk = context.__voidLibraries["@runtime/sdk"].ios;
  const controller = new AbortController();
  const running = sdk.fs.readFile({path:"data/x"},{signal:controller.signal});
  controller.abort();
  assert.equal((await running).error.code, "CANCELLED");
  assert.equal(messages[1].params.id, messages[0].id);
  assert.equal((await sdk.fs.readFile({path:"data/x"},{timeoutMs:5})).error.code,"TIMEOUT");
  const events = [];
  const unsubscribe = sdk.onEvent(event => events.push(event.id));
  context.__voidNativeEvent({id:"local"});
  unsubscribe();
  context.__voidNativeEvent({id:"ended"});
  assert.deepEqual(events, ["local"]);
});
