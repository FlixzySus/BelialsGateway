local gui = {}
local logic = require("core.logic")

local plugin_label = "Belial's Gateway"

-- GUI elements
gui.elements = {}
gui.root = tree_node:new(0)
gui.subtree_settings = tree_node:new(1)

local developer_id = "Bunny"
local initialized = false

-- Initialize GUI elements
function gui.initialize(dev_id)
    developer_id = dev_id or "Bunny"
    
    -- Initialize GUI elements with unique IDs
    gui.elements.main_toggle = checkbox:new(false, get_hash(developer_id .. "main_toggle"))
    gui.elements.auto_retry = checkbox:new(true, get_hash(developer_id .. "auto_retry"))
    gui.elements.debug_mode = checkbox:new(false, get_hash(developer_id .. "debug_mode"))
    
    initialized = true
end

-- Ensure initialization before any GUI operations
local function ensure_initialized()
    if not initialized then
        gui.initialize()
    end
end

-- Check BossTosser status
local function get_bosstosser_status()
    -- Try multiple ways to check BossTosser status
    local success, result = pcall(function()
        if _G.BosserPlugin and _G.BosserPlugin.status then
            local status = _G.BosserPlugin.status()
            return status.enabled or false
        end
        -- Try GUI method
        if _G.gui and _G.gui.elements and _G.gui.elements.main_toggle then
            return _G.gui.elements.main_toggle:get()
        end
        return false
    end)
    
    if success then
        return result
    else
        return false
    end
end

-- Auto-toggle controls when approaching altar
function gui.auto_toggle_controls()
    -- Disable Enable Script toggle
    if gui.elements.main_toggle then
        gui.elements.main_toggle:set(false)
    end
end

-- Auto-disable both toggles when called by logic
function gui.auto_disable_toggles()
    if gui.elements.main_toggle then
        gui.elements.main_toggle:set(false)
    end
end

-- Render the menu
function gui.on_render_menu()
    -- Ensure GUI is initialized before rendering
    ensure_initialized()
    
    if not gui.root or not gui.elements.main_toggle then
        return
    end
    
    -- Main tree node containing everything
    if gui.root:push(plugin_label) then
        
        -- Main toggle inside the tree
        gui.elements.main_toggle:render("Enable Script", "Auto walks to Belial alter room then enables Bosser")
        
        -- Show BossTosser status if it's available
        local bosstosser_status = get_bosstosser_status()
        if bosstosser_status then
            -- Use a different color to show BossTosser is active
            graphics.text_2d("BossTosser Status: ENABLED", vec2.new(10, 100), 12, color_green(255))
        else
            graphics.text_2d("BossTosser Status: DISABLED", vec2.new(10, 100), 12, color_orange(255))
        end
        
        -- Settings subtree
        if gui.subtree_settings:push("Settings") then
            gui.elements.auto_retry:render("Auto Retry Teleport", "Automatically retry teleport if not in correct zone")
            gui.elements.debug_mode:render("Debug Mode", "Show debug information and waypoints on screen")
            gui.subtree_settings:pop()
        end
        
        gui.root:pop()
    end
    
    -- Handle toggle changes (process outside the tree check to ensure they always work)
    local is_enabled = gui.elements.main_toggle:get()
    local debug_enabled = gui.elements.debug_mode:get()
    local auto_retry_enabled = gui.elements.auto_retry:get()
    
    -- Update logic with settings
    logic.set_enabled(is_enabled)
    logic.set_debug_mode(debug_enabled)
    logic.set_auto_retry(auto_retry_enabled)
end

-- Get menu state
function gui.is_enabled()
    ensure_initialized()
    if gui.elements.main_toggle then
        return gui.elements.main_toggle:get()
    end
    return false
end

function gui.is_debug_enabled()
    ensure_initialized()
    if gui.elements.debug_mode then
        return gui.elements.debug_mode:get()
    end
    return false
end

