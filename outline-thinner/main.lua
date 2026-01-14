-- Outline Thinner Plugin for Aseprite
-- Thin 2-pixel outlines to 1-pixel

local plugin

-- Check if a pixel is transparent
local function isTransparent(image, x, y, transparentColor)
    if x < 0 or y < 0 or x >= image.width or y >= image.height then
        return true  -- Out of bounds = transparent
    end
    return image:getPixel(x, y) == transparentColor
end

-- Check if a pixel is opaque (outline candidate)
local function isOpaque(image, x, y, transparentColor)
    if x < 0 or y < 0 or x >= image.width or y >= image.height then
        return false
    end
    return image:getPixel(x, y) ~= transparentColor
end

-- Check if pixel is on the outline (opaque and adjacent to transparent)
local function isOutlinePixel(image, x, y, transparentColor)
    if not isOpaque(image, x, y, transparentColor) then
        return false
    end
    -- Check 4-connected neighbors for transparent
    return isTransparent(image, x-1, y, transparentColor) or
           isTransparent(image, x+1, y, transparentColor) or
           isTransparent(image, x, y-1, transparentColor) or
           isTransparent(image, x, y+1, transparentColor)
end

-- Get 3x3 neighborhood pattern (true = opaque, false = transparent)
local function getNeighborhood(image, cx, cy, transparentColor)
    local n = {}
    for dy = -1, 1 do
        n[dy] = {}
        for dx = -1, 1 do
            n[dy][dx] = isOpaque(image, cx + dx, cy + dy, transparentColor)
        end
    end
    return n
end

-- Count opaque 4-neighbors
local function countOpaque4Neighbors(n)
    local count = 0
    if n[-1][0] then count = count + 1 end  -- top
    if n[1][0] then count = count + 1 end   -- bottom
    if n[0][-1] then count = count + 1 end  -- left
    if n[0][1] then count = count + 1 end   -- right
    return count
end

-- Count transparent 4-neighbors
local function countTransparent4Neighbors(n)
    local count = 0
    if not n[-1][0] then count = count + 1 end
    if not n[1][0] then count = count + 1 end
    if not n[0][-1] then count = count + 1 end
    if not n[0][1] then count = count + 1 end
    return count
end

-- Check if removing center pixel would disconnect the outline
-- Uses 8-connectivity check for remaining opaque pixels
local function wouldDisconnect(n)
    -- If we have only 0 or 1 opaque neighbor, removing is safe
    local opaque4 = countOpaque4Neighbors(n)
    if opaque4 <= 1 then
        return false
    end

    -- Check if opaque neighbors are connected to each other (without center)
    -- Build a list of opaque neighbor positions
    local positions = {}
    for dy = -1, 1 do
        for dx = -1, 1 do
            if not (dx == 0 and dy == 0) and n[dy][dx] then
                table.insert(positions, {dx, dy})
            end
        end
    end

    if #positions <= 1 then
        return false
    end

    -- Check 8-connectivity between neighbors
    -- Two positions are 8-adjacent if |dx| <= 1 and |dy| <= 1
    local visited = {[1] = true}
    local queue = {1}

    while #queue > 0 do
        local current = table.remove(queue)
        local cx, cy = positions[current][1], positions[current][2]

        for i, pos in ipairs(positions) do
            if not visited[i] then
                local px, py = pos[1], pos[2]
                -- Check if 8-adjacent
                if math.abs(cx - px) <= 1 and math.abs(cy - py) <= 1 then
                    visited[i] = true
                    table.insert(queue, i)
                end
            end
        end
    end

    -- Check if all positions were visited
    for i = 1, #positions do
        if not visited[i] then
            return true  -- Would disconnect
        end
    end

    return false
end

