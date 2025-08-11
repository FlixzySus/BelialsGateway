local logic = {}
local pathwalker = require("core.pathwalker")
local explorer_integration = require("core.explorer_integration")

-- Constants
local TARSARAK_WAYPOINT_ID = 0x8C7B7 -- Tarsarak waypoint
local TARGET_WORLD_ID = 4156639130 -- Sanctuary_Eastern_Continent
local TARGET_ZONE_NAME = "Kehj_Ridge"
local TARGET_WORLD_NAME = "Sanctuary_Eastern_Continent"
local BELIAL_WORLD_ID = 1504937651
local BELIAL_ZONE_NAME = "Boss_Kehj_Belial"

-- Script states
local STATES = {
    IDLE = "Idle",
    TELEPORTING = "Teleporting to Tarsarak",
    WAITING_ARRIVAL = "Waiting for arrival",
    ZONE_VERIFIED = "Zone verified - Ready to path",
    WALKING_PATH = "Walking path to Belial",
    LOOKING_FOR_PORTAL = "Looking for Belial portal",
    INTERACTING_PORTAL = "Interacting with portal",
    WAITING_AFTER_PORTAL = "Waiting after portal interaction",
    WALKING_TO_ALTAR = "Walking to Altar",
    COMPLETED = "Arrived at Altar",
    ERROR = "Error occurred"
}

-- Script variables
local script_state = {
    enabled = false,
    debug_mode = false,
    auto_retry = true,
    retry_delay = 5.0, -- Reduced retry delay for faster retries
    
    current_state = STATES.IDLE,
    current_step = "Ready",
    last_error = "",
    is_active = false,
    
    teleport_start_time = 0,
    teleport_completed = false,
    zone_check_completed = false,
    last_retry_time = 0,
    retry_count = 0,
    max_retries = 10, -- Increased retries for teleport
    
    waypoints = {},
    altar_waypoints = {}, -- ToAlter path waypoints
    
    portal_search_radius = 25.0, -- Significantly increased search radius
    portal_interaction_range = 5.0, -- Increased interaction range
    portal_wait_delay = 3.0, -- Wait 5 seconds after path completion before looking for portal
    post_portal_wait_delay = 7.0, -- Wait 15 seconds after portal interaction before ToAlter path
    
    -- BossTosser integration
    bosstosser_enabled = false, -- Track if BossTosser is enabled
    
    -- Path completion tracking
    near_end_threshold = 2.0,
    path_completed = false,
    path_completion_time = 0, -- Track when path was completed
    portal_interaction_time = 0, -- Track when portal was interacted with
    auto_toggle_executed = false, -- Track if auto-toggle has been executed
    
    -- Position tracking for path verification
    last_player_position = nil,
    position_check_interval = 1.0,
    last_position_check = 0,
    stuck_threshold = 3.0, -- Consider stuck if not moving for 3 seconds
    stuck_timer = 0,
    
    -- Zone loss tracking
    zone_loss_start_time = nil,
    
    -- Path start validation  
    min_distance_to_start = 25.0, -- Increased distance threshold
    teleport_completion_delay = 10.0, -- Wait 15 seconds after teleport for zone check
    zone_verification_delay = 7.0, -- 15 seconds to verify zone after teleport
    
    -- Teleport verification
    teleport_verification_start = 0,
    teleport_attempts = 0,
    max_teleport_attempts = 10, -- Allow many teleport attempts
}

-- Initialize the logic system
function logic.initialize(waypoint_data, altar_waypoint_data)
    script_state.waypoints = waypoint_data or {}
    script_state.altar_waypoints = altar_waypoint_data or {}
    
    if #script_state.waypoints == 0 then
        script_state.last_error = "No TarsarakToBelial waypoints loaded!"
    end
    
    if #script_state.altar_waypoints == 0 then
        script_state.last_error = "No ToAlter waypoints loaded!"
    end
    
    -- Initialize explorer integration (disabled by default for cleaner pathfinding)
    explorer_integration.set_exploration_assistance_enabled(false)
end

-- Check if player is in the correct world/zone (relaxed version)
local function is_in_target_location()
    local current_world = world.get_current_world()
    if not current_world then
        return false
    end
    
    local world_id = current_world:get_world_id()
    local zone_name = current_world:get_current_zone_name()
    local world_name = current_world:get_name()
    
    -- Primary check: correct world and zone
    local primary_match = world_id == TARGET_WORLD_ID and 
                         zone_name == TARGET_ZONE_NAME and 
                         world_name == TARGET_WORLD_NAME
    
    -- Fallback check: just correct world (in case zone name varies)
    local fallback_match = world_id == TARGET_WORLD_ID and 
                          world_name == TARGET_WORLD_NAME
    
    return primary_match or fallback_match
