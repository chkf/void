import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";
import * as esbuild from "esbuild-wasm";
import { compileProject } from "../runtime/compiler.mjs";

const tool = name => readFile(new URL("../ios/Toolchain/" + name, import.meta.url), "utf8");
const types = JSON.parse(await tool("types.json"));
const versions = JSON.parse(await tool("versions.json"));
const libraries = await tool("libraries.js");
const example = await tool("NativeUIDemo/app/src/main.tsx");
const pkg = await tool("NativeUIDemo/app/package.json");
const settle = () => new Promise(resolve => setImmediate(resolve));

function compile(source = example, dependencies = pkg) {
  const files = { "app/package.json": Buffer.from(dependencies), "app/src/main.tsx": Buffer.from(source) };
  return compileProject(esbuild, { mode: "native", entry: "src/main.tsx", files }, types, versions);
}

function session({ hold = false, version = 2 } = {}) {
  const commits = [], errors = [], replies = [];
  const context = vm.createContext({ setTimeout, clearTimeout, console, crypto: webcrypto, __voidNativeUIVersion: version,
    webkit: { messageHandlers: { voidRPC: { async postMessage({ id, method, params }) {
      if (method === "ui.commit") {
        commits.push(params);
        if (hold) await new Promise(resolve => replies.push(resolve));
      } else if (method === "runtime.error") { errors.push(params.message); }
      return { id, result: { success: true, data: null } };
    } } } }
  });
  vm.runInContext(libraries, context);
  function find(predicate, node = commits.at(-1).nodes[0]) {
    if (predicate(node)) return node;
    for (const child of node.children) {
      const match = find(predicate, child);
      if (match) return match;
    }
  }
  let seq = 0;
  function event(id, name, value, revision = commits.at(-1).revision) {
    context.__voidEvent({ id, name, value, sequence: ++seq, revision });
  }
  return { context, commits, errors, replies, find, event,
    run(product) { vm.runInContext(new TextDecoder().decode(product.files["bundle/main.js"]), context); } };
}

test("锁定的 UI 版本选择各自导出和声明，旧宿主打开新版产物会给出升级提示", async () => {
  assert.equal(versions["@runtime/ui"], "1.1.0");
  const old = pkg.replace("1.1.0", "1.0.0");
  await assert.rejects(compile(example, old), /no exported member|has no exported member/i);
  await assert.rejects(compile('import {Text} from "@runtime/ui"; <Text value="x" font="title"/>;', old), /TS2322/);
  for (const unsupported of ["^1.1.0", "1.0.1", "1.1.1", "latest"]) {
    await assert.rejects(compile(example, pkg.replace("1.1.0", unsupported)), /不支持 @runtime\/ui/);
  }
  await assert.rejects(compile('import {Text} from "@runtime/ui"; <Text value="x" color="red"/>;'), /TS2322/);
  const app = await compile();
  assert.throws(() => session({ version: 1 }).run(app), /升级 void 宿主/);
  const legacy = session({ version: 1 });
  legacy.run(await compile('import {render,Text} from "@runtime/ui"; render(<Text value="old"/>);', old));
  assert.equal(legacy.commits[0].uiVersion, 1);
});

test("离线示例经真实 renderer 往返选中、表单和主题，动态增删标签保留已挂载组件", async () => {
  const ui = session();
  ui.run(await compile());
  const lookup = type => ui.find(n => n.type === type);
  const button = label => ui.find(n => n.type === "Button" && n.props.label === label);
  assert.equal(ui.commits[0].uiVersion, 2);
  assert.equal(lookup("TabView").children.length, 2);
  const [home, settings] = lookup("TabView").children;
  assert.equal(ui.find(n => n.type === "ProjectManagementButton", home), undefined);
  assert.ok(ui.find(n => n.type === "ProjectManagementButton", settings));
  const input = lookup("TextField").id;
  ui.event(input, "onChange", "保留输入");
  await settle();
  ui.event(button("增加").id, "onPress", null);
  await settle();
  assert.equal(lookup("ProgressView").props.value, 1);
  ui.event(lookup("TabView").id, "onChange", "settings");
  await settle();
  assert.equal(lookup("TabView").props.selection, "settings");
  ui.event(button("深色").id, "onPress", null);
  await settle();
  assert.equal(lookup("Theme").props.mode, "dark");
  ui.event(lookup("Toggle").id, "onChange", true);
  await settle();
  assert.equal(lookup("TabView").children.length, 3);
  ui.event(lookup("TabView").id, "onChange", "rows");
  await settle();
  assert.equal(lookup("TabView").props.selection, "rows");
  ui.event(lookup("TabView").id, "onChange", "settings");
  await settle();
  ui.event(lookup("Toggle").id, "onChange", false);
  await settle();
  ui.event(lookup("TabView").id, "onChange", "components");
  await settle();
  assert.equal(lookup("TabView").children.length, 2);
  assert.equal(lookup("TextField").id, input);
  assert.equal(lookup("TextField").props.value, "保留输入");
  assert.equal(lookup("ProgressView").props.value, 1);
  assert.deepEqual(ui.errors, []);
});

