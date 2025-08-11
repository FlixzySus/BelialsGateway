-- pathwalker.lua - Fixed and optimized for Belial's Gateway
local M = {}

-- Path walker state
M.is_walking = false
M.is_paused = false
M.current_path = {}
M.current_waypoint_index = 1
M.walking_forward = true
M.loop_enabled = false
M.path_threshold = 1.2 -- Slightly increased threshold to prevent overshooting

-- Navigation state
M.walking_to_start = false
M.start_distance_threshold = 3.0 -- Reduced threshold for more precise start detection
M.original_path = {}

-- Movement timing controls
M.last_move_request = 0
M.move_request_interval = 0.1 -- Limit movement requests to every 100ms
M.waypoint_reached_delay = 0.2 -- Small delay after reaching waypoint before advancing

-- Stuck detection
M.last_position = nil
M.last_position_time = 0
M.stuck_threshold = 2.0 -- Consider stuck if not moving for 2 seconds
M.stuck_check_interval = 0.5

-- Check if player needs to walk to path start
local function check_distance_to_path_start(points)
    if not points or #points == 0 then
        return false, 0
    end
    
    local player_position = get_player_position()
    if not player_position then
        return false, 0
    end
    
    local path_start = points[1]
    if not path_start then
        return false, 0
    end
    
    local success, distance = pcall(function()
        return player_position:dist_to_ignore_z(path_start)
    end)
    
    if not success then
        console.print("Error calculating distance to path start")
        return false, 0
    end
    
    return distance > M.start_distance_threshold, distance
end

-- Create navigation path to start
local function create_navigation_to_start(start_position)
    local player_position = get_player_position()
    if not player_position or not start_position then
        return nil
    end
    
    -- Create a simple path from current position to start
    return {player_position, start_position}
end

-- Check if player is stuck at current position
local function check_stuck_condition()
    -- Don't check for stuck condition if we're at or near the last waypoint
    if M.current_waypoint_index >= #M.current_path then
        return false
    end
    
    local current_time = get_gametime()
    local player_position = get_player_position()
    
    if not player_position then
        return false
    end
    
    -- Check stuck condition every interval
    if current_time - M.last_position_time < M.stuck_check_interval then
        return false
    end
    
    if M.last_position then
        local distance_moved = player_position:dist_to_ignore_z(M.last_position)
        
        if distance_moved < 0.5 then -- Moved less than 0.5 meters
            if current_time - M.last_position_time >= M.stuck_threshold then
                return true
            end
        else
            M.last_position_time = current_time -- Reset timer if moving
        end
    else
        M.last_position_time = current_time
    end
    
    M.last_position = player_position
    return false
end

