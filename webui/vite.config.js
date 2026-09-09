import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  base: "./",
  build: {
    outDir: "../module/webroot",
    target: "esnext",
    chunkSizeWarningLimit: 1000,
  },
  plugins: [vue()],
});
