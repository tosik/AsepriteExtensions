-- Palette Editor Plugin for Aseprite
-- Edit indexed palette colors with live preview

local plugin

-- Save palette state (for applying final changes)
local function savePaletteState(sprite)
    local palette = sprite.palettes[1]
    local state = {}
    for i = 0, #palette - 1 do
        local c = palette:getColor(i)
        state[i] = Color{ r = c.red, g = c.green, b = c.blue, a = c.alpha }
    end
    return state
end

-- Apply palette state
local function applyPaletteState(sprite, state)
    local palette = sprite.palettes[1]
    for i, c in pairs(state) do
        palette:setColor(i, c)
    end
    app.refresh()
end

-- Build color array for shades widget
local function buildColorArray(sprite)
    local palette = sprite.palettes[1]
    local colors = {}
    for i = 0, #palette - 1 do
        local c = palette:getColor(i)
        table.insert(colors, Color{ r = c.red, g = c.green, b = c.blue, a = c.alpha })
    end
    return colors
end

-- Main dialog
local function showPaletteEditor()
    local sprite = app.activeSprite

    if not sprite then
        app.alert("No active sprite!")
        return
    end

    if sprite.colorMode ~= ColorMode.INDEXED then
        app.alert("This tool only works in Indexed color mode.\nUse Sprite > Color Mode > Indexed to convert.")
        return
    end

    local palette = sprite.palettes[1]
    local colorArray = buildColorArray(sprite)
    local originalPalette = savePaletteState(sprite)
    local previewUndoCount = 0

    -- Default to foreground color index if valid
    local fgColor = app.fgColor
    local selectedIndex = 0
    if fgColor.index and fgColor.index >= 0 and fgColor.index < #palette then
        selectedIndex = fgColor.index
    end
    local currentColor = palette:getColor(selectedIndex)

    local dlg = Dialog{
        title = "Palette Editor",
        onclose = function()
            -- If closed without Apply, undo all preview changes
            if previewUndoCount > 0 then
                for i = 1, previewUndoCount do
                    app.undo()
                end
            end
        end
    }

    dlg:label{ text = "Click a color to select:" }

    dlg:shades{
        id = "colorPicker",
        colors = colorArray,
        mode = "pick",
        onclick = function(ev)
            if ev.button == MouseButton.LEFT then
                -- Find index by matching color
                for i = 0, #palette - 1 do
                    local c = palette:getColor(i)
                    if ev.color and c.red == ev.color.red and c.green == ev.color.green
                       and c.blue == ev.color.blue and c.alpha == ev.color.alpha then
                        selectedIndex = i
                        break
                    end
                end
                local c = palette:getColor(selectedIndex)
                dlg:modify{ id = "colorLabel", text = "Color Index: " .. selectedIndex }
                dlg:modify{ id = "colorValue", color = c }
            end
        end
    }

    dlg:label{
        id = "colorLabel",
        text = "Color Index: " .. selectedIndex
    }

    dlg:color{
        id = "colorValue",
        label = "Color:",
        color = currentColor,
        onchange = function()
            local c = dlg.data.colorValue
            app.transaction("Preview", function()
                palette:setColor(selectedIndex, Color{ r = c.red, g = c.green, b = c.blue, a = c.alpha })
            end)
            previewUndoCount = previewUndoCount + 1
            colorArray[selectedIndex + 1] = c
            dlg:modify{ id = "colorPicker", colors = colorArray }
            app.refresh()
        end
    }

    dlg:separator()

    dlg:button{
        id = "revert",
        text = "Revert This Color",
        onclick = function()
            if originalPalette[selectedIndex] then
                local c = originalPalette[selectedIndex]
                app.transaction("Preview", function()
                    palette:setColor(selectedIndex, c)
                end)
                previewUndoCount = previewUndoCount + 1
                dlg:modify{ id = "colorValue", color = c }
                colorArray[selectedIndex + 1] = Color{ r = c.red, g = c.green, b = c.blue, a = c.alpha }
                dlg:modify{ id = "colorPicker", colors = colorArray }
                app.refresh()
            end
        end
    }

    dlg:button{
        id = "revertAll",
        text = "Revert All",
        onclick = function()
            -- Undo all preview changes
            for i = 1, previewUndoCount do
                app.undo()
            end
            previewUndoCount = 0
            -- Update colorArray from original palette
            for i = 0, #palette - 1 do
                if originalPalette[i] then
                    local c = originalPalette[i]
                    colorArray[i + 1] = Color{ r = c.red, g = c.green, b = c.blue, a = c.alpha }
                end
            end
            dlg:modify{ id = "colorPicker", colors = colorArray }
            if originalPalette[selectedIndex] then
                local c = originalPalette[selectedIndex]
                dlg:modify{ id = "colorValue", color = c }
            end
        end
    }

    dlg:separator()

    dlg:button{
        id = "apply",
        text = "Apply",
        onclick = function()
            -- Save current palette state before undoing previews
            local finalPalette = savePaletteState(sprite)

            -- Undo all preview changes
            for i = 1, previewUndoCount do
                app.undo()
            end
            previewUndoCount = 0

            -- Apply final state in one transaction
            app.transaction("Palette Edit", function()
                applyPaletteState(sprite, finalPalette)
            end)

            dlg:close()
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
        id = "PaletteEditor",
        title = "Palette Editor...",
        group = "sprite_color",
        onclick = showPaletteEditor
    }
end

function exit(p)
end
