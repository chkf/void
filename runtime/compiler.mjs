import ts from "typescript";
import { parse, serialize } from "parse5";

const extensions = [".ts", ".tsx", ".js", ".jsx", ".mjs", ".json"];
const loaders = { ts: "ts", tsx: "tsx", js: "js", mjs: "js", cjs: "js", jsx: "jsx", css: "css", json: "json" };
const decoder = new TextDecoder();
const encoder = new TextEncoder();
const builtins = new Set(["react", "react/jsx-runtime", "react-dom", "react-dom/client", "@runtime/ui", "@runtime/sdk"]);

export function fromBase64(text) {
  return Uint8Array.from(atob(text), c => c.charCodeAt(0));
}

export function toBase64(bytes) {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 8192) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  }
  return btoa(binary);
}

function relative(parent, specifier) {
  if (specifier.includes("\\") || specifier.includes("\0") || /^[\w+.-]+:|^\/\//.test(specifier)) {
    throw new Error("不支持的模块或资源地址 " + specifier);
  }
  const parts = specifier.startsWith("/") ? ["app"] : parent.split("/").slice(0, -1);
  for (const part of specifier.split("/")) {
    if (!part || part === ".") continue;
    if (part === "..") {
      if (!parts.length) throw new Error("路径超出项目 " + specifier);
      parts.pop();
    } else {
      parts.push(part);
    }
  }
  return parts.join("/");
}

function findModule(files, path) {
  return [path, ...extensions.map(ext => path + ext), ...extensions.map(ext => path + "/index" + ext)]
    .find(name => Object.hasOwn(files, name));
}

function typecheck(files, declarations, roots) {
  if (!roots.length) return;
  const options = {
    strict: true, noEmit: true, allowJs: true, checkJs: false, skipLibCheck: true,
    target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext,
    jsx: ts.JsxEmit.ReactJSX, moduleResolution: ts.ModuleResolutionKind.Bundler,
    lib: ["lib.es2022.d.ts", "lib.dom.d.ts", "lib.dom.iterable.d.ts"], types: [],
    baseUrl: "/", paths: { "*": ["modules/*", "node_modules/*"] }
  };
  const texts = new Map(Object.entries(declarations));
  for (const [name, bytes] of Object.entries(files)) {
    if (/\.(?:[cm]?[jt]sx?|json)$/.test(name)) texts.set("/" + name, decoder.decode(bytes));
  }
  const dirs = new Set(["/"]);
  for (const path of texts.keys()) {
    let dir = path;
    while ((dir = dir.slice(0, dir.lastIndexOf("/")))) dirs.add(dir);
  }
  const host = {
    fileExists: path => texts.has(path),
    readFile: path => texts.get(path),
    directoryExists: path => dirs.has(path.replace(/\/+$/, "") || "/"),
    getSourceFile(path, languageVersion) {
      const text = texts.get(path);
      if (text !== undefined) return ts.createSourceFile(path, text, languageVersion);
    },
    getDefaultLibFileName: () => "/lib/lib.es2022.d.ts", getCurrentDirectory: () => "/",
    getDirectories: () => [], getCanonicalFileName: path => path, useCaseSensitiveFileNames: () => true,
    getNewLine: () => "\n", writeFile() { throw new Error("类型检查不生成文件"); }
  };
  const program = ts.createProgram(roots.map(root => "/" + root), options, host);
  const errors = ts.getPreEmitDiagnostics(program);
  if (errors.length) {
    throw new Error(errors.slice(0, 12).map(error => {
      let location = "";
      if (error.file && error.start !== undefined) {
        const pos = error.file.getLineAndCharacterOfPosition(error.start);
        location = error.file.fileName.slice(1) + ":" + (pos.line + 1) + ":" + (pos.character + 1) + " ";
      }
      return location + "TS" + error.code + " " + ts.flattenDiagnosticMessageText(error.messageText, "\n");
    }).join("\n"));
  }
}

