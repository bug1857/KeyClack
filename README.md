# KeyClack — Free Mechanical Keyboard Simulator for macOS

A free, ultra-low-latency (<3 ms), zero-dependency native Swift menu bar app that turns your MacBook keyboard into a satisfying mechanical keyboard — inspired by Klack.

## Features

- **6 Physically Modeled Built-In Switches** (works out of the box with zero downloads):
  - **Holy Panda** — rounded tactile bump + deep PBT thock
  - **Oil King** — butter-smooth lubed linear + creamy marbly PE-foam pop
  - **Cherry MX Blue** — crisp click-jacket snap + bright ABS clack
  - **Kailh Box Jade** — thick clickbar with dual snap on both press & release
  - **Topre 45g** — velvety electro-capacitive rubber-dome thock
  - **IBM Model M** — classic buckling spring with subtle damped metallic ping
- **Klack-Style Acoustic Realism**:
  - Separate **Key-Down** (bottom-out) and **Key-Up** (top-out housing return) sounds
  - Distinct acoustics for **Spacebar** (6.25u hollow + stabilizer micro-doublet), **Enter**, **Backspace**, **Shift**, and **Modifiers** (left & right tracked independently)
  - **Spatial Stereo Panning + Haas ITD** mapped to the physical MacBook keyboard layout (left keys sound left, right keys sound right)
  - **6× Round-Robin Variations + Organic Humanization** (subtle pitch & velocity variation so fast typing never sounds robotic)
  - **Key-Repeat Suppression**, **Sleep/Wake Recovery**, and **Seamless Speaker ↔ AirPods Switching**
- **Custom & Mechvibes Sound Pack Importer**:
  - Imports **Mechvibes V1** (`single` & `multi`), **MechvibesDX V2** (including dual down + up slices), **`.zip` archives**, and **plain `.wav` / `.mp3` / `.m4a` / `.flac` / `.aiff` folders**
  - Auto-converts `.ogg` Mechvibes packs on import if `ffmpeg` is installed (`brew install ffmpeg`)
- **Smart Mute & Menu Bar Workflow**:
  - **Auto-Mute When Mic Is Active** (CoreAudio HAL detects Zoom, Meet, FaceTime, Discord, or Dictation without asking for Microphone permission)
  - **Per-App Auto-Mute**, **Global Mute Shortcut** (`⌃⌥⌘K`), and **Launch at Login**

---

## Install on Your MacBook (macOS 13+)

### Option 1: Download Pre-Built App (Fastest — No Dev Tools Needed)

1. Go to [**Releases**](https://github.com/bug1857/KeyClack/releases/latest) and download **`KeyClack-macOS.zip`** (Universal binary for Apple Silicon & Intel).
2. Unzip it and drag **`KeyClack.app`** into **`/Applications`**.
3. Since KeyClack is free & ad-hoc signed (not App Store notarized), clear macOS's browser download flag once in Terminal and launch:
   ```bash
   xattr -cr /Applications/KeyClack.app && open /Applications/KeyClack.app
   ```

### Option 2: Build Locally from Source (Zero Quarantine Prompt)

Only requires Apple's free Command Line Tools (full Xcode is **not** needed):

```bash
xcode-select --install   # skip if already installed
git clone https://github.com/bug1857/KeyClack.git
cd KeyClack
./build-app.sh --install
```

---

## First-Time Permission Setup (10 Seconds)

macOS protects keystrokes so no app can hear typing in other apps without your explicit approval:

1. Click the **keyboard icon** in your menu bar and click **Grant Permission in System Settings**.
2. In **System Settings → Privacy & Security → Input Monitoring**, toggle **KeyClack** ON (click **Quit & Reopen** if prompted).
3. You'll see **`● Live`** in green — start typing anywhere!

> **Privacy:** KeyClack uses a read-only `CGEventTap (.listenOnly)` strictly for physical key-code timing. It never logs characters, never sees password fields (macOS automatically hides Secure Input), and makes zero network connections.

---

## Importing Real Recorded Sound Packs (Mechvibes)

1. Download any Mechvibes V1 or V2 sound pack (`.zip` or folder containing `config.json` + audio).
2. Click the KeyClack menu bar icon → **Switches** → **Import Pack…**
3. Select the `.zip`, folder, or `config.json`. KeyClack normalizes and caches it in `~/Library/Application Support/KeyClack/ImportedPacks/`.
4. If a pack uses `.ogg` audio, install `ffmpeg` once (`brew install ffmpeg`) and re-import.

## Troubleshooting

- **Keys went silent after updating/rebuilding?** Because ad-hoc builds have a new binary hash on each compile, reset macOS's cached permission once and re-enable it:
  ```bash
  tccutil reset ListenEvent com.keyclack.app && killall KeyClack; open /Applications/KeyClack.app
  ```
- **Top pill says `Call Mute`?** Your microphone is currently active in a call or voice app. You can toggle this behavior under the **Smart Mute** tab.
