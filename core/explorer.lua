local CHUNK_SIZE = 5
local GRID_SIZE = 1
local CELL_UNEXPLORED, CELL_EXPLORED, CELL_NON_WALKABLE = 0, 1, 2
local RECENT_VISIT_COOLDOWN = 3000
local EXPLORATION_RADIUS = 5 * GRID_SIZE

local ExplorationChunk = {}
ExplorationChunk.__index = ExplorationChunk

function ExplorationChunk.new()
    return setmetatable({cells = {}, dirty = false}, ExplorationChunk)
end

function ExplorationChunk:get(x, y)
    return self.cells[y * CHUNK_SIZE + x] or CELL_UNEXPLORED
end

function ExplorationChunk:set(x, y, value)
    self.cells[y * CHUNK_SIZE + x] = value
    self.dirty = true
end

function ExplorationChunk:is_unexplored()
    local unexplored_count = 0
    for _, cell in pairs(self.cells) do
        if cell == CELL_UNEXPLORED then unexplored_count = unexplored_count + 1 end
    end
    return unexplored_count / (CHUNK_SIZE * CHUNK_SIZE) > 0.02
end

local Quadtree = {}
Quadtree.__index = Quadtree

function Quadtree.new(x, y, width, height, depth)
    return setmetatable({x = x, y = y, width = width, height = height, depth = depth, children = nil, chunk = nil}, Quadtree)
end

function Quadtree:insert(x, y, chunk)
    if self.depth == 0 or (self.chunk and not self.children) then
        self.chunk = chunk
        return
    end
    if not self.children then self:split() end
    local index = self:get_index(x, y)
    if index then self.children[index]:insert(x, y, chunk) end
end

function Quadtree:get(x, y)
    if self.chunk and not self.children then return self.chunk end
    local index = self:get_index(x, y)
    return index and self.children and self.children[index]:get(x, y) or nil
end

function Quadtree:split()
    local subWidth, subHeight = self.width / 2, self.height / 2
    self.children = {
        Quadtree.new(self.x, self.y, subWidth, subHeight, self.depth - 1),
        Quadtree.new(self.x + subWidth, self.y, subWidth, subHeight, self.depth - 1),
        Quadtree.new(self.x, self.y + subHeight, subWidth, subHeight, self.depth - 1),
        Quadtree.new(self.x + subWidth, self.y + subHeight, subWidth, subHeight, self.depth - 1)
    }
end

function Quadtree:get_index(x, y)
    local verticalMidpoint, horizontalMidpoint = self.x + (self.width / 2), self.y + (self.height / 2)
    local topQuadrant, leftQuadrant = (y < horizontalMidpoint), (x < verticalMidpoint)
    return leftQuadrant and (topQuadrant and 1 or 3) or (topQuadrant and 2 or 4)
end

local PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

function PriorityQueue.new()
    return setmetatable({heap = {}}, PriorityQueue)
end