-- Start walking a path with given waypoints
function M.start_walking_path_with_points(points, path_name, force_walk_to_first)
    local success, result = pcall(function()
        if not points or #points == 0 then
            return false, "No waypoints provided"
        end
        
        -- Store the original path
        M.original_path = {}
        for i, point in ipairs(points) do
            M.original_path[i] = point
        end
        
        -- If force_walk_to_first is true, always walk to first coordinate regardless of distance
        if force_walk_to_first then
            console.print("Force walking to first coordinate of the path...")
            
            -- Create navigation path to start
            local nav_path = create_navigation_to_start(points[1])
            if nav_path then
                M.current_path = nav_path
                M.current_waypoint_index = 2 -- Go to the start position
                M.walking_to_start = true
            else
                return false, "Failed to create navigation path to start"
            end
        else
            -- Check if player is far from path start (original behavior)
            local needs_navigation, distance = check_distance_to_path_start(points)
            
            if needs_navigation then
                console.print(string.format("Player is %.1fm from path start. Walking to starting position first...", distance))
                
                -- Create navigation path to start
                local nav_path = create_navigation_to_start(points[1])
                if nav_path then
                    M.current_path = nav_path
                    M.current_waypoint_index = 2 -- Go to the start position
                    M.walking_to_start = true
                else
                    return false, "Failed to create navigation path to start"
                end
            else
                console.print(string.format("Player is close to path start (%.1fm). Starting path walk directly.", distance))
                
                -- Start walking the actual path
                M.current_path = {}
                for i, point in ipairs(points) do
                    M.current_path[i] = point
                end
                M.current_waypoint_index = 1
                M.walking_to_start = false
            end
        end
        
        M.walking_forward = true
        M.is_walking = true
        M.is_paused = false
        M.last_move_request = 0
        M.last_position = nil
        M.last_position_time = get_gametime()
        
        local display_name = path_name or "Custom Path"
        console.print("Started walking path: " .. display_name .. " (" .. #points .. " waypoints)")
        return true, "Success"
    end)
    
    if not success then
        console.print("Error starting path walk: " .. tostring(result))
        return false
    end
    
    return result
end

-- Stop walking completely
function M.stop_walking()
    M.is_walking = false
    M.is_paused = false
    M.current_path = {}
    M.current_waypoint_index = 1
    M.walking_forward = true
    M.walking_to_start = false
    M.original_path = {}
    M.last_move_request = 0
    M.last_position = nil
    M.last_position_time = 0
    console.print("Stopped walking path")
end

-- Pause/resume walking
function M.toggle_pause()
    if not M.is_walking then
        return false
    end
    
    M.is_paused = not M.is_paused
    console.print(M.is_paused and "Paused path walking" or "Resumed path walking")
    return true
end

-- Set loop mode
function M.set_loop_enabled(enabled)
    M.loop_enabled = enabled
    console.print("Path looping " .. (enabled and "enabled" or "disabled"))
end

-- Get next waypoint in the sequence
local function get_next_waypoint_index()
    if not M.current_path or #M.current_path == 0 then
        return nil
    end
    
    if M.walking_forward then
        if M.current_waypoint_index < #M.current_path then
            return M.current_waypoint_index + 1
        else
            return nil -- End of path
        end
    else
        if M.current_waypoint_index > 1 then
            return M.current_waypoint_index - 1
        else
            return nil -- End of path
        end
    end
end

-- Handle transition from navigation to actual path
local function handle_start_reached()
    if not M.walking_to_start or #M.original_path == 0 then
        return
    end
    
    console.print("Reached path starting position. Beginning actual path walk...")
    
    -- Switch to the actual path
    M.current_path = {}
    for i, point in ipairs(M.original_path) do
        M.current_path[i] = point
    end
    M.current_waypoint_index = 1
    M.walking_to_start = false
    M.walking_forward = true
    
    console.print("Now walking the recorded path (" .. #M.current_path .. " waypoints)")
end

-- Update path walking logic
function M.update_path_walking()
    local success, err = pcall(function()
        if not M.is_walking or M.is_paused or #M.current_path == 0 then
            return
        end
        
        local player_position = get_player_position()
        if not player_position then
            return
        end
        
        if M.current_waypoint_index < 1 or M.current_waypoint_index > #M.current_path then
            console.print("Invalid waypoint index, stopping")
            M.stop_walking()
            return
        end
        
        local current_waypoint = M.current_path[M.current_waypoint_index]
        if not current_waypoint then
            console.print("Invalid waypoint, stopping")
            M.stop_walking()
            return
        end
        
        local distance = player_position:dist_to_ignore_z(current_waypoint)
        
        -- Check if we've reached the current waypoint
        if distance <= M.path_threshold then
            if M.walking_to_start then
                -- We've reached the start position, transition to actual path
                handle_start_reached()
                return
            else
                -- Normal waypoint progression
                local next_index = get_next_waypoint_index()
                
                if next_index then
                    M.current_waypoint_index = next_index
                    console.print("Reached waypoint " .. (M.current_waypoint_index - 1) .. 
                                 ", moving to waypoint " .. M.current_waypoint_index)
                else
                    -- We've reached the final waypoint - path completed
                    console.print("Reached the final waypoint (#" .. M.current_waypoint_index .. ") - Path completed!")
                    M.stop_walking()
                    return
                end
            end
        end
        
        -- Only check for stuck condition if we haven't reached the final waypoint
        if M.current_waypoint_index < #M.current_path then
            if check_stuck_condition() then
                console.print("Player appears stuck, attempting to continue to next waypoint...")
                local next_index = get_next_waypoint_index()
                if next_index then
                    M.current_waypoint_index = next_index
                    console.print("Skipped to waypoint " .. M.current_waypoint_index .. " due to stuck condition")
                    -- Reset stuck detection after skipping
                    M.last_position = nil
                    M.last_position_time = get_gametime()
                else
                    console.print("Reached end of path due to stuck condition")
                    M.stop_walking()
                    return
                end
            end
        end
        
        -- Move towards current waypoint with rate limiting
        local current_time = get_gametime()
        if current_time - M.last_move_request >= M.move_request_interval then
            local target_waypoint = M.current_path[M.current_waypoint_index]
            if target_waypoint then
                pathfinder.request_move(target_waypoint)
                M.last_move_request = current_time
            end
        end
    end)
    
    if not success then
        console.print("Error in path walking update: " .. tostring(err))
        M.stop_walking()
    end
end

-- Get current status for display
function M.get_status()
    if not M.is_walking then
        return "Not walking"
    elseif M.is_paused then
        return "Paused"
    elseif M.walking_to_start then
        return "Walking to path start"
    else
        return string.format("Walking waypoint %d/%d", 
                           M.current_waypoint_index, 
                           #M.current_path)
    end
end

-- Check if we're at the final waypoint
function M.is_at_final_waypoint()
    if not M.is_walking or #M.current_path == 0 then
        return false
    end
    
    -- Check if we're at the last waypoint and close to it
    local player_position = get_player_position()
    if not player_position or M.current_waypoint_index ~= #M.current_path then
        return false
    end
    
    local final_waypoint = M.current_path[#M.current_path]
    if not final_waypoint then
        return false
    end
    
    local distance = player_position:dist_to_ignore_z(final_waypoint)
    return distance <= M.path_threshold
end

-- Check if the pathwalker has reached the end of the path
function M.is_path_completed()
    -- Path is completed if we're not walking AND we had waypoints to walk
    return not M.is_walking and (#M.original_path > 0 or #M.current_path > 0)
end

-- Get progress information
function M.get_progress()
    if not M.is_walking or #M.current_path == 0 then
        return 0, 0
    end
    
    if M.walking_to_start then
        return 0, #M.original_path -- Not started actual path yet
    end
    
    return M.current_waypoint_index, #M.current_path
end

return M