end

-- More lenient zone check for starting the path (relaxed requirements)
local function is_in_correct_zone_for_pathfinding()
    local current_world = world.get_current_world()
    if not current_world then
        return false, "No world data available"
    end
    
    local world_id = current_world:get_world_id()
    local zone_name = current_world:get_current_zone_name()
    local world_name = current_world:get_name()
    
    -- Primary requirement: correct world ID (most important)
    if world_id ~= TARGET_WORLD_ID then
        return false, "Wrong world ID: " .. tostring(world_id) .. " (expected: " .. tostring(TARGET_WORLD_ID) .. ")"
    end
    
    -- Secondary requirement: correct world name (important but allow some flexibility)
    if world_name ~= TARGET_WORLD_NAME then
        -- Log the issue but allow it to pass if world ID is correct
        console.print("Warning: World name mismatch: " .. tostring(world_name) .. " (expected: " .. TARGET_WORLD_NAME .. ") but continuing since World ID matches")
    end
    
    -- Tertiary requirement: zone name (least strict, allow variations)
    if zone_name ~= TARGET_ZONE_NAME then
        -- Check for common zone name variations or patterns
        local zone_ok = false
        
        -- Allow zone names that contain "Kehj" (the main area)
        if zone_name and zone_name:find("Kehj") then
            zone_ok = true
            console.print("Zone name contains 'Kehj', accepting: " .. tostring(zone_name))
        end
        
        -- Allow common zone variations
        local acceptable_zones = {
            "Kehj_Ridge",
            "Kehj_RidgeShared", 
            "Sanctuary_Eastern_Continent",
            "Hawezar",
            "Kehj"
        }
        
        for _, acceptable_zone in ipairs(acceptable_zones) do
            if zone_name == acceptable_zone then
                zone_ok = true
                console.print("Acceptable zone found: " .. tostring(zone_name))
                break
            end
        end
        
        if not zone_ok then
            console.print("Warning: Zone name mismatch: " .. tostring(zone_name) .. " (expected: " .. TARGET_ZONE_NAME .. ") but continuing since World ID is correct")
            -- Don't fail for zone name mismatch if world ID is correct
        end
    end
    
    console.print("Zone check passed - World ID: " .. tostring(world_id) .. ", World Name: " .. tostring(world_name) .. ", Zone: " .. tostring(zone_name))
    return true, "Zone check passed (relaxed validation)"
end

-- Check if player is in Belial's area
local function is_in_belial_area()
    local current_world = world.get_current_world()
    if not current_world then
        return false
    end
    
    local world_id = current_world:get_world_id()
    local zone_name = current_world:get_current_zone_name()
    
    return world_id == BELIAL_WORLD_ID or zone_name == BELIAL_ZONE_NAME
end

-- Check if player is close enough to the path start to begin walking
local function is_close_to_path_start()
    if #script_state.waypoints == 0 then
        return false
    end
    
    local player_pos = get_player_position()
    if not player_pos then
        return false
    end
    
    local path_start = script_state.waypoints[1]
    local distance = player_pos:dist_to_ignore_z(path_start)
    
    return distance <= script_state.min_distance_to_start
end

-- Reset all state variables for a complete restart
local function reset_script_state()
    script_state.current_state = STATES.IDLE
    script_state.current_step = "Ready"
    script_state.last_error = ""
    script_state.is_active = false
    script_state.teleport_start_time = 0
    script_state.teleport_completed = false
    script_state.zone_check_completed = false
    script_state.retry_count = 0
    script_state.path_completed = false
    script_state.path_completion_time = 0
    script_state.portal_interaction_time = 0
    script_state.bosstosser_enabled = false
    script_state.auto_toggle_executed = false
    script_state.last_player_position = nil
    script_state.last_position_check = 0
    script_state.stuck_timer = 0
    script_state.zone_loss_start_time = nil
    script_state.teleport_verification_start = 0
    script_state.teleport_attempts = 0
    
    -- Stop any active pathwalking
    pathwalker.stop_walking()
    explorer_integration.clear_exploration_state()
end

