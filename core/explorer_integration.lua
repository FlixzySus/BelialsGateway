-- explorer_integration.lua - Modified for Belial's Gateway
-- Integration between the explorer module and path walker

local explorer = require("core.explorer")
local pathwalker = require("core.pathwalker")

local M = {}

-- Integration state
M.auto_explore_enabled = false
M.exploration_active = false
M.last_exploration_check = 0
M.exploration_check_interval = 2.0 -- Check every 2 seconds
M.exploration_assistance_enabled = true -- Enable explorer to assist with pathfinding

-- Function to convert exploration target to a simple path
local function create_exploration_path(target_position)
    local player_pos = get_player_position()
    if not player_pos or not target_position then
        return nil
    end
    
    -- Create a simple 2-point path: current position -> target
    return {player_pos, target_position}
end

-- Check if exploration target is beneficial for current path
local function is_exploration_beneficial(exploration_target, path_waypoints, current_waypoint_index)
    if not exploration_target or not path_waypoints or current_waypoint_index > #path_waypoints then
        return false
    end
    
    local player_pos = get_player_position()
    if not player_pos then
        return false
    end
    
    local current_waypoint = path_waypoints[current_waypoint_index]
    if not current_waypoint then
        return false
    end
    
    -- Check if exploration target is reasonably close to our path direction
    local dist_exploration_to_waypoint = exploration_target:dist_to_ignore_z(current_waypoint)
    local dist_player_to_waypoint = player_pos:dist_to_ignore_z(current_waypoint)
    
    -- Use exploration if it's leading us towards our goal or is a reasonable detour
    return dist_exploration_to_waypoint < (dist_player_to_waypoint + 15.0)
end

-- Auto exploration update function with path assistance
function M.update_exploration_assistance()
    if not M.exploration_assistance_enabled or not pathwalker.is_walking then
        return
    end
    
    local current_time = os.clock()
    if current_time - M.last_exploration_check < M.exploration_check_interval then
        return
    end
    
    M.last_exploration_check = current_time
    
    -- Don't interfere if we're walking to start position
    if pathwalker.walking_to_start then
        return
    end
    
    -- Try to get exploration target
    local has_target = explorer.update_exploration()
    
    if has_target then
        local exploration_target = explorer.current_target()
        if exploration_target then
            -- Check if this exploration target would be beneficial
            local current_wp_index = pathwalker.current_waypoint_index
            local is_beneficial = is_exploration_beneficial(
                exploration_target, 
                pathwalker.current_path, 
                current_wp_index
            )
            
            if is_beneficial then
                -- Temporarily insert exploration target as next waypoint
                local modified_path = {}
                
                -- Copy path up to current position
                for i = 1, current_wp_index - 1 do
                    table.insert(modified_path, pathwalker.current_path[i])
                end
                
                -- Insert exploration target
                table.insert(modified_path, exploration_target)
                
                -- Add remaining waypoints
                for i = current_wp_index, #pathwalker.current_path do
                    table.insert(modified_path, pathwalker.current_path[i])
                end
                
                -- Update pathwalker with modified path
                pathwalker.current_path = modified_path
                pathwalker.current_waypoint_index = current_wp_index
                
                M.exploration_active = true
            end
        end
    end
end

-- Pure auto exploration (when not following a path)
function M.update_auto_exploration()
    if not M.auto_explore_enabled or pathwalker.is_walking then
        return
    end
    
    local current_time = os.clock()
    if current_time - M.last_exploration_check < M.exploration_check_interval then
        return
    end
    
    M.last_exploration_check = current_time
    
    -- Try to get exploration target
    local has_target = explorer.update_exploration()
    
    if has_target then
        local target = explorer.current_target()
        if target then
            -- Create a simple path to the exploration target
            local exploration_path = create_exploration_path(target)
            if exploration_path then
                -- Start pathwalker with exploration path
                pathwalker.current_path = exploration_path
                pathwalker.current_waypoint_index = 2 -- Go to target
                pathwalker.walking_forward = true
                pathwalker.is_walking = true
                pathwalker.is_paused = false
                pathwalker.loop_enabled = false
                pathwalker.walking_to_start = false
                
                M.exploration_active = true
            end
        end
    else
        if M.exploration_active then
            M.exploration_active = false
        end
    end
end

-- Check if we should stop exploration (reached target)
function M.check_exploration_completion()
    if not M.exploration_active then
        return
    end
    
    local player_pos = get_player_position()
    if not player_pos then
        return
    end
    
    -- If we have an exploration target and we're close to it
    local target = explorer.current_target()
    if target and player_pos:dist_to(target) <= pathwalker.path_threshold then
        M.exploration_active = false
        
        -- Small delay before looking for next target
        M.last_exploration_check = os.clock() + 1.0
    end
end

-- Enable/disable auto exploration
function M.set_auto_explore_enabled(enabled)
    M.auto_explore_enabled = enabled
    if not enabled then
        if M.exploration_active and not pathwalker.is_walking then
            pathwalker.stop_walking()
            M.exploration_active = false
        end
    end
end

-- Enable/disable exploration assistance for pathfinding
function M.set_exploration_assistance_enabled(enabled)
    M.exploration_assistance_enabled = enabled
end

-- Get current exploration status
function M.get_exploration_status()
    if pathwalker.is_walking and M.exploration_assistance_enabled then
        if M.exploration_active then
            return "Assisting pathfinding with exploration"
        else
            return "Ready to assist pathfinding"
        end
    elseif not pathwalker.is_walking and M.auto_explore_enabled then
        if M.exploration_active then
            return "Exploring area..."
        else
            return "Looking for exploration targets..."
        end
    else
        return "Explorer integration disabled"
    end
end

-- Clear current exploration state
function M.clear_exploration_state()
    M.exploration_active = false
    explorer.clear_target()
end

-- Main update function to be called from logic.lua
function M.update()
    if pathwalker.is_walking then
        M.update_exploration_assistance()
    else
        M.update_auto_exploration()
    end
    
    M.check_exploration_completion()
end

return M