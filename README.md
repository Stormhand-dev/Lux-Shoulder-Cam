# LuxShoulderCam

**LuxShoulderCam** is a WoW 3.3.5a (build 12340) mod that adds a real-time over-the-shoulder camera offset — height and horizontal position — controlled via an in-game panel and keybindings.

> Drop `LuxShoulderCam.dll` into your WoW root folder (loaded automatically by [Lexara](https://github.com/Stormhand-dev/Lexara---HD-Font-Renderer-for-WoW-3.3.5) and install the addon. No configuration file needed — settings are saved per character.

![WoW 3.3.5](https://img.shields.io/badge/WoW-3.3.5a%20%2812340%29-blue)
![Version](https://img.shields.io/badge/version-1.0-brightgreen)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

---

## Features

- **Height offset** — raise or lower the camera above/below the default position
- **Horizontal offset** — shift the camera left or right (true over-the-shoulder, tracks player rotation)
- **Instant restore** — camera position is restored from the first rendered frame on login, with no visible delay
- **Per-character settings** — each character has independent saved values
- **In-game panel** — open with `/lsc`, drag anywhere on screen
- **Keybindings** — fully configurable in the WoW Key Bindings menu under *LuxShoulderCam*

---

## Requirements

- World of Warcraft **3.3.5a (build 12340)**
- [Lexara](https://github.com/Stormhand-dev/Lexara---HD-Font-Renderer-for-WoW-3.3.5) — HD font renderer that also acts as the DLL loader

---

## Installation

1. Copy `LuxShoulderCam.dll` to your WoW root folder (where `WoW.exe` is located)
2. Copy the `LuxShoulderCam/` addon folder to `Interface\AddOns\`
3. Launch the game — the DLL loads automatically via Lexara

**Files required in WoW root:**
```
WoW.exe
dinput8.dll          ← Lexara
LuxShoulderCam.dll   ← this mod
```

**Files required in Interface\AddOns\:**
```
LuxShoulderCam/
  LuxShoulderCam.lua
  LuxShoulderCam.xml
  LuxShoulderCam.toc
  Bindings.xml
```

---

## Usage

| Command | Description |
|---|---|
| `/lsc` | Open / close the panel |
| `/lsc reset` | Reset camera to default position |
| `/lsc reload` | Re-apply saved values manually |
| `/lsc status` | Print DLL status to chat |

Keybindings are available in **Key Bindings → LuxShoulderCam** for all actions (raise, lower, move right, move left, reset, toggle panel).

---

## Limits

| Axis | Min | Max |
|---|---|---|
| Height (vertical) | -1.0 | +1.0 |
| Horizontal | -2.0 | +2.0 |

Values are in WoW internal units (yards). Going beyond these limits causes visual clipping.

---

## Compatibility

- Coexists with ReShade, OBS, and RivaTuner (BeginScene hook uses MinHook with retry logic)
- Designed for **private servers** — use on official Blizzard servers violates ToS

---

## Credits

- Camera patch technique ported from [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3) by Konaka
- Hook library: [MinHook 1.3.4](https://github.com/TsudaKageyu/minhook) by Tsuda Kageyu (MIT)

---

## Author

**Stormhand**