test("快速切换合并到最终选中值，受控拒绝也确认序号，过期事件和禁用按钮不能调用旧回调", async () => {
  const ui = session({ hold: true });
  const react = ui.context.__voidLibraries.react;
  const { render, TabView, Tab, Button } = ui.context.__voidLibraries["@runtime/ui@1.1.0"];
  const h = react.createElement;
  let clicks = 0, changes = 0, mounts = 0, pageMounts = 0, reverse, allow = true;
  function Child() {
    react.useState(() => ++pageMounts);
    return null;
  }
  function Root() {
    react.useState(() => ++mounts);
    const [selection, select] = react.useState("a");
    const [flipped, flip] = react.useState(false);
    reverse = () => flip(v => !v);
    return h(TabView, { selection, onChange: id => { changes++; if (allow) select(id); } },
      (flipped ? ["b","a"] : ["a","b"]).map(id => h(Tab, { id, title: id, systemName: "circle" },
        h(Child), h(Button, { label: id, disabled: selection === "b", onPress: () => { clicks++; } }))));
  }
  render(h(Root));
  const first = ui.commits[0], id = first.nodes[0].id;
  const buttonID = ui.find(n => n.type === "Button").id;
  for (let i = 0; i < 41; i++) ui.event(id, "onChange", i % 2 ? "a" : "b", first.revision);
  assert.equal(ui.commits.length, 1);
  ui.replies.shift()();
  await settle();
  const last = ui.commits.at(-1);
  assert.equal(ui.commits.length, 2);
  assert.equal(last.nodes[0].props.selection, "b");
  assert.equal(last.eventSequence, 41);
  ui.event(buttonID, "onPress", null, first.revision);
  ui.event(buttonID, "onPress", null);
  assert.equal(clicks, 0);
  reverse();
  ui.replies.shift()();
  await settle();
  assert.equal(ui.find(n => n.type === "Button" && n.props.label === "a").id, buttonID);
  assert.equal(mounts, 1);
  assert.equal(pageMounts, 2);
  ui.event(id, "onChange", "a", first.revision);
  assert.equal(changes, 41);
  allow = false;
  ui.event(id, "onChange", "a");
  ui.replies.shift()();
  await settle();
  assert.equal(changes, 42);
  assert.equal(ui.commits.at(-1).nodes[0].props.selection, "b");
  assert.equal(ui.commits.at(-1).eventSequence, 45);
  const count = ui.commits.length;
  ui.replies.shift()();
  await settle();
  assert.equal(ui.commits.length, count);
  ui.event(id, "onChange", "a", first.revision);
  assert.equal(ui.commits.at(-1).eventSequence, 46);
  assert.equal(ui.commits.at(-1).nodes[0].props.selection, "b");
  assert.equal(changes, 42);
  ui.replies.shift()();
});

test("WebKit 序列化前报告无效回调、非有限数值和嵌套样式", () => {
  const ui = session();
  const { render, Theme, Button, ProgressView } = ui.context.__voidLibraries["@runtime/ui@1.1.0"];
  const h = ui.context.__voidLibraries.react.createElement;
  for (const element of [h(ProgressView, { value: NaN }), h(ProgressView, { value: Infinity }),
                         h(Theme, { light: { text: { deep: true } } }), h(Button, { label: "x" })]) render(element);
  assert.equal(ui.commits.length, 0);
  assert.equal(ui.errors.length, 4);
});

test("一个原生事件同时删除选中页并更新受控值，整个过程中每次提交均有有效选择", async () => {
  const ui = session();
  const react = ui.context.__voidLibraries.react, h = react.createElement;
  const { render, TabView, Tab, Button } = ui.context.__voidLibraries["@runtime/ui@1.1.0"];
  function Tabs() {
    const [ids, setIDs] = react.useState(["a", "b", "c"]);
    const [selection, select] = react.useState("c");
    return h(TabView, { selection, onChange: select }, ids.map(id =>
      h(Tab, { id, title: id, systemName: "circle" }, h(Button, { label: id, onPress: () => {
        setIDs(["b", "a"]);
        select("a");
      } }))));
  }
  render(h(Tabs));
  await settle();
  const stable = ui.find(n => n.type === "Button" && n.props.label === "a").id;
  ui.event(ui.find(n => n.type === "Button" && n.props.label === "c").id, "onPress", null);
  await settle();
  assert.equal(ui.commits.length, 2);
  const nav = ui.commits[1].nodes[0];
  assert.equal(nav.props.selection, "a");
  assert.deepEqual(Array.from(nav.children, n => n.props.id), ["b", "a"]);
  assert.equal(ui.find(n => n.type === "Button" && n.props.label === "a").id, stable);
});
