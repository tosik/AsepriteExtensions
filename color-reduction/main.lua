-- Color Reduction Plugin for Aseprite
-- Merge similar colors within a distance threshold

local plugin

-- Calculate color distance (Euclidean distance in RGB space)
local function colorDistance(c1, c2)
    local dr = c1.r - c2.r
    local dg = c1.g - c2.g
    local db = c1.b - c2.b
    return math.sqrt(dr * dr + dg * dg + db * db)
end

-- Union-Find data structure for grouping colors
local function createUnionFind(n)
    local parent = {}
    local rank = {}
    for i = 1, n do
        parent[i] = i
        rank[i] = 0
    end

    local function find(x)
        if parent[x] ~= x then
            parent[x] = find(parent[x])
        end
        return parent[x]
    end

    local function union(x, y)
        local px, py = find(x), find(y)
        if px == py then return end
        if rank[px] < rank[py] then
            parent[px] = py
        elseif rank[px] > rank[py] then
            parent[py] = px
        else
            parent[py] = px
            rank[px] = rank[px] + 1
        end
    end

    return { find = find, union = union }
end

-- Collect all unique colors from sprite (all cels, all frames)
local function collectColors(sprite)
    local colors = {}
    local colorSet = {}

    for _, frame in ipairs(sprite.frames) do
        for _, layer in ipairs(sprite.layers) do
            if layer.isVisible and not layer.isGroup then
                local cel = layer:cel(frame)
                if cel then
                    local image = cel.image
                    for it in image:pixels() do
                        local pixel = it()

                        if sprite.colorMode == ColorMode.RGB then
                            local a = app.pixelColor.rgbaA(pixel)
                            if a > 0 then
                                local r = app.pixelColor.rgbaR(pixel)
                                local g = app.pixelColor.rgbaG(pixel)
                                local b = app.pixelColor.rgbaB(pixel)
                                local key = string.format("%d,%d,%d,%d", r, g, b, a)
                                if not colorSet[key] then
                                    colorSet[key] = true
                                    table.insert(colors, { r = r, g = g, b = b, a = a, key = key })
                                end
                            end
                        elseif sprite.colorMode == ColorMode.INDEXED then
                            local idx = pixel
                            if idx ~= image.spec.transparentColor then
                                local key = tostring(idx)
                                if not colorSet[key] then
                                    colorSet[key] = true
                                    local color = sprite.palettes[1]:getColor(idx)
                                    table.insert(colors, {
                                        r = color.red,
                                        g = color.green,
                                        b = color.blue,
                                        a = color.alpha,
                                        index = idx,
                                        key = key
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return colors
end

-- Group colors by distance threshold
local function groupColors(colors, threshold)
    local n = #colors
    if n == 0 then return {} end

    local uf = createUnionFind(n)

    -- Compare all pairs and union if within threshold
    for i = 1, n do
        for j = i + 1, n do
            if colorDistance(colors[i], colors[j]) <= threshold then
                uf.union(i, j)
            end
        end
    end

    -- Group by root
    local groups = {}
    for i = 1, n do
        local root = uf.find(i)
        if not groups[root] then
            groups[root] = {}
        end
        table.insert(groups[root], colors[i])
    end

    return groups
end

-- Calculate average color for a group
local function averageColor(group)
    local sumR, sumG, sumB, sumA = 0, 0, 0, 0
    for _, c in ipairs(group) do
        sumR = sumR + c.r
        sumG = sumG + c.g
        sumB = sumB + c.b
        sumA = sumA + c.a
    end
    local n = #group
    return {
        r = math.floor(sumR / n),
        g = math.floor(sumG / n),
        b = math.floor(sumB / n),
        a = math.floor(sumA / n)
    }
end

-- Build color mapping from old colors to new colors
local function buildColorMapping(colors, groups)
    local mapping = {}

    for _, group in pairs(groups) do
        local avgColor = averageColor(group)
        for _, c in ipairs(group) do
            mapping[c.key] = avgColor
        end
    end

    return mapping
end

-- Apply color reduction to RGB sprite
local function applyColorReductionRGB(sprite, mapping, newPalette)
    -- First, change to indexed mode with the new palette
    app.command.ChangePixelFormat{
        format = "indexed",
        dithering = "none"
    }

    -- Build a mapping from RGBA to palette index
    local colorToIndex = {}
    for i = 0, #newPalette - 1 do
        local c = newPalette:getColor(i)
        local key = string.format("%d,%d,%d,%d", c.red, c.green, c.blue, c.alpha)
        colorToIndex[key] = i
    end

    -- Update each cel
    for _, frame in ipairs(sprite.frames) do
        for _, layer in ipairs(sprite.layers) do
            if not layer.isGroup then
                local cel = layer:cel(frame)
                if cel then
                    local image = cel.image
                    local newImage = image:clone()

                    for it in newImage:pixels() do
                        local idx = it()
                        if idx ~= newImage.spec.transparentColor then
                            local oldColor = sprite.palettes[1]:getColor(idx)
                            local oldKey = string.format("%d,%d,%d,%d",
                                oldColor.red, oldColor.green, oldColor.blue, oldColor.alpha)

                            -- Find the mapped color
                            local newColor = mapping[oldKey]
                            if newColor then
                                local newKey = string.format("%d,%d,%d,%d",
                                    newColor.r, newColor.g, newColor.b, newColor.a)
                                local newIdx = colorToIndex[newKey]
                                if newIdx then
                                    it(newIdx)
                                end
                            end
                        end
                    end

                    cel.image = newImage
                end
            end
        end
    end
end

-- Apply color reduction to Indexed sprite
local function applyColorReductionIndexed(sprite, colors, groups)
    -- Build mapping from old index to new index
    local indexMapping = {}
    local newColors = {}
    local newIndex = 0

    for _, group in pairs(groups) do
        local avgColor = averageColor(group)
        table.insert(newColors, avgColor)
        for _, c in ipairs(group) do
            indexMapping[c.index] = newIndex
        end
        newIndex = newIndex + 1
    end

    -- Update palette
    local palette = sprite.palettes[1]
    palette:resize(#newColors + 1)  -- +1 for transparent

    -- Set transparent color at index 0
    palette:setColor(0, Color{ r = 0, g = 0, b = 0, a = 0 })

    -- Shift indices by 1 to account for transparent
    for i, c in ipairs(newColors) do
        palette:setColor(i, Color{ r = c.r, g = c.g, b = c.b, a = c.a })
    end

    -- Update index mapping to account for transparent at 0
    local adjustedMapping = {}
    for oldIdx, newIdx in pairs(indexMapping) do
        adjustedMapping[oldIdx] = newIdx + 1
    end

    -- Update each cel
    for _, frame in ipairs(sprite.frames) do
        for _, layer in ipairs(sprite.layers) do
            if not layer.isGroup then
                local cel = layer:cel(frame)
                if cel then
                    local image = cel.image
                    local newImage = image:clone()

                    for it in newImage:pixels() do
                        local oldIdx = it()
                        if oldIdx ~= image.spec.transparentColor then
                            local newIdx = adjustedMapping[oldIdx]
                            if newIdx then
                                it(newIdx)
                            end
                        end
                    end

                    cel.image = newImage
                end
            end
        end
    end
end

-- Apply preview (palette only, no pixel remapping)
local function applyPreviewIndexed(sprite, colors, groups)
    local palette = sprite.palettes[1]

    -- Build mapping from old index to new color
    for _, group in pairs(groups) do
        local avgColor = averageColor(group)
        for _, c in ipairs(group) do
            if c.index then
                palette:setColor(c.index, Color{ r = avgColor.r, g = avgColor.g, b = avgColor.b, a = avgColor.a })
            end
        end
    end
    app.refresh()
end

-- Main dialog
local function showColorReductionDialog()
    local sprite = app.activeSprite

    if not sprite then
        app.alert("No active sprite!")
        return
    end

    if sprite.colorMode == ColorMode.GRAY then
        app.alert("Grayscale mode is not supported. Please convert to RGB or Indexed first.")
        return
    end

    if sprite.colorMode == ColorMode.RGB then
        app.alert("Live preview only works in Indexed mode.\nPlease convert to Indexed first (Sprite > Color Mode > Indexed).")
        return
    end

    local colors = collectColors(sprite)
    local originalColorCount = #colors
    local previewUndoCount = 0

    local dlg = Dialog{
        title = "Color Reduction",
        onclose = function()
            -- If closed without Apply, undo all preview changes
            if previewUndoCount > 0 then
                for i = 1, previewUndoCount do
                    app.undo()
                end
            end
        end
    }

    dlg:label{
        id = "colorCount",
        label = "Colors:",
        text = originalColorCount .. " -> " .. originalColorCount
    }

    dlg:slider{
        id = "threshold",
        label = "Distance Threshold:",
        min = 1,
        max = 100,
        value = 16,
        onchange = function()
            -- Live preview on slider change
            local threshold = dlg.data.threshold
            local groups = groupColors(colors, threshold)
            local count = 0
            for _ in pairs(groups) do count = count + 1 end

            dlg:modify{ id = "colorCount", text = originalColorCount .. " -> " .. count }

            -- Apply preview in a transaction so we can undo it
            app.transaction("Preview", function()
                applyPreviewIndexed(sprite, colors, groups)
            end)
            previewUndoCount = previewUndoCount + 1
        end
    }

    dlg:label{
        text = "(Higher = more colors merged)"
    }

    dlg:separator()

    dlg:button{
        id = "revert",
        text = "Revert",
        onclick = function()
            -- Undo all preview changes
            for i = 1, previewUndoCount do
                app.undo()
            end
            previewUndoCount = 0
            dlg:modify{ id = "colorCount", text = originalColorCount .. " -> " .. originalColorCount }
        end
    }

    dlg:button{
        id = "apply",
        text = "Apply",
        onclick = function()
            -- Apply actual color reduction with pixel remapping
            local threshold = dlg.data.threshold
            local groups = groupColors(colors, threshold)
            local count = 0
            for _ in pairs(groups) do count = count + 1 end

            -- Undo all preview changes first
            for i = 1, previewUndoCount do
                app.undo()
            end
            previewUndoCount = 0

            -- Apply actual reduction in a transaction
            app.transaction("Color Reduction", function()
                applyColorReductionIndexed(sprite, colors, groups)
            end)

            dlg:close()
            app.refresh()
            app.alert("Reduced from " .. originalColorCount .. " to " .. count .. " colors!")
        end
    }

    dlg:button{
        id = "cancel",
        text = "Cancel",
        onclick = function()
            -- Undo all preview changes
            for i = 1, previewUndoCount do
                app.undo()
            end
            previewUndoCount = 0
            dlg:close()
        end
    }

    dlg:show{ wait = false }
end

-- Plugin initialization
function init(p)
    plugin = p

    plugin:newCommand{
        id = "ColorReduction",
        title = "Color Reduction...",
        group = "sprite_color",
        onclick = showColorReductionDialog
    }
end

function exit(p)
end
