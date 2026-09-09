<script setup>
import { computed, onMounted, reactive, ref } from "vue";
import {
  MiuixBasicComponent,
  MiuixCard,
  MiuixScrollArea,
  MiuixSmallTitle,
  MiuixSnackbarHost,
  MiuixSwitchPreference,
  MiuixText,
  MiuixTopAppBar,
  showSnackbar,
} from "miuix-vue";
import { exec } from "kernelsu";
import "miuix-vue/style.css";
import "./theme.css";

const MOD = "/data/adb/modules/text_menu_cleaner_global";
const ACTIONS = [
  { key: "search", title: "Search", summary: "Xiaomi Search" },
  { key: "translate", title: "Translate", summary: "Xiaomi Translate. Google Translate stays" },
  { key: "ask", title: "Ask", summary: "Ask Hyper Xiaoai" },
  { key: "ai_rewrite", title: "AI rewrite", summary: "The AI pen" },
  { key: "phrases", title: "Frequent phrases", summary: "Saved phrases" },
];

const flags = reactive({
  search: true,
  translate: true,
  ask: true,
  ai_rewrite: true,
  phrases: true,
});
const applying = ref(false);
const detail = ref("");

const hiddenCount = computed(() => Object.values(flags).filter(Boolean).length);

const statusTitle = computed(() => {
  if (applying.value) return "Applying";
  if (detail.value.startsWith("ACTIVE")) return "Active";
  if (detail.value.startsWith("SKIPPED")) return "Not active";
  return "Not applied yet";
});

const statusSummary = computed(() => {
  const count = `${hiddenCount.value} of ${ACTIONS.length} hidden`;
  if (!applying.value && detail.value.startsWith("SKIPPED")) {
    return `${count}\n${detail.value.replace(/^SKIPPED:\s*/, "")}`;
  }
  return count;
});

function parseKv(text) {
  const out = {};
  for (const line of text.split("\n")) {
    const match = line.trim().match(/^([A-Za-z0-9_]+)=(.*)$/);
    if (match) out[match[1]] = match[2];
  }
  return out;
}

async function loadStatus() {
  const result = await exec(`sh ${MOD}/webui.sh status`);
  if (result.errno !== 0) {
    throw new Error(result.stderr || result.stdout || "status failed");
  }
  const [conf, log] = result.stdout.split("\n---\n");
  const values = parseKv(conf || "");
  for (const key of Object.keys(flags)) {
    flags[key] = values[key] === "1" || String(values[key]).toLowerCase() === "true";
  }
  detail.value = (log || "").trim();
}

// The switch flips at once. apply.sh runs a few hundred ms later, and any
// toggles that land while it is running are folded into one more pass.
let applyTimer = null;
let running = false;
let dirty = false;

function onToggle(key, value) {
  flags[key] = value;
  dirty = true;
  clearTimeout(applyTimer);
  applyTimer = setTimeout(runApply, 350);
}

async function runApply() {
  if (running) return;
  running = true;
  applying.value = true;
  let last = null;
  try {
    while (dirty) {
      dirty = false;
      const args = Object.keys(flags)
        .map((item) => (flags[item] ? "1" : "0"))
        .join(" ");
      last = await exec(`sh ${MOD}/webui.sh apply ${args}`);
    }
    const line = (last.stdout || last.stderr || "").trim().split("\n").pop() || "";
    detail.value = line;
    if (last.errno === 0 && line.startsWith("ACTIVE")) {
      showSnackbar({ message: "Restart open apps to see the change" });
    } else {
      showSnackbar({ message: line.replace(/^SKIPPED:\s*/, "") || "Could not apply" });
      await loadStatus();
    }
  } catch (error) {
    showSnackbar({ message: error.message || "Could not apply" });
    await loadStatus().catch(() => {});
  } finally {
    running = false;
    applying.value = false;
    if (dirty) runApply();
  }
}

onMounted(async () => {
  try {
    await loadStatus();
  } catch (error) {
    detail.value = "";
    showSnackbar({ message: error.message || "Open this page from the root manager" });
  }
});
</script>

<template>
  <div class="app">
    <MiuixScrollArea class="app__body">
      <MiuixTopAppBar large title="Text Menu Cleaner" class="app__top-app-bar" />

      <MiuixCard class="tip">
        <MiuixText type="footnote1" color="var(--m-color-on-surface-variant-summary)">
          Switch an action off to keep it in Xiaomi's text toolbar. Restart open apps after changing.
        </MiuixText>
      </MiuixCard>

      <MiuixSmallTitle text="Status" />
      <MiuixCard class="group">
        <MiuixBasicComponent :title="statusTitle" :summary="statusSummary" />
      </MiuixCard>

      <MiuixSmallTitle text="Hidden actions" />
      <MiuixCard class="group">
        <MiuixSwitchPreference
          v-for="action in ACTIONS"
          :key="action.key"
          :title="action.title"
          :summary="action.summary"
          :model-value="flags[action.key]"
          @update:model-value="onToggle(action.key, $event)"
        />
      </MiuixCard>
    </MiuixScrollArea>
    <MiuixSnackbarHost />
  </div>
</template>

<style>
.app {
  display: flex;
  flex-direction: column;
  height: 100vh;
  background: var(--m-color-surface);
}

.app__body {
  flex: 1;
  min-height: 0;
  overflow: hidden;
  --m-scroll-area-inset-top: 52px;
}

.app__top-app-bar {
  padding-top: var(--top-inset);
}

.tip {
  margin: 12px 12px 6px;
}

.tip .m-text {
  display: block;
  padding: 12px 16px;
  line-height: 1.4;
}

.group {
  margin: 0 12px 6px;
}

.m-basic-component__summary {
  white-space: pre-line;
}
</style>
