# KeyClack — Free Native Mechanical Keyboard Simulator for macOS

A lightweight, ultra-low-latency (<3 ms), zero-dependency native Swift menu bar app that transforms your MacBook keyboard into a satisfying mechanical keyboard — inspired by Klack, completely free and open to tweak.

## Features

- **6 Physically Modeled Built-In Switches** (works immediately with zero downloads):
  - **Holy Panda** — rounded tactile bump + deep PBT thock
  - **Oil King** — butter-smooth lubed linear + creamy marbly PE-foam pop
  - **Cherry MX Blue** — crisp click-jacket snap + bright ABS clack
  - **Kailh Box Jade** — thick clickbar with dual snap on both press & release
  - **Topre 45g** — velvety electro-capacitive rubber-dome thock
  - **IBM Model M** — classic buckling spring with subtle damped metallic ping
- **Klack-Style Acoustic Realism**:
  - Separate **Key-Down** (bottom-out) and **Key-Up** (top-out housing return) audio
  - Distinct acoustic physics for **Spacebar** (6.25u hollow + stabilizer micro-doublet), **Enter**, **Backspace**, **Shift**, and **Modifiers** (left & right tracked independently)
  - **Spatial Stereo Panning + Haas ITD** mapped to the physical MacBook keyboard layout (left keys sound left, right keys sound right)
  - **6× Round-Robin Variations + Organic Micro-Variation** (per-stroke pitch & velocity jitter) so fast typing never sounds robotic
  - **Key-Repeat Suppression** (holding a key down won't spam clicks)
  - **Seamless Output Switching** (automatically survives plugging in headphones or switching to AirPods)
- **Custom & Mechvibes Sound Pack Importer**:
  - Imports **Mechvibes V1** (`defines`, `single` and `multi`), **MechvibesDX V2** (`definitions`, including dual down + up slices!), **`.zip` archives**, and **plain folders of `.wav` / `.mp3` / `.m4a` / `.flac` / `.aiff` files**
  - Auto-converts `.ogg` Mechvibes packs on import if `ffmpeg` is installed (`brew install ffmpeg`)
- **Smart Mute & Workflow**:
  - **Auto-Mute When Mic Is Active** (CoreAudio HAL listener detects Zoom, Google Meet, FaceTime, Discord, or Dictation without asking for Microphone permission)
  - **Per-App Auto-Mute** (silence automatically when chosen apps are frontmost)
  - **Global Mute Shortcut** (`⌃⌥⌘K` default, customizable presets)
  - **Launch at Login** (`SMAppService`) & pure menu-bar mode (no Dock icon)

## Quick Start on Your MacBook

Requires **macOS 13 (Ventura) or newer** and Apple's free Command Line Tools (full Xcode is not required):

```bash
# 1. If you don't already have Swift / Command Line Tools:
xcode-select --install

# 2. Build KeyClack.app, install to /Applications, and launch it:
cd KeyClack
./build-app.sh --install
```

### First-Time Permission Setup (10 seconds)

macOS protects your keystrokes so no app can hear typing in other apps without explicit permission:

1. Click the **keyboard icon** in your menu bar and click **Grant Permission in System Settings**.
2. In **System Settings → Privacy & Security → Input Monitoring**, toggle **KeyClack** ON.
3. KeyClack detects the permission automatically within ~1 second and starts playing immediately!

> **Privacy note:** KeyClack uses a read-only `CGEventTap (.listenOnly)` strictly for physical key-code timing. It never logs characters, never reads passwords (macOS automatically hides Secure Input fields), and makes zero network requests.

## Importing Real Recorded Sound Packs (Mechvibes)

1. Download any community Mechvibes sound pack (`.zip` or folder containing `config.json` + audio).
2. Click the KeyClack menu bar icon → **Import Pack…**
3. Select the `.zip`, folder, or `config.json` — KeyClack normalizes and caches it under `~/Library/Application Support/KeyClack/ImportedPacks/`.
4. If a community pack uses `.ogg` audio instead of `.wav`/`.mp3`/`.flac`, install `ffmpeg` once (`brew install ffmpeg`) and re-import.
