export async function request(method, params) {
  const id = crypto.randomUUID();
  const transport = globalThis.webkit?.messageHandlers?.voidRPC;
  if (!transport) {
    return { success: false, error: { code: "NO_SESSION", message: "需要打开 void 项目会话" } };
  }
  try {
    const response = await transport.postMessage({ version: 1, id, method, params });
    if (response.id !== id) throw new Error("请求标识不匹配");
    return response.result;
  } catch (error) {
    return { success: false, error: { code: "SESSION_CLOSED", message: String(error) } };
  }
}

export const ios = { system: { info: () => request("system.info", {}) } };