-- Handle teleport retry logic
local function handle_retry()
    local current_time = get_gametime()
    if current_time - script_state.last_retry_time >= script_state.retry_delay then
        if script_state.retry_count < script_state.max_retries then
            script_state.retry_count = script_state.retry_count + 1
            script_state.last_retry_time = current_time
            logic.start_teleport()
        else
            script_state.last_error = "Failed to teleport after " .. script_state.max_retries .. " attempts"
            script_state.current_state = STATES.ERROR
            script_state.is_active = false
        end
    end
end

-- Start teleportation to Tarsarak
function logic.start_teleport()
    script_state.current_state = STATES.TELEPORTING
    script_state.current_step = "Attempting teleport to Tarsarak"
    script_state.teleport_start_time = get_gametime()
    script_state.teleport_verification_start = get_gametime()
    script_state.teleport_attempts = script_state.teleport_attempts + 1
    script_state.is_active = true
    script_state.last_error = ""
    script_state.teleport_completed = false
    script_state.zone_check_completed = false
    
    teleport_to_waypoint(TARSARAK_WAYPOINT_ID)
    
    -- Move to waiting state
    script_state.current_state = STATES.WAITING_ARRIVAL
    script_state.current_step = "Waiting for teleport to complete..."
end

-- Function to check if BossTosser script is enabled
local function is_bosstosser_enabled()
    -- Try to access the BossTosser script's state
    local success, result = pcall(function()
        -- Check for the BosserPlugin global from BossTosser-main
        if _G.BosserPlugin and _G.BosserPlugin.status then
            local status = _G.BosserPlugin.status()
            return status.enabled or false
        end
        return false
    end)
    
    if success then
        return result
    else
        return false
    end
end

-- Function to enable BossTosser script
local function enable_bosstosser()
    local success, result = pcall(function()
        -- Method 1: Try the BosserPlugin global from BossTosser-main
        if _G.BosserPlugin and _G.BosserPlugin.enable then
            _G.BosserPlugin.enable()
            
            -- Wait a moment and check if it worked
            local check_success = false
            local attempts = 0
            while attempts < 10 do
                if _G.BosserPlugin.status and _G.BosserPlugin.status().enabled then
                    check_success = true
                    break
                end
                -- Small delay between checks
                local start_time = get_gametime()
                while get_gametime() - start_time < 0.2 do
                    -- Wait
                end
                attempts = attempts + 1
            end
            
            if check_success then
                return true
            end
        end
        
        -- Method 2: Try accessing the GUI elements directly
        if _G.gui and _G.gui.elements and _G.gui.elements.main_toggle then
            _G.gui.elements.main_toggle:set(true)
            
            -- Check if it worked
            local start_time = get_gametime()
            while get_gametime() - start_time < 2.0 do
                if _G.gui.elements.main_toggle:get() then
                    return true
                end
            end
        end
        
        -- Method 3: Try finding the script module directly
        for module_name, module in pairs(package.loaded) do
            if module_name:find("BossTosser") or module_name:find("bosser") then
                -- Try different ways to enable
                if module.enable then
                    module.enable()
                    return true
                elseif module.BosserPlugin and module.BosserPlugin.enable then
                    module.BosserPlugin.enable()
                    return true
                end
            end
        end
        
        return false
    end)
    
    if success and result then
        script_state.bosstosser_enabled = true
        return true
    else
        return false
    end
end

local function start_altar_pathfinding()
    if #script_state.altar_waypoints == 0 then
        script_state.last_error = "No ToAlter waypoints available for pathfinding"
        script_state.current_state = STATES.ERROR
        return
    end
    
    -- Start pathwalker with the ToAlter path
    local success = pathwalker.start_walking_path_with_points(script_state.altar_waypoints, "ToAlter", false)
    
    if success then
        script_state.current_state = STATES.WALKING_TO_ALTAR
        script_state.current_step = "Walking ToAlter path"
        script_state.last_player_position = get_player_position()
        script_state.last_position_check = get_gametime()
        script_state.stuck_timer = 0
    else
        script_state.last_error = "Failed to start ToAlter pathwalker"
        script_state.current_state = STATES.ERROR
    end
end

