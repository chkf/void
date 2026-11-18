import * as React from "react";
import * as jsx from "react/jsx-runtime";
import * as ReactDOM from "react-dom";
import * as client from "react-dom/client";
import * as ui from "./ui.js";
import { ios } from "./bridge.js";

globalThis.__voidLibraries = {
  react: React, "react/jsx-runtime": jsx, "react-dom": ReactDOM,
  "react-dom/client": client, "@runtime/ui": ui, "@runtime/sdk": { ios }
};