-- Check if pixel is part of a diagonal 2-thick pattern
-- Returns true if this pixel can be removed from a diagonal pair
local function isDiagonalRemovable(image, x, y, transparentColor)
    if not isOpaque(image, x, y, transparentColor) then
        return false
    end

    -- Check 4 diagonal 2x2 patterns where this pixel is the "outer" one
    -- Pattern 1: pixel at top-left of 2x2, diagonal goes down-right
    --   X O    <- X is current pixel, can remove if O,O,O are opaque
    --   O O       and X has more transparent neighbors
    local patterns = {
        -- {dx, dy for the 3 other pixels in 2x2}, {which diagonal neighbor to check}
        {{0,1}, {1,0}, {1,1}},   -- current is top-left
        {{0,-1}, {1,0}, {1,-1}}, -- current is bottom-left
        {{0,1}, {-1,0}, {-1,1}}, -- current is top-right
        {{0,-1}, {-1,0}, {-1,-1}} -- current is bottom-right
    }

    for _, pattern in ipairs(patterns) do
        local allOpaque = true
        local diagonalOpaque = false

        for i, delta in ipairs(pattern) do
            local nx, ny = x + delta[1], y + delta[2]
            if not isOpaque(image, nx, ny, transparentColor) then
                allOpaque = false
                break
            end
            -- The 3rd position is the diagonal
            if i == 3 then
                diagonalOpaque = true
            end
        end

        if allOpaque and diagonalOpaque then
            -- Check if current pixel has more transparent neighbors than diagonal
            local myTrans = 0
            local diagX, diagY = x + pattern[3][1], y + pattern[3][2]
            local diagTrans = 0

            -- Count transparent 8-neighbors
            for dy = -1, 1 do
                for dx = -1, 1 do
                    if not (dx == 0 and dy == 0) then
                        if isTransparent(image, x + dx, y + dy, transparentColor) then
                            myTrans = myTrans + 1
                        end
                        if isTransparent(image, diagX + dx, diagY + dy, transparentColor) then
                            diagTrans = diagTrans + 1
                        end
                    end
                end
            end

            -- Remove the one with more transparent neighbors (more outer)
            if myTrans > diagTrans then
                return true
            end
        end
    end

    return false
end

-- Check for stair-step diagonal pattern (2 pixels wide)
local function isStairStepRemovable(image, x, y, transparentColor)
    if not isOpaque(image, x, y, transparentColor) then
        return false
    end

    -- Look for patterns like:
    --   . X O      . O X
    --   . O O  or  . O O   (and rotations)
    --   . . O      . O .

    -- Horizontal stair patterns
    local stairPatterns = {
        -- Going down-right, current pixel is upper of pair
        {check = {{1,0}, {1,1}}, transparent = {{0,-1}, {-1,0}, {-1,-1}}},
        -- Going down-right, current pixel is left of pair
        {check = {{0,1}, {1,1}}, transparent = {{-1,0}, {0,-1}, {-1,-1}}},
        -- Going down-left
        {check = {{-1,0}, {-1,1}}, transparent = {{0,-1}, {1,0}, {1,-1}}},
        {check = {{0,1}, {-1,1}}, transparent = {{1,0}, {0,-1}, {1,-1}}},
        -- Going up-right
        {check = {{1,0}, {1,-1}}, transparent = {{0,1}, {-1,0}, {-1,1}}},
        {check = {{0,-1}, {1,-1}}, transparent = {{-1,0}, {0,1}, {-1,1}}},
        -- Going up-left
        {check = {{-1,0}, {-1,-1}}, transparent = {{0,1}, {1,0}, {1,1}}},
        {check = {{0,-1}, {-1,-1}}, transparent = {{1,0}, {0,1}, {1,1}}},
    }

    for _, pattern in ipairs(stairPatterns) do
        local checkOk = true
        for _, delta in ipairs(pattern.check) do
            if not isOpaque(image, x + delta[1], y + delta[2], transparentColor) then
                checkOk = false
                break
            end
        end

        if checkOk then
            local hasTransparent = false
            for _, delta in ipairs(pattern.transparent) do
                if isTransparent(image, x + delta[1], y + delta[2], transparentColor) then
                    hasTransparent = true
                    break
                end
            end

            if hasTransparent then
                return true
            end
        end
    end

    return false
end

