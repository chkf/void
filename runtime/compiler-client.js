// The document remains responsive while type checking and WebAssembly run in the worker.
let activeBuild;

globalThis.cancelVoidBuild = () => {
  activeBuild?.cancel();
};

globalThis.buildProject = input => new Promise((resolve, reject) => {
  globalThis.cancelVoidBuild();
  const worker = new Worker("compiler.js");
  let finished = false;
  function finish(callback, value) {
    if (finished) return;
    finished = true;
    worker.terminate();
    activeBuild = undefined;
    callback(value);
  }
  activeBuild = { cancel: () => finish(reject, new Error("已取消编译")) };
  worker.onmessage = event => finish(resolve, event.data);
  worker.onerror = event => finish(reject, new Error(event.message || "编译工作线程已退出"));
  worker.postMessage(input);
});
