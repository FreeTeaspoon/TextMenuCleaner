import { createApp } from "vue";
import { setThemeMode } from "miuix-vue";
import { enableEdgeToEdge } from "kernelsu";
import App from "./App.vue";
import "./style.css";

try {
  enableEdgeToEdge(true);
} catch (_) {}
setThemeMode("system");
createApp(App).mount("#app");

setThemeMode("system");
createApp(App).mount("#app");
