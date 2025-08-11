# Belial’s Gateway (Diablo IV — QQT Script)

> Auto‑travel and path walker from **Tarsarak → Belial portal → Altar Room**, with optional explorer assistance and automatic Bosser handoff.

## Overview
Belial’s Gateway is a QQT Lua script that:
1) Teleports your character to **Tarsarak**
2) Walks the path to the **Palace of the Deceiver**
3) Enters the portal and continues the path to the **Alter Room** 
4) Enables Bosser script when the altar is reached

## Folder Structure
Place this folder under your QQT scripts directory:

diablo_qqt/
└─ scripts/
└─ BelialsGateway/
├─ main.lua
├─ gui.lua
├─ core/
│ ├─ logic.lua
│ ├─ explorer.lua
│ ├─ explorer_integration.lua
│ └─ pathwalker.lua
└─ paths/
├─ TarsarakToBelial.lua
└─ ToAlter.lua
