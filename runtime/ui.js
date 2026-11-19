import Reconciler from "react-reconciler";
import { DefaultEventPriority } from "react-reconciler/constants";
import { request } from "./bridge.js";

export const VStack = "VStack", HStack = "HStack", List = "List", Form = "Form";
export const Section = "Section", Text = "Text", Image = "Image", Button = "Button";
export const TextField = "TextField", Toggle = "Toggle", Picker = "Picker";

let nextID = 0;
let revision = 0;
let eventSequence = 0;
let callbacks = new Map();
let previousCallbacks = new Map();
let sending = false;
let dirty = false;
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
  const props = {};
  for (const [key, value] of Object.entries(node.props)) {
    if (key === "children") continue;
    if (key === "onChange" || key === "onPress") {
      handlers.set(node.id + "/" + key, value);
    } else {
      props[key] = value;
    }
  }
  const children = node.children.filter(child => !child.hidden).map(child => serialize(child, handlers));
  return { id: node.id, type: node.type, props, children };
}

function publish() {
  dirty = true;
  if (sending) return;
  const handlers = new Map();
  const nodes = container.children.filter(node => !node.hidden).map(node => serialize(node, handlers));
  previousCallbacks = callbacks;
  callbacks = handlers;
  dirty = false;
  sending = true;
  void request("ui.commit", { revision: ++revision, eventSequence, nodes }).then(reply => {
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
export function render(view) {
  root ??= reconciler.createContainer(container, 0, null, false, null, "", console.error, null);
  reconciler.updateContainer(view, root, null, null);
}

globalThis.__voidEvent = ({ id, name, value, sequence, revision: displayedRevision }) => {
  if (sequence <= eventSequence || (displayedRevision != null && displayedRevision !== revision && displayedRevision !== revision - 1)) return;
  eventSequence = sequence;
  const handlers = displayedRevision === revision - 1 ? previousCallbacks : callbacks;
  handlers.get(id + "/" + name)?.(value);
};
