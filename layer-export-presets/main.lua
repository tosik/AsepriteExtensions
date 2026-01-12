-- Layer Export Presets Plugin for Aseprite
-- Allows configuring layer visibility patterns and batch exporting

local plugin

-- Helper function to get all layers recursively (including nested groups)
local function getAllLayers(layers, result, prefix)
    result = result or {}
    prefix = prefix or ""
    for _, layer in ipairs(layers) do
        local fullName = prefix .. layer.name
        table.insert(result, { layer = layer, fullName = fullName })
        if layer.isGroup then
            getAllLayers(layer.layers, result, fullName .. "/")
        end
    end
    return result
end

-- Save original visibility states
local function saveVisibility(sprite)
    local allLayers = getAllLayers(sprite.layers)
    local states = {}
    for _, item in ipairs(allLayers) do
        states[item.fullName] = item.layer.isVisible
    end
    return states
end

-- Restore visibility states
local function restoreVisibility(sprite, states)
    local allLayers = getAllLayers(sprite.layers)
    for _, item in ipairs(allLayers) do
        if states[item.fullName] ~= nil then
            item.layer.isVisible = states[item.fullName]
        end
    end
end

-- Apply preset visibility
local function applyPresetVisibility(sprite, preset)
    local allLayers = getAllLayers(sprite.layers)
    for _, item in ipairs(allLayers) do
        local isVisible = preset.layers[item.fullName]
        if isVisible ~= nil then
            item.layer.isVisible = isVisible
        else
            item.layer.isVisible = false
        end
    end
end

-- Simple JSON encoder for presets
local function encodeJSON(presets)
    local result = "[\n"
    for i, preset in ipairs(presets) do
        result = result .. "  {\n"
        result = result .. '    "name": "' .. (preset.name or "") .. '",\n'
        result = result .. '    "exportName": "' .. (preset.exportName or "") .. '",\n'
        result = result .. '    "layers": {\n'

        local layerEntries = {}
        for layerName, visible in pairs(preset.layers) do
            table.insert(layerEntries, '      "' .. layerName .. '": ' .. tostring(visible))
        end
        result = result .. table.concat(layerEntries, ",\n") .. "\n"

        result = result .. "    }\n"
        result = result .. "  }"
        if i < #presets then
            result = result .. ","
        end
        result = result .. "\n"
    end
    result = result .. "]"
    return result
end

-- Simple JSON decoder for presets
local function decodeJSON(jsonStr)
    local presets = {}
    jsonStr = jsonStr:gsub("[\n\r\t]", " ")

    for presetStr in jsonStr:gmatch("{[^{}]*{[^{}]*}[^{}]*}") do
        local preset = {
            name = "",
            exportName = "",
            layers = {}
        }

        local name = presetStr:match('"name"%s*:%s*"([^"]*)"')
        if name then preset.name = name end

        local exportName = presetStr:match('"exportName"%s*:%s*"([^"]*)"')
        if exportName then preset.exportName = exportName end

        local layersStr = presetStr:match('"layers"%s*:%s*{([^}]*)}')
        if layersStr then
            for layerName, visible in layersStr:gmatch('"([^"]*)"%s*:%s*(%w+)') do
                preset.layers[layerName] = (visible == "true")
            end
        end

        table.insert(presets, preset)
    end

    return presets
end

-- Get auto-save JSON path for sprite
local function getAutoSavePath(sprite)
    local spriteDir = sprite.filename:match("^(.*[/\\])")
    local spriteName = sprite.filename:match("([^/\\]+)%.%w+$")
    if spriteDir and spriteName then
        return spriteDir .. spriteName .. ".presets.json"
    end
    return nil
end