function resolver(files, versions, declared) {
  return {
    name: "void-project",
    setup(build) {
      build.onResolve({ filter: /.*/ }, args => {
        const specifier = args.path;
        if (args.kind === "entry-point") return { path: specifier, namespace: "project" };
        if (builtins.has(specifier)) {
          const pkg = specifier.startsWith("react-dom/") ? "react-dom" : specifier.split("/jsx-runtime")[0];
          if (declared[pkg] !== versions[pkg]) throw new Error("app/package.json 缺少匹配的依赖 " + pkg + "@" + versions[pkg]);
          return { path: specifier, namespace: "host-library" };
        }
        let path;
        if (specifier.startsWith(".") || specifier.startsWith("/")) {
          path = relative(args.importer, specifier);
        } else {
          const parts = specifier.split("/");
          const pkg = parts.splice(0, specifier.startsWith("@") ? 2 : 1).join("/");
          const base = "modules/" + pkg + "/";
          if (!declared[pkg] || !Object.hasOwn(files, base + "package.json")) {
            throw new Error("无法解析依赖 " + specifier + "，由 " + args.importer + " 引入");
          }
          const meta = JSON.parse(decoder.decode(files[base + "package.json"]));
          if (meta.version !== declared[pkg]) throw new Error("本地依赖版本不匹配 " + pkg);
          path = relative(base + "package.json", parts.join("/") || meta.module || meta.main || "index");
          if (!path.startsWith(base)) throw new Error("依赖入口超出模块目录 " + pkg);
        }
        const found = findModule(files, path);
        if (!found || !/^(app|assets|modules)\//.test(found)) throw new Error("找不到模块 " + specifier + "，由 " + args.importer + " 引入");
        if (found.endsWith(".node")) throw new Error("设备不支持 Node 原生扩展 " + found);
        return { path: found, namespace: "project" };
      });
      build.onLoad({ filter: /.*/, namespace: "host-library" }, ({ path }) => ({
        contents: "module.exports = globalThis.__voidLibraries[" + JSON.stringify(path) + "]"
      }));
      build.onLoad({ filter: /.*/, namespace: "project" }, ({ path }) => ({
        contents: files[path], loader: loaders[path.split(".").pop()] || "file"
      }));
    }
  };
}

function htmlEntries(html, path, entries) {
  const document = parse(html);
  function visit(node) {
    const attr = key => node.attrs?.find(item => item.name === key);
    const link = node.tagName === "script" ? attr("src") :
      node.tagName === "link" && attr("rel")?.value === "stylesheet" ? attr("href") : null;
    if (link && !/^[\w+.-]+:|^\/\//.test(link.value)) {
      const file = relative(path, link.value.split(/[?#]/)[0]);
      const css = node.tagName === "link";
      const out = "bundle/entry-" + entries.length;
      entries.push({ in: file, out });
      const depth = path.split("/").length - 2;
      link.value = "../".repeat(depth) + out + (css ? ".css" : ".js");
    }
    for (const child of node.childNodes || []) visit(child);
  }
  visit(document);
  return serialize(document);
}

// 桌面测试与 IPA 中的构建会话调用同一入口。输入只包含获准发布的源码快照。
export async function compileProject(esbuild, input, declarations, versions) {
  const { files, entry, mode } = input;
  const path = "app/" + entry;
  if (!Object.hasOwn(files, path)) throw new Error("入口不存在 " + path);
  const pkg = files["app/package.json"] ? JSON.parse(decoder.decode(files["app/package.json"])) : {};
  const declared = pkg.dependencies || {};
  for (const [name, version] of Object.entries(declared)) {
    if (versions[name] === version) continue;
    const local = files["modules/" + name + "/package.json"];
    if (!local || JSON.parse(decoder.decode(local)).version !== version) throw new Error("app/package.json 缺少锁定依赖 " + name + "@" + version);
  }
  const published = Object.create(null);
  const entries = [];
  if (mode === "native") {
    entries.push({ in: path, out: "bundle/main" });
    published["index.html"] = encoder.encode('<!doctype html><meta charset="utf-8"><script src="_void/libraries.js"></script><script defer src="bundle/main.js"></script>');
  } else {
    for (const [name, bytes] of Object.entries(files)) {
      if (name.startsWith("assets/")) published[name] = bytes;
      if (!name.startsWith("app/") || /\.(?:tsx?|jsx|json|map)$/i.test(name)) continue;
      const target = name.slice(4);
      if (target.startsWith("_void/") || target.startsWith("bundle/")) throw new Error("项目使用了宿主保留的资源路径 " + name);
      if (/\.html?$/i.test(target)) {
        const html = htmlEntries(decoder.decode(bytes), name, entries);
        const libraryPath = "../".repeat(target.split("/").length - 1) + "_void/libraries.js";
        published[target] = encoder.encode(html.replace("<head>", '<head><script src="' + libraryPath + '"></script>'));
      } else {
        published[target] = bytes;
      }
    }
  }
  typecheck(files, declarations, Object.keys(files).filter(name => /^app\/.*\.(?:ts|tsx)$/.test(name)));
  if (entries.length) {
    const result = await esbuild.build({
      entryPoints: entries, bundle: true, write: false, outdir: "void-output",
      assetNames: "bundle/assets/[name]-[hash]", jsx: "automatic", target: "safari17",
      format: "iife", sourcemap: "linked", metafile: true, logLevel: "silent",
      plugins: [resolver(files, versions, declared)]
    });
    for (const file of result.outputFiles) {
      const path = file.path.replaceAll("\\", "/").split("/void-output/").at(-1);
      published[path] = file.contents;
    }
  }
  return { entry: mode === "native" ? "index.html" : entry, files: published };
}