-- Start the pathfinding process with the complete TarsarakToBelial path
local function start_pathfinding()
    if #script_state.waypoints == 0 then
        script_state.last_error = "No waypoints available for pathfinding"
        script_state.current_state = STATES.ERROR
        return
    end
    
    -- More lenient zone verification before starting path
    local zone_ok, zone_message = is_in_correct_zone_for_pathfinding()
    if not zone_ok then
        script_state.last_error = "Zone check failed: " .. zone_message
        script_state.current_state = STATES.ERROR
        return
    end
    
    -- Check distance to path start (but be more lenient)
    local player_pos = get_player_position()
    local distance_to_start = math.huge
    if player_pos and #script_state.waypoints > 0 then
        distance_to_start = player_pos:dist_to_ignore_z(script_state.waypoints[1])
    end
    
    -- If too far from start, try to walk to it first
    if distance_to_start > script_state.min_distance_to_start then
        console.print("Distance to start: " .. string.format("%.1f", distance_to_start) .. "m, forcing walk to start")
        -- Force walking to the first coordinate
        local success = pathwalker.start_walking_path_with_points(script_state.waypoints, "TarsarakToBelial", true)
        
        if success then
            script_state.current_state = STATES.WALKING_PATH
            script_state.current_step = "Walking to path start, then following TarsarakToBelial path"
            script_state.path_completed = false
            script_state.path_completion_time = 0
            script_state.last_player_position = get_player_position()
            script_state.last_position_check = get_gametime()
            script_state.stuck_timer = 0
        else
            script_state.last_error = "Failed to start pathwalker"
            script_state.current_state = STATES.ERROR
        end
        return
    end
    
    -- Start pathwalker with the full path, don't walk to first coordinate since we're already close
    local success = pathwalker.start_walking_path_with_points(script_state.waypoints, "TarsarakToBelial", false)
    
    if success then
        script_state.current_state = STATES.WALKING_PATH
        script_state.current_step = "Walking TarsarakToBelial path"
        script_state.path_completed = false
        script_state.path_completion_time = 0
        script_state.last_player_position = get_player_position()
        script_state.last_position_check = get_gametime()
        script_state.stuck_timer = 0
    else
        script_state.last_error = "Failed to start pathwalker"
        script_state.current_state = STATES.ERROR
    end
end

-- Check if player is stuck (not moving for too long)
local function check_if_stuck()
    -- Don't check for stuck if pathwalker isn't active or path is completed
    if not pathwalker.is_walking or pathwalker.is_path_completed() then
        return false
    end
    
    local current_time = get_gametime()
    
    if current_time - script_state.last_position_check < script_state.position_check_interval then
        return false
    end
    
    local player_pos = get_player_position()
    if not player_pos then
        return false
    end
    
    if script_state.last_player_position then
        local distance_moved = player_pos:dist_to_ignore_z(script_state.last_player_position)
        
        if distance_moved < 1.0 then -- Moved less than 1 meter
            script_state.stuck_timer = script_state.stuck_timer + script_state.position_check_interval
            
            if script_state.stuck_timer >= script_state.stuck_threshold then
                return true
            end
        else
            script_state.stuck_timer = 0 -- Reset stuck timer if moving
        end
    end
    
    script_state.last_player_position = player_pos
    script_state.last_position_check = current_time
    return false
end

-- Portal identification constants
local BELIAL_PORTAL = {
    id = 153616422,
    type_id = 922770521,
    secondary_data_id = 138412099,
    skin_name = "Portal_Dungeon_Generic"
}