-- Check if pixel is a removable outline pixel
-- Removable = on outline, part of thick area, removal doesn't disconnect
local function isRemovable(image, x, y, transparentColor)
    -- Check diagonal patterns first
    if isDiagonalRemovable(image, x, y, transparentColor) then
        return true
    end

    if isStairStepRemovable(image, x, y, transparentColor) then
        return true
    end

    -- Must be on the outline
    if not isOutlinePixel(image, x, y, transparentColor) then
        return false
    end

    local n = getNeighborhood(image, x, y, transparentColor)

    -- Must have at least 2 opaque 4-neighbors (otherwise it's already thin)
    local opaque4 = countOpaque4Neighbors(n)
    if opaque4 < 2 then
        return false
    end

    -- Must have at least 1 transparent 4-neighbor (on the edge)
    local trans4 = countTransparent4Neighbors(n)
    if trans4 < 1 then
        return false
    end

    -- Check specific patterns for 2-pixel thick outlines
    -- Pattern: pixel has opaque neighbor that also touches transparent
    -- This means we're on a thick part of the outline

    local hasOutlineNeighbor = false

    -- Check each 4-neighbor
    local dirs = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
    for _, dir in ipairs(dirs) do
        local nx, ny = x + dir[1], y + dir[2]
        if isOutlinePixel(image, nx, ny, transparentColor) then
            hasOutlineNeighbor = true
            break
        end
    end

    if not hasOutlineNeighbor then
        return false
    end

    -- Check if removal would disconnect
    if wouldDisconnect(n) then
        return false
    end

    return true
end

-- Perform one pass of thinning, returns number of pixels removed
local function thinPass(image, transparentColor)
    local toRemove = {}

    -- Find all removable pixels
    for y = 0, image.height - 1 do
        for x = 0, image.width - 1 do
            if isRemovable(image, x, y, transparentColor) then
                table.insert(toRemove, {x, y})
            end
        end
    end

    -- Sort by number of transparent neighbors (remove outer pixels first)
    table.sort(toRemove, function(a, b)
        local n1 = getNeighborhood(image, a[1], a[2], transparentColor)
        local n2 = getNeighborhood(image, b[1], b[2], transparentColor)
        return countTransparent4Neighbors(n1) > countTransparent4Neighbors(n2)
    end)

    -- Remove pixels one by one, re-checking each time
    local removed = 0
    for _, pos in ipairs(toRemove) do
        local x, y = pos[1], pos[2]
        -- Re-check if still removable (previous removals may have changed things)
        if isRemovable(image, x, y, transparentColor) then
            image:drawPixel(x, y, transparentColor)
            removed = removed + 1
        end
    end

    return removed
end

-- Main thinning function
local function thinOutline(sprite, maxIterations)
    maxIterations = maxIterations or 10

    local cel = app.activeCel
    if not cel then
        app.alert("No active cel!")
        return 0
    end

    local image = cel.image:clone()
    local transparentColor = image.spec.transparentColor

    local totalRemoved = 0

    for i = 1, maxIterations do
        local removed = thinPass(image, transparentColor)
        totalRemoved = totalRemoved + removed
        if removed == 0 then
            break
        end
    end

    if totalRemoved > 0 then
        cel.image = image
    end

    return totalRemoved
end

-- Main dialog
local function showOutlineThinner()
    local sprite = app.activeSprite

    if not sprite then
        app.alert("No active sprite!")
        return
    end

    if sprite.colorMode ~= ColorMode.INDEXED then
        app.alert("This tool works best in Indexed color mode.\nUse Sprite > Color Mode > Indexed to convert.")
        return
    end

    local dlg = Dialog("Outline Thinner")

    dlg:slider{
        id = "iterations",
        label = "Max Iterations:",
        min = 1,
        max = 20,
        value = 5
    }

    dlg:label{
        text = "(More iterations = more thinning)"
    }

    dlg:button{ id = "apply", text = "Apply" }
    dlg:button{ id = "cancel", text = "Cancel" }

    dlg:show()

    if dlg.data.apply then
        app.transaction("Thin Outline", function()
            local removed = thinOutline(sprite, dlg.data.iterations)
            app.refresh()
            app.alert("Removed " .. removed .. " pixels")
        end)
    end
end

-- Plugin initialization
function init(p)
    plugin = p

    plugin:newCommand{
        id = "OutlineThinner",
        title = "Outline Thinner...",
        group = "cel_popup_links",
        onclick = showOutlineThinner
    }
end

function exit(p)
end
