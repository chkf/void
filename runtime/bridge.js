import catalog from "./sdk-api.json";

export async function request(method, params, options = {}) {
  const id = crypto.randomUUID();
  const transport = globalThis.webkit?.messageHandlers?.voidRPC;
  if (!transport) {
    return { success: false, error: { code: "NO_SESSION", message: "需要打开 void 项目会话" } };
  }
  const cancelled = () => ({ success: false, error: { code: "CANCELLED", message: "请求已取消" } });
  if (options.signal?.aborted) return cancelled();
  let timer;
  let cancel;
  try {
    const interrupt = new Promise(resolve => {
      const stop = result => {
        void Promise.resolve(transport.postMessage({version: 1, id: crypto.randomUUID(), method: "sdk.cancel", params: { id }})).catch(() => {});
        resolve({ id, result });
      };
      cancel = () => stop(cancelled());
      options.signal?.addEventListener("abort", cancel, { once: true });
      if (options.timeoutMs > 0) timer = setTimeout(() => stop({success: false, error: {code:"TIMEOUT", message:"请求超时"}}), options.timeoutMs);
    });
    const response = await Promise.race([transport.postMessage({ version: 1, id, method, params }), interrupt]);
    if (response.id !== id) throw new Error("请求标识不匹配");
    return response.result;
  } catch (error) {
    return { success: false, error: { code: "SESSION_CLOSED", message: String(error) } };
  } finally {
    if (timer !== undefined) clearTimeout(timer);
    options.signal?.removeEventListener("abort", cancel);
  }
}

const listeners = new Set();
globalThis.__voidNativeEvent = event => {
  for (const listener of [...listeners]) listener(event);
};

export const ios = Object.fromEntries(Object.entries(catalog).map(([group, methods]) => [
  group, Object.fromEntries(Object.keys(methods).map(method => [
    method, (params = {}, options) => request(group + "." + method, params, options)
  ]))
]));
ios.version = "1.1.0";
ios.onEvent = listener => { listeners.add(listener); return () => listeners.delete(listener); };
ios.stop = id => request("sdk.stop", { id });

const nativeCapabilities = ios.graphics.capabilities;
ios.graphics.capabilities = async (params, options) => {
  const result = await nativeCapabilities(params, options);
  if (!result.success) return result;
  const canvas = () => globalThis.document?.createElement("canvas");
  const gl = canvas()?.getContext("webgl2") ?? canvas()?.getContext("webgl");
  const webgl2 = !!gl && typeof WebGL2RenderingContext !== "undefined" && gl instanceof WebGL2RenderingContext;
  const webgl = !!gl;
  gl?.getExtension("WEBGL_lose_context")?.loseContext();
  return { success: true, data: { ...result.data, canvas2D: !!canvas()?.getContext("2d"), webgl, webgl2,
    wasm: typeof WebAssembly === "object", animation: typeof globalThis.Element?.prototype.animate === "function" } };
};
let displayedCanvas;
ios.graphics.showCanvas = async (canvas, height = 240) => {
  if (!(canvas instanceof HTMLCanvasElement)) return {success:false,error:{code:"INVALID_PARAMS",message:"需要 HTMLCanvasElement"}};
  const result = await request("graphics.showCanvas", { height });
  if (result.success) {
    if (displayedCanvas !== canvas) displayedCanvas?.remove();
    displayedCanvas = canvas;
    canvas.style.cssText = "display:block;width:100%;height:100%;object-fit:contain";
    document.body.style.margin = "0";
    document.body.append(canvas);
  }
  return result;
};
ios.graphics.hideCanvas = async () => {
  const result = await request("graphics.hideCanvas", {});
  if (result.success) { displayedCanvas?.remove(); displayedCanvas = undefined; }
  return result;
};
