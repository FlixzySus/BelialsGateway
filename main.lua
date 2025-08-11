local developer_id = "belials_gateway"

-- Load required modules
local gui = require("gui")
local logic = require("core.logic")
local explorer = require("core.explorer")
local tarsarak_points = require("paths.TarsarakToBelial")
local altar_points = require("paths.ToAlter")

-- Initialize the system
local function initialize()
    console.print("=== Belial's Gateway Loaded ===")
    console.print("Author: Bunny")
    console.print("Version: Beta - 1.0")
    console.print("Description: Auto teleport to Tarsarak, path to Belial Lair, path to Altar Room, then enable Bosser")
    console.print("Integration: Automatically enables Bosser script after completing ToAlter path")
    console.print("===============================")
    
    -- Initialize logic with both waypoint sets
    logic.initialize(tarsarak_points, altar_points)
    
    -- Initialize GUI
    gui.initialize(developer_id)
    
    console.print("Script initialized successfully!")
end

-- Register callbacks
on_update(function()
    logic.on_update()
end)

on_render(function()
    logic.on_render()
    gui.on_render()
end)

on_render_menu(function()
    gui.on_render_menu()
end)

-- Initialize the script
initialize()