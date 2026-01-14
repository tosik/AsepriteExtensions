-- Outline Tool Plugin for Aseprite
-- Draws outline around non-transparent pixels

local plugin

-- Check if a pixel is transparent
local function isTransparent(image, x, y)
    if x < 0 or y < 0 or x >= image.width or y >= image.height then
        return true
    end

    local pixel = image:getPixel(x, y)

    if image.colorMode == ColorMode.RGB then
        local alpha = app.pixelColor.rgbaA(pixel)
        return alpha == 0
    elseif image.colorMode == ColorMode.GRAY then
        local alpha = app.pixelColor.grayaA(pixel)
        return alpha == 0
    elseif image.colorMode == ColorMode.INDEXED then
        return pixel == image.spec.transparentColor
    end

    return false
end

-- Check if a pixel is non-transparent
local function isOpaque(image, x, y)
    return not isTransparent(image, x, y)
end

-- Find the closest color to black in the palette (ignoring transparent colors)
local function findClosestBlack(palette)
    local closestIndex = 1  -- Default to index 1 (often black in most palettes)
    local closestDistance = math.huge

    for i = 0, #palette - 1 do
        local color = palette:getColor(i)
        -- Skip colors with low alpha (transparent or semi-transparent)
        if color.alpha >= 128 then
            -- Calculate distance to black (0, 0, 0)
            local distance = color.red * color.red + color.green * color.green + color.blue * color.blue
            if distance < closestDistance then
                closestDistance = distance
                closestIndex = i
            end
        end
    end

    return closestIndex
end

-- Get black color based on color mode
local function getBlackColor(sprite)
    if sprite.colorMode == ColorMode.RGB then
        return app.pixelColor.rgba(0, 0, 0, 255)
    elseif sprite.colorMode == ColorMode.GRAY then
        return app.pixelColor.graya(0, 255)
    elseif sprite.colorMode == ColorMode.INDEXED then
        return findClosestBlack(sprite.palettes[1])
    end
    return 0
end

-- 4-directional neighbors (no diagonals)
local directions = {
    { 0, -1 }, -- up
    { 0,  1 }, -- down
    { -1, 0 }, -- left
    { 1,  0 }, -- right
}

-- Draw outline on the image
local function drawOutline(sprite, cel, outlineType)
    local image = cel.image
    local blackColor = getBlackColor(sprite)

    -- Clone the image for modification
    local newImage = image:clone()

    -- Collect pixels to paint
    local pixelsToPaint = {}

    for y = 0, image.height - 1 do
        for x = 0, image.width - 1 do
            if outlineType == "outer" then
                -- Outer outline: transparent pixels adjacent to opaque pixels
                if isTransparent(image, x, y) then
                    for _, dir in ipairs(directions) do
                        local nx, ny = x + dir[1], y + dir[2]
                        if isOpaque(image, nx, ny) then
                            table.insert(pixelsToPaint, { x = x, y = y })
                            break
                        end
                    end
                end
            else
                -- Inner outline: opaque pixels adjacent to transparent pixels
                if isOpaque(image, x, y) then
                    for _, dir in ipairs(directions) do
                        local nx, ny = x + dir[1], y + dir[2]
                        if isTransparent(image, nx, ny) then
                            table.insert(pixelsToPaint, { x = x, y = y })
                            break
                        end
                    end
                end
            end
        end
    end

    -- Paint the outline pixels
    for _, p in ipairs(pixelsToPaint) do
        newImage:drawPixel(p.x, p.y, blackColor)
    end

    return newImage
end

-- Main dialog
local function showOutlineDialog()
    local sprite = app.activeSprite

    if not sprite then
        app.alert("No active sprite!")
        return
    end

    local layer = app.activeLayer

    if not layer then
        app.alert("No active layer!")
        return
    end

    if layer.isGroup then
        app.alert("Cannot apply to a group layer. Please select a normal layer.")
        return
    end

    local cel = app.activeCel

    if not cel then
        app.alert("No active cel on this layer/frame!")
        return
    end

    local dlg = Dialog("Outline Tool")

    dlg:combobox{
        id = "outlineType",
        label = "Outline Type:",
        options = { "Outer (around sprite)", "Inner (inside sprite)" }
    }

    dlg:button{ id = "apply", text = "Apply" }
    dlg:button{ id = "cancel", text = "Cancel" }

    dlg:show()

    if dlg.data.apply then
        local outlineType = "outer"
        if dlg.data.outlineType == "Inner (inside sprite)" then
            outlineType = "inner"
        end

        app.transaction(function()
            local newImage = drawOutline(sprite, cel, outlineType)
            cel.image = newImage
        end)

        app.refresh()
    end
end

-- Plugin initialization
function init(p)
    plugin = p

    plugin:newCommand{
        id = "OutlineTool",
        title = "Draw Outline...",
        group = "cel_popup_links",
        onclick = showOutlineDialog
    }
end

function exit(p)
end
