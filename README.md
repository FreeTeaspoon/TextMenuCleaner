# Text Menu Cleaner

A KernelSU/Magisk module that hides Xiaomi's own actions from the HyperOS text selection toolbar: Search, Translate, Ask, the AI rewrite pen, and Frequent phrases. Pick which ones to hide from a Miuix-styled page inside the root manager. Google Translate, ChatGPT, sharing, and the normal cut/copy/paste items are untouched.

Compatible with the verified Miuix Editor APK from Redmi K90, Android 17, Miuix Editor 17 (version code 37). Firmware updates keep working when that APK is unchanged, including HyperOS `OS4.0.0.31.XPKCNXM` to `OS4.0.0.32.XPKCNXM`. Compatibility is checked by the exact APK hash, not its version label. See [Other firmware](#other-firmware) if the editor itself changes.

## Install

1. Build `dist/TextMenuCleaner-Global-1.4.zip` using the instructions below.
2. Flash it in KernelSU, Magisk, or APatch and reboot.
3. Tap Open on the module card. Toggle the actions you want gone. Changes apply within a second.
4. Restart any app that was already open. Its toolbar still holds the old editor until then.

The module patches the shared editor once after boot and bind-mounts it into zygote. Every app started after that point gets the patched toolbar. There is no per-app list.

## Rollback

Disable the module in the root manager and reboot. Nothing on `/product` was modified, so there is nothing to restore.

For an immediate rollback over ADB without a reboot:

```sh
adb shell su -c 'sh /data/adb/modules/text_menu_cleaner_global/rollback.sh'
```

This disables the module and unmounts the patched editor from every namespace it can reach. Apps that already loaded the patched code keep it until you restart them.

## What it covers

Any app process forked from zygote after the module activates, provided the app loads the editor from `/product/app/MiuixEditor/MiuixEditor.apk` through the inherited mount. That is the normal case.

Not covered:

- Processes that were already running when the module activated (restart them).
- Apps that draw their own selection menu instead of using Xiaomi's toolbar.
- Apps that bundle their own editor copy or that tear down inherited root mounts.
- Third-party text actions like Google Translate. Those are separate from Xiaomi's and this module leaves them alone.

## How it works

Xiaomi implements each toolbar action as a class in `miuix.textaction` inside the editor APK: `Query` (Search), `Translate`, `AskHyperXiaoai`, `AiRecognition` (the AI pen), and `Phrases`. Each class has an `onInvalidated()` method whose only job is to add its own menu item. Replacing that method body with `return-void` removes the item. `TextActionManager.verifyMenuItem()` already tolerates a null item, so nothing else needs to change.

The module never ships Xiaomi's code. After boot, `apply.sh`:

1. Checks the editor path reported by Package Manager, and the SHA-256 of the stock APK as seen from init's mount namespace. Any mismatch logs `SKIPPED` and stops.
2. Copies the stock APK out of init's namespace into the module directory.
3. Runs `payload/patcher.jar` through `app_process`. It rewrites only the `onInvalidated()` bodies selected in `menu.conf`, at byte offsets from `payload/offsets.txt`, then fixes up the DEX checksum and signature and the zip CRC. The rest of the APK stays byte-for-byte identical.
4. Bind-mounts the result over the stock path inside each zygote namespace, and verifies the hash it sees afterwards.

Modifying the DEX invalidates Xiaomi's APK signature, which is why the mount waits until after boot and only targets zygote. Init, system_server, and Package Manager keep seeing the signed stock file, including during package scans. There is no signature bypass and no SELinux change.

The Open page is a Vite/Vue app using `miuix-vue`, served from `webroot/` the same way Magic Mount does it. It calls `webui.sh status|apply` through the KernelSU WebUI bridge, and `apply` reruns `apply.sh` in place.

## Build

Requirements: Python 3, JDK 17, Node.js, and Android build-tools 37.0.0 with `ANDROID_SDK_ROOT` pointing at the SDK.

```sh
adb pull /product/app/MiuixEditor/MiuixEditor.apk /tmp/MiuixEditor-original.apk
bash build.sh /tmp/MiuixEditor-original.apk
```

The stock APK is only used as a check. `build.sh` patches it twice, once with `patch_editor.py` (the reference implementation, which parses the DEX properly) and once with the on-device `MenuPatcher.java` (which uses the precomputed offsets), and fails if the two DEX files differ. The APK is not packed into the zip.

`bash build.sh --pack` skips that check and just compiles the patcher, builds the WebUI, and writes `dist/TextMenuCleaner-Global-1.4.zip`.

`EditorProbe.java` is a runtime check for use on the device. It loads the original and patched editors with a `PathClassLoader` and calls each `onInvalidated()` without an attached editor. The originals throw `NullPointerException`; the patched ones return. It also confirms the remaining action classes still load.

## Other firmware

A firmware update needs no module update when the editor APK and path stay unchanged. If Xiaomi updates the editor APK, the hash check will fail and the module will stay inactive. This protects the fixed byte offsets from being applied to different code. Do not loosen the hash check. Pull the new APK and run `patch_editor.py` on it. It asserts the five target classes still exist and writes a `.patch.json` with the new code offset and instruction size for each. Copy those into `module/payload/offsets.txt`, update `STOCK_SHA` in `module/config.sh`, then rebuild. `build.sh` will fail if the Java patcher and the Python reference disagree.

## Tested on

Redmi K90, HyperOS `OS4.0.0.31.XPKCNXM` and `OS4.0.0.32.XPKCNXM`, KernelSU.

Version 1.4 was applied over ADB on `.32` without rebooting. The module reported `ACTIVE`, all five patched actions passed `EditorProbe`, and namespace hashes confirmed that zygote saw the patched APK while init and system_server still saw stock. The `.31` UI checks below have not been repeated on `.32`.

- `boot-completed.sh` logged `ACTIVE` after boot. Zygote saw the patched APK; init and Package Manager still saw stock hash `16cd2f07…`.
- Chrome's omnibox toolbar showed Select all, Cut, Copy, Share, with Google Translate and Ask ChatGPT in the overflow. Xiaomi's Search, Translate, Ask, AI pen, and Frequent phrases were gone.
- Settings, started after activation, no longer offered Frequent phrases in its search field.
- Apps with custom selection menus were unchanged.

No Xiaomi firmware, decompiled or otherwise, is included in this repository.