function gui.should_enable_bosstosser()
    -- Always return true since we removed the toggle but still want BossTosser to activate
    return true
end

function gui.show_status_enabled()
    -- Only show detailed status if debug mode is enabled
    return gui.is_debug_enabled()
end

-- Render status on screen (only if debug mode is enabled)
function gui.on_render()
    if not gui.show_status_enabled() then
        return
    end
    
    local status = logic.get_status()
    
    -- Display status on screen
    local screen_pos = vec2.new(10, 50)
    graphics.text_2d("=== Belial's Gateway Debug ===", screen_pos, 14, color_white(255))
    
    screen_pos.y = screen_pos.y + 20
    
    -- Script status
    graphics.text_2d("  State: " .. (status.state or "Unknown"), screen_pos, 14, color_yellow(255))
    screen_pos.y = screen_pos.y + 18
    graphics.text_2d("  Step: " .. (status.current_step or "Unknown"), screen_pos, 14, color_green(255))
    screen_pos.y = screen_pos.y + 18
    
    -- Show current waypoint progress
    if status.current_waypoint and status.current_waypoint > 0 then
        graphics.text_2d("  Progress: " .. status.current_waypoint .. "/" .. status.total_waypoints, screen_pos, 14, color_white(255))
        screen_pos.y = screen_pos.y + 18
    end
    
    -- Show distance to start if available
    if status.distance_to_start and status.distance_to_start < math.huge then
        local distance_color = status.distance_to_start <= 20.0 and color_green(255) or color_orange(255)
        graphics.text_2d("  Distance to Start: " .. string.format("%.1f", status.distance_to_start) .. "m", screen_pos, 14, distance_color)
        screen_pos.y = screen_pos.y + 18
    end
    
    -- Show teleport attempts if applicable
    if status.teleport_attempts and status.teleport_attempts > 0 then
        graphics.text_2d("  Teleport Attempts: " .. status.teleport_attempts .. "/" .. status.max_teleport_attempts, screen_pos, 14, color_orange(255))
        screen_pos.y = screen_pos.y + 18
    end
    
    -- Show pathwalker status
    if status.pathwalker_status and status.pathwalker_status ~= "" then
        graphics.text_2d("  Pathwalker: " .. status.pathwalker_status, screen_pos, 14, color_cyan(255))
        screen_pos.y = screen_pos.y + 18
    end
    
    -- Show portal search info when looking for portal
    if status.state == "Looking for Belial portal" then
        graphics.text_2d("  Searching for Portal_Dungeon_Generic...", screen_pos, 14, color_purple(255))
        screen_pos.y = screen_pos.y + 18
    end
    
    -- Show BossTosser status if relevant
    if status.bosstosser_status then
        local bosstosser_color = status.bosstosser_status == "Enabled" and color_green(255) or color_orange(255)
        graphics.text_2d("  BossTosser: " .. status.bosstosser_status, screen_pos, 14, bosstosser_color)
        screen_pos.y = screen_pos.y + 18
    end
    
    -- Show BossTosser integration setting
    local integration_status = gui.should_enable_bosstosser() and "Will Enable" or "Disabled"
    local integration_color = gui.should_enable_bosstosser() and color_green(255) or color_red(255)
    graphics.text_2d("  BossTosser Integration: " .. integration_status, screen_pos, 14, integration_color)
    screen_pos.y = screen_pos.y + 18
    
    screen_pos.y = screen_pos.y + 10
    if status.is_active then
        graphics.text_2d("  STATUS: ACTIVE", screen_pos, 14, color_green(255))
    else
        graphics.text_2d("  STATUS: INACTIVE", screen_pos, 14, color_orange(255))
    end
    
    -- Show error if any
    if status.last_error and status.last_error ~= "" then
        screen_pos.y = screen_pos.y + 20
        graphics.text_2d("  ERROR: " .. status.last_error, screen_pos, 12, color_red(255))
    end
end

return gui