import * as React from "react";
import * as jsx from "react/jsx-runtime";
import * as ReactDOM from "react-dom";
import * as client from "react-dom/client";
import { legacyUI, nativeUI } from "./ui.js";
import { ios } from "./bridge.js";

globalThis.__voidLibraries = {
  react: React, "react/jsx-runtime": jsx, "react-dom": ReactDOM,
  "react-dom/client": client, "@runtime/ui": legacyUI, "@runtime/ui@1.1.0": nativeUI, "@runtime/sdk": { ios }
};
