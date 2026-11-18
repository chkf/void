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