-- Look for and interact with Belial portal
local function handle_portal_interaction()
    local player_pos = get_player_position()
    if not player_pos then
        return
    end
    
    -- Look for ALL actors first for debugging
    local all_actors = actors_manager.get_all_actors()
    
    local interactable_count = 0
    local target_portal = nil
    local closest_distance = math.huge
    local closest_interactable = nil
    local closest_interactable_distance = math.huge
    
    -- Search through all actors
    for _, actor in ipairs(all_actors) do
        if actor then
            local actor_pos = actor:get_position()
            if actor_pos then
                local distance = player_pos:dist_to_ignore_z(actor_pos)
                
                -- Check if it's interactable
                if actor:is_interactable() then
                    interactable_count = interactable_count + 1
                    
                    -- Log details of all nearby interactables
                    if distance < script_state.portal_search_radius then
                        -- Track closest interactable regardless of type
                        if distance < closest_interactable_distance then
                            closest_interactable_distance = distance
                            closest_interactable = actor
                        end
                        
                        -- Check for our specific portal
                        local is_target_portal = false
                        
                        -- Primary check: skin name
                        if actor:get_skin_name() == BELIAL_PORTAL.skin_name then
                            is_target_portal = true
                        end
                        
                        -- Secondary checks
                        if actor:get_id() == BELIAL_PORTAL.id then
                            is_target_portal = true
                        end
                        
                        if actor:get_type_id() == BELIAL_PORTAL.type_id then
                            is_target_portal = true
                        end
                        
                        if actor:get_secondary_data_id() == BELIAL_PORTAL.secondary_data_id then
                            is_target_portal = true
                        end
                        
                        if is_target_portal and distance < closest_distance then
                            closest_distance = distance
                            target_portal = actor
                        end
                    end
                end
            end
        end
    end
    
    if target_portal then
        if closest_distance <= script_state.portal_interaction_range then
            script_state.current_state = STATES.INTERACTING_PORTAL
            script_state.current_step = "Interacting with Belial portal"
            
            local interaction_success = interact_object(target_portal)
            
            if interaction_success then
                script_state.current_state = STATES.WAITING_AFTER_PORTAL
                script_state.current_step = "Portal interaction successful - Waiting " .. script_state.post_portal_wait_delay .. "s before ToAlter path"
                script_state.portal_interaction_time = get_gametime()
            else
                pathfinder.request_move(target_portal:get_position())
                script_state.current_step = "Moving closer to portal for interaction"
            end
        else
            pathfinder.request_move(target_portal:get_position())
            script_state.current_step = "Moving to portal (distance: " .. string.format("%.2f", closest_distance) .. "m)"
        end
    else
        if closest_interactable then
            -- Try interacting with closest interactable as fallback
            if closest_interactable_distance <= script_state.portal_interaction_range then
                local interaction_success = interact_object(closest_interactable)
                
                if interaction_success then
                    script_state.current_state = STATES.WAITING_AFTER_PORTAL
                    script_state.current_step = "Portal interaction successful (fallback) - Waiting " .. script_state.post_portal_wait_delay .. "s before ToAlter path"
                    script_state.portal_interaction_time = get_gametime()
                else
                    pathfinder.request_move(closest_interactable:get_position())
                    script_state.current_step = "Moving to closest interactable"
                end
            else
                pathfinder.request_move(closest_interactable:get_position())
                script_state.current_step = "Moving to closest interactable (distance: " .. string.format("%.2f", closest_interactable_distance) .. "m)"
            end
        else
            -- Move to exact final coordinate
            if #script_state.waypoints > 0 then
                local end_pos = script_state.waypoints[#script_state.waypoints]
                local distance_to_final = player_pos:dist_to_ignore_z(end_pos)
                
                if distance_to_final > 1.0 then
                    pathfinder.request_move(end_pos)
                    script_state.current_step = "Moving to exact final coordinate"
                else
                    script_state.current_step = "At final coordinate - No portal detected"
                end
            end
        end
    end
end

-- Handle teleport verification and retry logic
local function handle_teleport_verification()
    local current_time = get_gametime()
    local time_since_teleport = current_time - script_state.teleport_verification_start
    
    -- Check if we're in the correct location
    if is_in_target_location() then
        script_state.teleport_completed = true
        script_state.current_state = STATES.ZONE_VERIFIED
        script_state.current_step = "Teleport successful - Verifying zone for " .. script_state.zone_verification_delay .. " seconds"
        script_state.teleport_start_time = current_time -- Reset timer for zone verification delay
        return
    end
    
    -- If we've waited long enough and still not in correct zone, retry
    if time_since_teleport >= script_state.retry_delay then
        if script_state.teleport_attempts < script_state.max_teleport_attempts then
            -- Reset and retry teleport
            script_state.current_state = STATES.TELEPORTING
            script_state.current_step = "Retrying teleport to Tarsarak"
            script_state.teleport_verification_start = current_time
            script_state.teleport_attempts = script_state.teleport_attempts + 1
            
            teleport_to_waypoint(TARSARAK_WAYPOINT_ID)
            
            script_state.current_state = STATES.WAITING_ARRIVAL
            script_state.current_step = "Waiting for teleport retry to complete..."
        else
            script_state.last_error = "Failed to teleport after " .. script_state.max_teleport_attempts .. " attempts"
            script_state.current_state = STATES.ERROR
            script_state.is_active = false
        end
    else
        -- Still waiting for teleport to complete
        local remaining = script_state.retry_delay - time_since_teleport
        script_state.current_step = "Waiting for teleport... (" .. string.format("%.1f", remaining) .. "s remaining)"
    end
end

-- Main update function
function logic.on_update()
    if not script_state.enabled then
        return
    end
    
    -- Update pathwalker
    pathwalker.update_path_walking()
    
    -- State machine logic
    if script_state.current_state == STATES.IDLE and script_state.enabled then
        logic.start_teleport()
        
    elseif script_state.current_state == STATES.WAITING_ARRIVAL then
        if is_in_target_location() then
            script_state.teleport_completed = true
            script_state.zone_check_completed = true
            script_state.current_state = STATES.ZONE_VERIFIED
            script_state.current_step = "Zone verified - Waiting before starting path"
            
            -- Add delay before starting path to ensure teleport is fully complete
            script_state.teleport_start_time = get_gametime()
        elseif script_state.auto_retry and not script_state.teleport_completed then
            handle_teleport_verification()
        end
        
    elseif script_state.current_state == STATES.ZONE_VERIFIED then
        -- Wait for teleport completion delay
        local current_time = get_gametime()
        if current_time - script_state.teleport_start_time >= script_state.teleport_completion_delay then
            -- Re-verify zone before starting path (using relaxed check)
            local zone_ok, zone_message = is_in_correct_zone_for_pathfinding()
            if zone_ok then
                start_pathfinding()
            else
                script_state.last_error = "Zone verification failed before pathfinding: " .. zone_message
                script_state.current_state = STATES.ERROR
            end
        else
            local remaining = script_state.teleport_completion_delay - (current_time - script_state.teleport_start_time)
            script_state.current_step = "Zone verified - Starting path in " .. string.format("%.1f", remaining) .. "s"
        end
        
    elseif script_state.current_state == STATES.WALKING_PATH then
        -- Use more lenient zone checking during pathwalking to avoid false positives
        if not is_in_target_location() then
            -- Add a small delay before declaring zone loss to handle temporary transitions
            if not script_state.zone_loss_start_time then
                script_state.zone_loss_start_time = get_gametime()
            elseif get_gametime() - script_state.zone_loss_start_time > 10.0 then -- 10 second grace period during pathwalking
                script_state.last_error = "Left target zone during pathwalking (confirmed after 10s delay)"
                script_state.current_state = STATES.ERROR
                pathwalker.stop_walking()
                script_state.zone_loss_start_time = nil
                return
            end
        else
            -- Reset zone loss timer if we're back in the correct zone
            script_state.zone_loss_start_time = nil
        end
        
        -- Check for stuck condition (only if path isn't completed)
        if check_if_stuck() then
            pathwalker.stop_walking()
            
            -- Try to restart pathfinding after a short delay
            script_state.current_state = STATES.ZONE_VERIFIED
            script_state.teleport_start_time = get_gametime()
            script_state.stuck_timer = 0
            return
        end
        
        -- Check if pathwalker has completed the path OR if we're at the final waypoint
        if pathwalker.is_path_completed() or pathwalker.is_at_final_waypoint() then
            script_state.current_state = STATES.LOOKING_FOR_PORTAL
            script_state.current_step = "Path completed - Waiting " .. script_state.portal_wait_delay .. "s before portal search"
            script_state.path_completed = true
            script_state.path_completion_time = get_gametime() -- Record when path was completed
            
            -- Stop pathwalker to prevent interference with portal interaction
            if pathwalker.is_walking then
                pathwalker.stop_walking()
            end
        end
        
        -- Fallback: If we're close to the final waypoint, also trigger portal search
        local player_pos = get_player_position()
        if player_pos and #script_state.waypoints > 0 then
            local final_waypoint = script_state.waypoints[#script_state.waypoints]
            local distance_to_final = player_pos:dist_to_ignore_z(final_waypoint)
            
            if distance_to_final <= 3.0 then -- Within 3 meters of final waypoint
                script_state.current_state = STATES.LOOKING_FOR_PORTAL
                script_state.current_step = "Near final waypoint - Waiting " .. script_state.portal_wait_delay .. "s before portal search"
                script_state.path_completed = true
                script_state.path_completion_time = get_gametime()
                
                if pathwalker.is_walking then
                    pathwalker.stop_walking()
                end
            end
        end
        
    elseif script_state.current_state == STATES.LOOKING_FOR_PORTAL then
        local current_time = get_gametime()
        local time_since_completion = current_time - script_state.path_completion_time
        
        -- Wait for the specified delay before starting portal search
        if time_since_completion < script_state.portal_wait_delay then
            local remaining = script_state.portal_wait_delay - time_since_completion
            script_state.current_step = "Waiting " .. string.format("%.1f", remaining) .. "s before portal search"
            return
        end
        
        -- Now actually search for portal
        script_state.current_step = "Searching for Portal_Dungeon_Generic..."
        
        -- Ensure we're at the final coordinate before searching for portal
        local player_pos = get_player_position()
        if player_pos and #script_state.waypoints > 0 then
            local final_waypoint = script_state.waypoints[#script_state.waypoints]
            local distance_to_final = player_pos:dist_to_ignore_z(final_waypoint)
            
            -- If we're not close to the final waypoint, move there first
            if distance_to_final > 3.0 then
                pathfinder.request_move(final_waypoint)
                script_state.current_step = "Moving to final coordinate for portal search"
            else
                -- We're close to final coordinate, now search for portal
                handle_portal_interaction()
            end
        else
            -- No waypoints or player position, just search for portal
            handle_portal_interaction()
        end
        
    elseif script_state.current_state == STATES.WAITING_AFTER_PORTAL then
        local current_time = get_gametime()
        local time_since_portal = current_time - script_state.portal_interaction_time
        
        -- Wait for the specified delay before starting ToAlter path
        if time_since_portal < script_state.post_portal_wait_delay then
            local remaining = script_state.post_portal_wait_delay - time_since_portal
            script_state.current_step = "Waiting " .. string.format("%.1f", remaining) .. "s before ToAlter path"
        else
            start_altar_pathfinding()
        end
        
    elseif script_state.current_state == STATES.WALKING_TO_ALTAR then
        -- Check if we're near the end of the ToAlter path (last few waypoints)
        local player_pos = get_player_position()
        local path_completed = false
        local near_altar = false
        
        if player_pos and #script_state.altar_waypoints > 0 then
            -- Check if we're close to the final waypoint or at one of the last few waypoints
            local final_waypoint = script_state.altar_waypoints[#script_state.altar_waypoints]
            local distance_to_final = player_pos:dist_to_ignore_z(final_waypoint)
            
            -- Get current pathwalker progress
            local current_wp, total_wp = pathwalker.get_progress()
            local waypoints_remaining = total_wp - current_wp
            
            -- Check if we're very close to the final waypoint (arrival detection)
            if distance_to_final <= 2.0 then
                path_completed = true
            end
            
            -- Check if we're near the altar for auto-toggle
            if distance_to_final <= 10.0 or waypoints_remaining <= 3 then
                near_altar = true
            end
            
            -- Auto-toggle when near completion (within 10m of final OR last 3 waypoints)
            if near_altar and not script_state.auto_toggle_executed then
                -- Auto-toggle the controls
                logic.auto_toggle_controls()
                script_state.auto_toggle_executed = true
                script_state.current_step = "Near altar - Activating Bosser integration"
            end
        end
        
        -- Check if ToAlter pathwalker has completed the path OR we're very close to final waypoint
        if pathwalker.is_path_completed() or pathwalker.is_at_final_waypoint() or path_completed then
            -- BossTosser should already be enabled by the auto-toggle, but double-check
            local bosstosser_status = is_bosstosser_enabled()
            if not bosstosser_status then
                enable_bosstosser()
            end
            
            script_state.current_state = "Arrived at Altar"
            script_state.current_step = "Starting Bosser"
            script_state.is_active = false
            
            -- Stop pathwalker
            if pathwalker.is_walking then
                pathwalker.stop_walking()
            end
        end
        
        -- Check for stuck condition during ToAlter path
        if check_if_stuck() then
            pathwalker.stop_walking()
            
            -- Try to restart ToAlter pathfinding after a short delay
            script_state.current_state = STATES.WAITING_AFTER_PORTAL
            script_state.portal_interaction_time = get_gametime() - script_state.post_portal_wait_delay + 2.0 -- Add 2 second delay
            script_state.stuck_timer = 0
            return
        end
        
    elseif script_state.current_state == STATES.ERROR then
        -- Stay in error state until manually reset
        if script_state.debug_mode then
            -- Error state handling (silent)
        end
    end
end

-- Render debug information
function logic.on_render()
    if not script_state.debug_mode then
        return
    end
    
    local player_pos = get_player_position()
    if not player_pos then
        return
    end
    
    -- Draw pathwalker progress if active
    if pathwalker.is_walking and #pathwalker.current_path > 0 then
        local current_wp_index = pathwalker.current_waypoint_index
        
        if current_wp_index <= #pathwalker.current_path then
            local current_waypoint = pathwalker.current_path[current_wp_index]
            graphics.circle_3d(current_waypoint, 1.5, color_yellow(200))
            graphics.text_3d("Current WP #" .. current_wp_index, current_waypoint, 12, color_yellow(255))
            graphics.line(player_pos, current_waypoint, color_yellow(150), 2.0)
        end
        
        -- Draw next few waypoints for context
        for i = current_wp_index + 1, math.min(current_wp_index + 3, #pathwalker.current_path) do
            local waypoint = pathwalker.current_path[i]
            graphics.circle_3d(waypoint, 0.8, color_green(150))
            graphics.text_3d(tostring(i), waypoint, 10, color_green(255))
        end
    end
    
    -- Draw waypoints every 10 coordinates for cleaner visualization
    if #script_state.waypoints > 0 then
        -- Draw every 10th waypoint
        for i = 1, #script_state.waypoints, 10 do
            local waypoint = script_state.waypoints[i]
            graphics.circle_3d(waypoint, 0.5, color_white(150))
            graphics.text_3d(tostring(i), waypoint, 10, color_white(255))
        end
        
        -- Always draw the first waypoint (start)
        graphics.circle_3d(script_state.waypoints[1], 1.5, color_green(255))
        graphics.text_3d("START", script_state.waypoints[1], 12, color_green(255))
        
        -- Always draw the last waypoint (end)
        graphics.circle_3d(script_state.waypoints[#script_state.waypoints], 1.5, color_red(255))
        graphics.text_3d("END", script_state.waypoints[#script_state.waypoints], 12, color_red(255))
        
        -- Show distance to path start
        local path_start = script_state.waypoints[1]
        local distance_to_start = player_pos:dist_to_ignore_z(path_start)
        graphics.line(player_pos, path_start, color_orange(100), 1.0)
        graphics.text_3d("Dist: " .. string.format("%.1f", distance_to_start) .. "m", path_start, 10, color_orange(255))
    end
end

-- Public interface functions
function logic.set_enabled(enabled)
    if script_state.enabled ~= enabled then
        script_state.enabled = enabled
        if enabled then
            reset_script_state() -- Always perform complete reset when enabling
            -- Force immediate start of teleport sequence
            script_state.current_state = STATES.IDLE
        else
            reset_script_state() -- Clean stop when disabling
        end
    end
end

function logic.set_debug_mode(debug)
    script_state.debug_mode = debug
end

function logic.set_auto_retry(auto_retry)
    script_state.auto_retry = auto_retry
end

-- Auto-toggle controls function (called when approaching altar)
function logic.auto_toggle_controls()
    -- Import GUI and toggle controls
    local gui = require("gui")
    if gui and gui.auto_toggle_controls then
        gui.auto_toggle_controls()
    end
    
    -- Enable BossTosser immediately
    local success = enable_bosstosser()
    if not success then
        -- Retry failed
    end
end

-- Auto-disable script function (called when ToAlter path completes)
function logic.auto_disable_script()
    -- This function will be called by the GUI to disable both toggles
    -- Import GUI and disable toggles
    local gui = require("gui")
    if gui and gui.auto_disable_toggles then
        gui.auto_disable_toggles()
    end
end

function logic.stop_script()
    reset_script_state()
end

function logic.get_status()
    local current_waypoint = 0
    local total_waypoints = #script_state.waypoints
    
    -- Get progress from pathwalker if it's active
    if pathwalker.is_walking then
        current_waypoint, total_waypoints = pathwalker.get_progress()
    end
    
    -- Calculate distance to start
    local distance_to_start = math.huge
    if #script_state.waypoints > 0 then
        local player_pos = get_player_position()
        if player_pos then
            distance_to_start = player_pos:dist_to_ignore_z(script_state.waypoints[1])
        end
    end
    
    return {
        state = script_state.current_state,
        current_step = script_state.current_step,
        last_error = script_state.last_error,
        is_active = script_state.is_active,
        retry_count = script_state.retry_count,
        max_retries = script_state.max_retries,
        current_waypoint = current_waypoint,
        total_waypoints = total_waypoints,
        distance_to_start = distance_to_start,
        stuck_timer = script_state.stuck_timer,
        pathwalker_status = pathwalker.get_status(),
        teleport_attempts = script_state.teleport_attempts,
        max_teleport_attempts = script_state.max_teleport_attempts,
        bosstosser_enabled = script_state.bosstosser_enabled,
        bosstosser_status = is_bosstosser_enabled() and "Enabled" or "Disabled"
    }
end

return logic