-- Get presets for current sprite (with auto-load from JSON if preferences empty)
local function getPresetsForSprite(sprite)
    if not sprite or not sprite.filename or sprite.filename == "" then
        return {}
    end
    local prefs = plugin.preferences
    prefs.spritePresets = prefs.spritePresets or {}

    -- If no presets in preferences, try to load from JSON file
    if not prefs.spritePresets[sprite.filename] or #prefs.spritePresets[sprite.filename] == 0 then
        local autoSavePath = getAutoSavePath(sprite)
        if autoSavePath then
            local file = io.open(autoSavePath, "r")
            if file then
                local content = file:read("*all")
                file:close()
                local loadedPresets = decodeJSON(content)
                if #loadedPresets > 0 then
                    prefs.spritePresets[sprite.filename] = loadedPresets
                end
            end
        end
    end

    prefs.spritePresets[sprite.filename] = prefs.spritePresets[sprite.filename] or {}
    return prefs.spritePresets[sprite.filename]
end

-- Save presets for current sprite (also auto-saves to JSON)
local function savePresetsForSprite(sprite, presets)
    if not sprite or not sprite.filename or sprite.filename == "" then
        return
    end
    local prefs = plugin.preferences
    prefs.spritePresets = prefs.spritePresets or {}
    prefs.spritePresets[sprite.filename] = presets

    -- Auto-save to JSON file
    local autoSavePath = getAutoSavePath(sprite)
    if autoSavePath and #presets > 0 then
        local file = io.open(autoSavePath, "w")
        if file then
            file:write(encodeJSON(presets))
            file:close()
        end
    end
end

-- Export presets to JSON file (manual)
local function exportPresetsToFile(sprite, presets)
    if #presets == 0 then
        app.alert("No presets to export!")
        return
    end

    local spriteDir = sprite.filename:match("^(.*[/\\])")
    local spriteName = sprite.filename:match("([^/\\]+)%.%w+$") or "presets"
    local defaultPath = (spriteDir or "") .. spriteName .. ".presets.json"

    local dlg = Dialog("Export Presets")
    dlg:file{
        id = "exportPath",
        label = "Save to:",
        save = true,
        filename = defaultPath,
        filetypes = { "json" }
    }
    dlg:button{ id = "ok", text = "Export" }
    dlg:button{ id = "cancel", text = "Cancel" }
    dlg:show()

    if dlg.data.ok and dlg.data.exportPath and dlg.data.exportPath ~= "" then
        local file = io.open(dlg.data.exportPath, "w")
        if file then
            file:write(encodeJSON(presets))
            file:close()
            app.alert("Presets exported to:\n" .. dlg.data.exportPath)
        else
            app.alert("Failed to write file!")
        end
    end
end

