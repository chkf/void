import Reconciler from "react-reconciler";
import { Children, cloneElement, createElement, Fragment, isValidElement } from "react";
import { DefaultEventPriority } from "react-reconciler/constants";
import { request } from "./bridge.js";

export const VStack = "VStack", HStack = "HStack", List = "List", Form = "Form";
export const Section = "Section", Text = "Text", Image = "Image", Button = "Button";
export const TextField = "TextField", Toggle = "Toggle", Picker = "Picker";
export const Theme = "Theme", Tab = "Tab", Screen = "Screen", ScrollView = "ScrollView";
export const Card = "Card", Spacer = "Spacer", ProgressView = "ProgressView";

// Give the React subtree the same identity as the native page, including when
// an application inserts or reorders tabs without an explicit React key.
export function TabView({ children, ...props }) {
  const tabs = [];
  const ids = new Set();
  function collect(child) {
    if (child == null) return;
    if (isValidElement(child) && child.type === Fragment) return Children.forEach(child.props.children, collect);
    if (!isValidElement(child) || child.type !== Tab) throw Error("TabView 的直接子项必须是 Tab");
    if (typeof child.props.id !== "string" || ids.has(child.props.id)) throw Error("Tab.id 必须是唯一的字符串");
    ids.add(child.props.id);
    tabs.push(cloneElement(child, { key: child.props.id }));
  }
  Children.forEach(children, collect);
  return createElement("TabView", props, tabs);
}

let nextID = 0;
let revision = 0;
let eventSequence = 0;
let callbacks = new Map();
let previousCallbacks = new Map();
let sending = false;
let dirty = false;
let uiVersion = 1;
let sentSequence = 0;
const container = { children: [] };

function remove(parent, child) {
  const index = parent.children.indexOf(child);
  if (index !== -1) parent.children.splice(index, 1);
}

function append(parent, child) {
  remove(parent, child);
  parent.children.push(child);
}

function insert(parent, child, before) {
  remove(parent, child);
  parent.children.splice(parent.children.indexOf(before), 0, child);
}

function serialize(node, handlers) {
  const props = Object.create(null);
  const event = node.type === Button ? "onPress" :
    [TextField, Toggle, Picker, "TabView"].includes(node.type) ? "onChange" : null;
  if (event && typeof node.props[event] !== "function") throw Error(node.type + "." + event + " 需要回调函数");
  for (const [key, value] of Object.entries(node.props)) {
    if (key === "children") continue;
    if (key === event) {
      if (!(node.type === Button && node.props.disabled === true)) {
        handlers.set(node.id + "/" + key, { callback: value, node });
      }
      continue;
    }
    if (value === undefined) continue;
    // WebKit can drop functions or coerce non-finite numbers before Swift sees
    // them. Only the two flat palette records and Picker's string array travel.
    if (node.type === Theme && (key === "light" || key === "dark")) {
      if (!value || typeof value !== "object" || Array.isArray(value) ||
          Object.keys(value).length > 9 || !Object.values(value).every(v => typeof v === "string")) {
        throw Error("Theme." + key + " 需要有限的语义色表");
      }
    } else if (node.type === Picker && key === "options") {
      if (!Array.isArray(value) || !value.every(v => typeof v === "string")) throw Error("Picker.options 需要文本数组");
    } else if (typeof value !== "string" && typeof value !== "boolean" && !Number.isFinite(value)) {
      throw Error(node.type + "." + key + " 属性值无效");
    }
    props[key] = value;
  }
  const children = node.children.filter(child => !child.hidden).map(child => serialize(child, handlers));
  return { id: node.id, type: node.type, props, children };
}

function publish() {
  dirty = true;
  if (sending) return;
  const handlers = new Map();
  let nodes;
  try {
    nodes = container.children.filter(node => !node.hidden).map(node => serialize(node, handlers));
  } catch (error) {
    dirty = false;
    void request("runtime.error", { message: String(error.message || error) });
    return;
  }
  previousCallbacks = callbacks;
  callbacks = handlers;
  dirty = false;
  sending = true;
  sentSequence = eventSequence;
  void request("ui.commit", { uiVersion, revision: ++revision, eventSequence, nodes }).then(reply => {
    if (!reply.success) console.error(reply.error.message);
  }).finally(() => {
    sending = false;
    if (dirty) publish();
  });
}

const reconciler = Reconciler({
  supportsMutation: true,
  isPrimaryRenderer: true,
  now: Date.now,
  getRootHostContext: () => null,
  getChildHostContext: context => context,
  getPublicInstance: node => node,
  prepareForCommit: () => null,
  resetAfterCommit: publish,
  createInstance: (type, props) => ({ id: String(++nextID), type, props, children: [] }),
  createTextInstance(value) {
    return { id: String(++nextID), type: Text, props: { value }, children: [] };
  },
  commitTextUpdate(node, oldText, value) { node.props = { value }; },
  shouldSetTextContent: () => false,
  finalizeInitialChildren: () => false,
  prepareUpdate: () => true,
  commitUpdate(node, update, type, oldProps, nextProps) { node.props = nextProps; },
  appendInitialChild: append,
  appendChild: append,
  appendChildToContainer: append,
  removeChild: remove,
  removeChildFromContainer: remove,
  insertBefore: insert,
  insertInContainerBefore: insert,
  clearContainer(root) { root.children.length = 0; },
  hideInstance(node) { node.hidden = true; },
  unhideInstance(node) { node.hidden = false; },
  hideTextInstance(node) { node.hidden = true; },
  unhideTextInstance(node) { node.hidden = false; },
  getCurrentEventPriority: () => DefaultEventPriority,
  scheduleTimeout: setTimeout,
  cancelTimeout: clearTimeout,
  noTimeout: -1,
  detachDeletedInstance() {}
});

let root;
function mount(view) {
  root ??= reconciler.createContainer(container, 0, null, false, null, "", console.error, null);
  reconciler.updateContainer(view, root, null, null);
}

export function render(view) {
  if (globalThis.__voidNativeUIVersion !== 2) throw Error("@runtime/ui@1.1.0 需要原生界面协议 2，请升级 void 宿主");
  uiVersion = 2;
  mount(view);
}

export const legacyUI = { VStack, HStack, List, Form, Section, Text, Image, Button, TextField, Toggle, Picker, render: mount };
export const nativeUI = { ...legacyUI, Theme, TabView, Tab, Screen, ScrollView, Card, Spacer, ProgressView, render };

globalThis.__voidEvent = ({ id, name, value, sequence, revision: displayedRevision }) => {
  if (sequence <= eventSequence || (displayedRevision != null && displayedRevision !== revision && displayedRevision !== revision - 1)) return;
  eventSequence = sequence;
  const handlers = displayedRevision === revision - 1 ? previousCallbacks : callbacks;
  const key = id + "/" + name;
  const handler = handlers.get(key);
  if (!handler || !callbacks.has(key) || (handler.node.type === Button && handler.node.props.disabled === true)) return;
  if (handler.node.type === "TabView" && !handler.node.children.some(tab => !tab.hidden && tab.props.id === value)) {
    if (sentSequence < sequence) publish();
    return;
  }
  handler.callback(value);
  // Even a controlled selection that the application declines needs an ACK.
  if (handler.node.type === "TabView" && sentSequence < sequence) publish();
};