function PriorityQueue:push(value, priority)
    table.insert(self.heap, {value = value, priority = priority})
    self:bubble_up(#self.heap)
end

function PriorityQueue:pop()
    if #self.heap == 0 then return nil end
    local result = self.heap[1]
    self.heap[1] = self.heap[#self.heap]
    table.remove(self.heap)
    self:bubble_down(1)
    return result.value, result.priority
end

function PriorityQueue:bubble_up(index)
    local parent = math.floor(index / 2)
    while index > 1 and self.heap[index].priority < self.heap[parent].priority do
        self.heap[index], self.heap[parent] = self.heap[parent], self.heap[index]
        index, parent = parent, math.floor(parent / 2)
    end
end

function PriorityQueue:bubble_down(index)
    local size = #self.heap
    while true do
        local smallest, left, right = index, 2 * index, 2 * index + 1
        if left <= size and self.heap[left].priority < self.heap[smallest].priority then
            smallest = left
        end
        if right <= size and self.heap[right].priority < self.heap[smallest].priority then
            smallest = right
        end
        if smallest == index then break end
        self.heap[index], self.heap[smallest] = self.heap[smallest], self.heap[index]
        index = smallest
    end
end

local exploration_quadtree = Quadtree.new(-1000, -1000, 2000, 2000, 20)
local frontier_chunks, recently_visited_chunks = {}, {}
local exploration_targets = PriorityQueue.new()
local current_target = nil

local function grid_key(pos)
    return math.floor(pos:x() / GRID_SIZE), math.floor(pos:y() / GRID_SIZE)
end

local function manage_frontier(chunk_x, chunk_y, add)
    local key = chunk_x .. "," .. chunk_y
    if add then
        frontier_chunks[key] = frontier_chunks[key] or {x = chunk_x, y = chunk_y}
    else
        frontier_chunks[key] = nil
    end
end

local function update_frontier(chunk_x, chunk_y)
    manage_frontier(chunk_x, chunk_y, false)
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local nx, ny = chunk_x + dx, chunk_y + dy
                local chunk = exploration_quadtree:get(nx, ny)
                if chunk and chunk:is_unexplored() then
                    manage_frontier(nx, ny, true)
                end
            end
        end
    end
end

local function evaluate_chunk(chunk, chunk_x, chunk_y, player_pos)
    local chunk_center = vec3:new(chunk_x * CHUNK_SIZE + CHUNK_SIZE / 2, chunk_y * CHUNK_SIZE + CHUNK_SIZE / 2, player_pos:z())
    local distance = player_pos:dist_to(chunk_center)
    local unexplored_count, explored_count = 0, 0
    for x = 0, CHUNK_SIZE - 1 do
        for y = 0, CHUNK_SIZE - 1 do
            local cell = chunk:get(x, y)
            if cell == CELL_UNEXPLORED then
                unexplored_count = unexplored_count + 1
            elseif cell == CELL_EXPLORED then
                explored_count = explored_count + 1
            end
        end
    end
    return (distance + 1) * (unexplored_count - (explored_count * 0.5))
end

local function manage_recently_visited(chunk_x, chunk_y, add)
    local key = chunk_x .. "," .. chunk_y
    if add then
        recently_visited_chunks[key] = get_gametime()
    else
        return recently_visited_chunks[key] and (get_gametime() - recently_visited_chunks[key]) < RECENT_VISIT_COOLDOWN
    end
end

local function update_exploration_grid()
    local player_pos = get_player_position()
    if not player_pos then return end
    
    local gx, gy = grid_key(player_pos)
    local chunk_x, chunk_y = math.floor(gx / CHUNK_SIZE), math.floor(gy / CHUNK_SIZE)

    for dx = -1, 1 do
        for dy = -1, 1 do
            local cx, cy = chunk_x + dx, chunk_y + dy
            local chunk = exploration_quadtree:get(cx, cy) or ExplorationChunk.new()
            exploration_quadtree:insert(cx, cy, chunk)

            for x = 0, CHUNK_SIZE - 1 do
                for y = 0, CHUNK_SIZE - 1 do
                    local world_x, world_y = cx * CHUNK_SIZE + x, cy * CHUNK_SIZE + y
                    local world_pos = vec3:new(world_x * GRID_SIZE, world_y * GRID_SIZE, player_pos:z())
                    world_pos = utility.set_height_of_valid_position(world_pos)
                    local distance = world_pos:dist_to(player_pos)
                    local is_walkable = utility.is_point_walkeable(world_pos)
                    local cell_state = distance <= EXPLORATION_RADIUS and 
                        (is_walkable and CELL_EXPLORED or CELL_NON_WALKABLE) or
                        (is_walkable and CELL_UNEXPLORED or CELL_NON_WALKABLE)
                    chunk:set(x, y, cell_state)
                end
            end

            update_frontier(cx, cy)
        end
    end
end

local function update_exploration_targets()
    exploration_targets = PriorityQueue.new()
    local player_pos = get_player_position()
    if not player_pos then return end

    for _, chunk in pairs(frontier_chunks) do
        local chunk_obj = exploration_quadtree:get(chunk.x, chunk.y)
        if chunk_obj then
            local score = evaluate_chunk(chunk_obj, chunk.x, chunk.y, player_pos)
            exploration_targets:push({x = chunk.x, y = chunk.y}, -score)
        end
    end
end

local function find_exploration_target()
    while true do
        local target, _ = exploration_targets:pop()
        if not target then return nil end
        local chunk = exploration_quadtree:get(target.x, target.y)
        if chunk and chunk:is_unexplored() and not manage_recently_visited(target.x, target.y, false) then
            manage_recently_visited(target.x, target.y, true)
            local player_pos = get_player_position()
            if not player_pos then return nil end
            return vec3:new(target.x * CHUNK_SIZE + CHUNK_SIZE / 2, target.y * CHUNK_SIZE + CHUNK_SIZE / 2, player_pos:z())
        end
    end
end

local function update_exploration()
    if not current_target then
        update_exploration_grid()
        update_exploration_targets()
        current_target = find_exploration_target()
        if current_target then
            current_target = utility.set_height_of_valid_position(current_target)
            return true
        end
        return false
    else
        local player_pos = get_player_position()
        if not player_pos then return false end
        
        -- Check if we've reached the current target
        local distance = player_pos:dist_to_ignore_z(current_target)
        if distance < 3.0 then
            current_target = nil
            return false
        end
        return true
    end
end

local function clear_target()
    current_target = nil
end

return {
    update_exploration = update_exploration,
    current_target = function() return current_target end,
    clear_target = clear_target
}