-- Import presets from JSON file
local function importPresetsFromFile(sprite)
    local spriteDir = sprite.filename:match("^(.*[/\\])") or ""

    local dlg = Dialog("Import Presets")
    dlg:file{
        id = "importPath",
        label = "Open:",
        open = true,
        filename = spriteDir,
        filetypes = { "json" }
    }
    dlg:button{ id = "ok", text = "Import" }
    dlg:button{ id = "cancel", text = "Cancel" }
    dlg:show()

    if dlg.data.ok and dlg.data.importPath and dlg.data.importPath ~= "" then
        local file = io.open(dlg.data.importPath, "r")
        if file then
            local content = file:read("*all")
            file:close()

            local importedPresets = decodeJSON(content)
            if #importedPresets > 0 then
                savePresetsForSprite(sprite, importedPresets)
                app.alert("Imported " .. #importedPresets .. " preset(s)!")
                return true
            else
                app.alert("No valid presets found in file!")
            end
        else
            app.alert("Failed to read file!")
        end
    end
    return false
end

-- Show preset editor dialog
local function showPresetEditor(sprite, preset, onSave)
    local allLayers = getAllLayers(sprite.layers)
    local dlg = Dialog("Edit Preset: " .. (preset.name or "New"))

    dlg:entry{
        id = "presetName",
        label = "Preset Name:",
        text = preset.name or ""
    }

    dlg:entry{
        id = "exportName",
        label = "Export Filename:",
        text = preset.exportName or ""
    }

    dlg:separator{ text = "Layer Visibility" }

    for i, item in ipairs(allLayers) do
        local isVisible = preset.layers[item.fullName]
        if isVisible == nil then
            isVisible = item.layer.isVisible
        end
        dlg:check{
            id = "layer_" .. i,
            label = item.fullName,
            selected = isVisible
        }
    end

    dlg:separator()
    dlg:button{ id = "save", text = "Save" }
    dlg:button{ id = "cancel", text = "Cancel" }
    dlg:show()

    if dlg.data.save then
        local newPreset = {
            name = dlg.data.presetName,
            exportName = dlg.data.exportName,
            layers = {}
        }

        for i, item in ipairs(allLayers) do
            newPreset.layers[item.fullName] = dlg.data["layer_" .. i]
        end

        if onSave then
            onSave(newPreset)
        end

        return newPreset
    end

    return nil
end

-- Export all presets as images
local function exportAllPresets(sprite, presets, outputDir)
    if #presets == 0 then
        app.alert("No presets to export!")
        return
    end

    local originalStates = saveVisibility(sprite)
    local exportedCount = 0

    for _, preset in ipairs(presets) do
        if preset.exportName and preset.exportName ~= "" then
            applyPresetVisibility(sprite, preset)

            local filename = preset.exportName
            if not filename:match("%.%w+$") then
                filename = filename .. ".png"
            end

            local fullPath = outputDir .. "/" .. filename
            sprite:saveCopyAs(fullPath)
            exportedCount = exportedCount + 1
        end
    end

    restoreVisibility(sprite, originalStates)
    app.alert("Exported " .. exportedCount .. " file(s)!")
end

-- Main preset manager dialog
local function showPresetManager()
    local sprite = app.activeSprite

    if not sprite then
        app.alert("No active sprite!")
        return
    end

    if not sprite.filename or sprite.filename == "" then
        app.alert("Please save the sprite first!")
        return
    end

    local presets = getPresetsForSprite(sprite)

    local function refreshDialog()
        showPresetManager()
    end

    local dlg = Dialog("Layer Export Presets")

    dlg:label{
        label = "Sprite:",
        text = sprite.filename:match("([^/\\]+)$") or sprite.filename
    }

    dlg:separator{ text = "Presets" }

    if #presets == 0 then
        dlg:label{ text = "(No presets defined)" }
    else
        local presetNames = {}
        for i, preset in ipairs(presets) do
            table.insert(presetNames, preset.name or ("Preset " .. i))
        end

        dlg:combobox{
            id = "selectedPreset",
            label = "Select:",
            options = presetNames
        }
    end

    dlg:newrow()
    dlg:button{ id = "addPreset", text = "Add New" }

    if #presets > 0 then
        dlg:button{ id = "editPreset", text = "Edit" }
        dlg:button{ id = "deletePreset", text = "Delete" }
        dlg:button{ id = "previewPreset", text = "Preview" }
    end

    dlg:separator{ text = "Import/Export Presets" }
    dlg:button{ id = "importPresets", text = "Import from JSON" }
    dlg:button{ id = "exportPresets", text = "Export to JSON", enabled = #presets > 0 }

    dlg:separator{ text = "Export Images" }

    local spriteDir = sprite.filename:match("^(.*[/\\])")

    dlg:file{
        id = "outputDir",
        label = "Output Folder:",
        save = false,
        filename = spriteDir or "",
        filetypes = {}
    }

    dlg:newrow()
    dlg:button{ id = "exportAll", text = "Export All Presets", enabled = #presets > 0 }
    dlg:button{ id = "exportSelected", text = "Export Selected", enabled = #presets > 0 }

    dlg:separator()
    dlg:button{ id = "close", text = "Close" }

    dlg:show()

    local data = dlg.data

    if data.addPreset then
        local newPreset = showPresetEditor(sprite, { name = "", exportName = "", layers = {} }, function(preset)
            table.insert(presets, preset)
            savePresetsForSprite(sprite, presets)
        end)
        if newPreset then refreshDialog() end
        return
    end

    if data.editPreset and data.selectedPreset then
        local selectedIndex = nil
        for i, preset in ipairs(presets) do
            if (preset.name or ("Preset " .. i)) == data.selectedPreset then
                selectedIndex = i
                break
            end
        end

        if selectedIndex then
            local editedPreset = showPresetEditor(sprite, presets[selectedIndex], function(preset)
                presets[selectedIndex] = preset
                savePresetsForSprite(sprite, presets)
            end)
            if editedPreset then refreshDialog() end
        end
        return
    end

    if data.deletePreset and data.selectedPreset then
        local result = app.alert{
            title = "Confirm Delete",
            text = "Delete preset '" .. data.selectedPreset .. "'?",
            buttons = { "Yes", "No" }
        }

        if result == 1 then
            for i, preset in ipairs(presets) do
                if (preset.name or ("Preset " .. i)) == data.selectedPreset then
                    table.remove(presets, i)
                    break
                end
            end
            savePresetsForSprite(sprite, presets)
            refreshDialog()
        end
        return
    end

    if data.previewPreset and data.selectedPreset then
        for i, preset in ipairs(presets) do
            if (preset.name or ("Preset " .. i)) == data.selectedPreset then
                applyPresetVisibility(sprite, preset)
                app.refresh()
                break
            end
        end
        return
    end

    if data.exportAll then
        local outputDir = data.outputDir
        if not outputDir or outputDir == "" then
            outputDir = spriteDir
        end

        if outputDir then
            exportAllPresets(sprite, presets, outputDir)
        else
            app.alert("Please select an output folder!")
        end
        return
    end

    if data.exportSelected and data.selectedPreset then
        local outputDir = data.outputDir
        if not outputDir or outputDir == "" then
            outputDir = spriteDir
        end

        if outputDir then
            for i, preset in ipairs(presets) do
                if (preset.name or ("Preset " .. i)) == data.selectedPreset then
                    exportAllPresets(sprite, { preset }, outputDir)
                    break
                end
            end
        else
            app.alert("Please select an output folder!")
        end
        return
    end

    if data.importPresets then
        if importPresetsFromFile(sprite) then
            refreshDialog()
        end
        return
    end

    if data.exportPresets then
        exportPresetsToFile(sprite, presets)
        return
    end
end

-- Quick export command
local function quickExportAll()
    local sprite = app.activeSprite

    if not sprite then
        app.alert("No active sprite!")
        return
    end

    if not sprite.filename or sprite.filename == "" then
        app.alert("Please save the sprite first!")
        return
    end

    local presets = getPresetsForSprite(sprite)

    if #presets == 0 then
        app.alert("No presets defined! Use 'Layer Export Presets > Manage Presets' to create presets first.")
        return
    end

    local spriteDir = sprite.filename:match("^(.*[/\\])")

    if spriteDir then
        exportAllPresets(sprite, presets, spriteDir)
    else
        app.alert("Could not determine output directory!")
    end
end

-- Plugin initialization
function init(p)
    plugin = p

    plugin.preferences = plugin.preferences or {}
    plugin.preferences.spritePresets = plugin.preferences.spritePresets or {}

    plugin:newMenuGroup{
        id = "layer_export_presets_menu",
        title = "Layer Export Presets",
        group = "file_export"
    }

    plugin:newCommand{
        id = "ManageLayerExportPresets",
        title = "Manage Presets...",
        group = "layer_export_presets_menu",
        onclick = showPresetManager
    }

    plugin:newCommand{
        id = "QuickExportAllPresets",
        title = "Quick Export All",
        group = "layer_export_presets_menu",
        onclick = quickExportAll
    }
end

function exit(p)
end
