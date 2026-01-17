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

-- Sanitize presets: remove non-existent layers, add missing layers
local function sanitizePresets(sprite, presets)
    local allLayers = getAllLayers(sprite.layers)
    local existingLayerNames = {}
    for _, item in ipairs(allLayers) do
        existingLayerNames[item.fullName] = item.layer.isVisible
    end

    for _, preset in ipairs(presets) do
        local newLayers = {}

        -- Keep only existing layers
        for layerName, visible in pairs(preset.layers) do
            if existingLayerNames[layerName] ~= nil then
                newLayers[layerName] = visible
            end
        end

        -- Add missing layers with visibility off by default
        for layerName, _ in pairs(existingLayerNames) do
            if newLayers[layerName] == nil then
                newLayers[layerName] = false
            end
        end

        preset.layers = newLayers
    end

    return presets
end

-- Escape string for JSON
local function escapeJsonString(str)
    if not str then return "" end
    return str:gsub("\\", "\\\\"):gsub('"', '\\"')
end

-- Simple JSON encoder for sprite data (presets + outputDir)
local function encodeJSON(data)
    local result = "{\n"
    result = result .. '  "outputDir": "' .. escapeJsonString(data.outputDir or "") .. '",\n'
    result = result .. '  "presets": [\n'

    for i, preset in ipairs(data.presets or {}) do
        result = result .. "    {\n"
        result = result .. '      "name": "' .. escapeJsonString(preset.name) .. '",\n'
        result = result .. '      "exportName": "' .. escapeJsonString(preset.exportName) .. '",\n'
        result = result .. '      "layers": {\n'

        local layerEntries = {}
        for layerName, visible in pairs(preset.layers or {}) do
            table.insert(layerEntries, '        "' .. escapeJsonString(layerName) .. '": ' .. tostring(visible))
        end
        result = result .. table.concat(layerEntries, ",\n") .. "\n"

        result = result .. "      }\n"
        result = result .. "    }"
        if i < #data.presets then
            result = result .. ","
        end
        result = result .. "\n"
    end

    result = result .. "  ]\n"
    result = result .. "}"
    return result
end

-- Simple JSON decoder for sprite data
local function decodeJSON(jsonStr)
    local data = {
        outputDir = "",
        presets = {}
    }

    jsonStr = jsonStr:gsub("[\n\r\t]", " ")

    -- Extract outputDir
    local outputDir = jsonStr:match('"outputDir"%s*:%s*"([^"]*)"')
    if outputDir then
        data.outputDir = outputDir:gsub("\\\\", "\\"):gsub('\\"', '"')
    end

    -- Extract presets
    for presetStr in jsonStr:gmatch('{%s*"name"[^{}]*{[^{}]*}[^{}]*}') do
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

        table.insert(data.presets, preset)
    end

    return data
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

-- Get data for current sprite (with auto-load from JSON if preferences empty)
local function getDataForSprite(sprite)
    if not sprite or not sprite.filename or sprite.filename == "" then
        return { presets = {}, outputDir = "" }
    end

    local prefs = plugin.preferences
    prefs.spriteData = prefs.spriteData or {}

    -- If no data in preferences, try to load from JSON file
    if not prefs.spriteData[sprite.filename] then
        local autoSavePath = getAutoSavePath(sprite)
        if autoSavePath then
            local file = io.open(autoSavePath, "r")
            if file then
                local content = file:read("*all")
                file:close()
                local loadedData = decodeJSON(content)
                if loadedData and (#loadedData.presets > 0 or loadedData.outputDir ~= "") then
                    -- Sanitize presets to match current sprite layers
                    loadedData.presets = sanitizePresets(sprite, loadedData.presets)
                    prefs.spriteData[sprite.filename] = loadedData
                end
            end
        end
    end

    prefs.spriteData[sprite.filename] = prefs.spriteData[sprite.filename] or { presets = {}, outputDir = "" }

    -- Always sanitize when returning (in case layers changed)
    if #prefs.spriteData[sprite.filename].presets > 0 then
        prefs.spriteData[sprite.filename].presets = sanitizePresets(sprite, prefs.spriteData[sprite.filename].presets)
    end

    return prefs.spriteData[sprite.filename]
end

-- Save data for current sprite (also auto-saves to JSON)
local function saveDataForSprite(sprite, data)
    if not sprite or not sprite.filename or sprite.filename == "" then
        return
    end

    local prefs = plugin.preferences
    prefs.spriteData = prefs.spriteData or {}
    prefs.spriteData[sprite.filename] = data

    -- Auto-save to JSON file
    local autoSavePath = getAutoSavePath(sprite)
    if autoSavePath and (#data.presets > 0 or (data.outputDir and data.outputDir ~= "")) then
        local file = io.open(autoSavePath, "w")
        if file then
            file:write(encodeJSON(data))
            file:close()
        end
    end
end

-- Export presets to JSON file (manual)
local function exportPresetsToFile(sprite, data)
    if #data.presets == 0 then
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
            file:write(encodeJSON(data))
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

            local importedData = decodeJSON(content)
            if #importedData.presets > 0 then
                -- Sanitize presets to match current sprite layers
                importedData.presets = sanitizePresets(sprite, importedData.presets)
                saveDataForSprite(sprite, importedData)
                app.alert("Imported " .. #importedData.presets .. " preset(s)!")
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

    local data = getDataForSprite(sprite)
    local presets = data.presets

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
    local savedOutputDir = data.outputDir
    if not savedOutputDir or savedOutputDir == "" then
        savedOutputDir = spriteDir or ""
    end

    dlg:entry{
        id = "outputDir",
        label = "Output Folder:",
        text = savedOutputDir
    }
    dlg:button{
        id = "browseFolder",
        text = "Browse...",
        onclick = function()
            local browseDlg = Dialog("Select Output Folder")
            browseDlg:file{
                id = "file",
                label = "Select any file in target folder:",
                open = true,
                filename = savedOutputDir
            }
            browseDlg:button{ id = "ok", text = "OK" }
            browseDlg:button{ id = "cancel", text = "Cancel" }
            browseDlg:show()
            if browseDlg.data.ok and browseDlg.data.file then
                local dir = browseDlg.data.file:match("^(.*[/\\])")
                if dir then
                    dlg:modify{ id = "outputDir", text = dir }
                    savedOutputDir = dir
                end
            end
        end
    }

    dlg:newrow()
    dlg:button{ id = "exportAll", text = "Export All Presets", enabled = #presets > 0 }
    dlg:button{ id = "exportSelected", text = "Export Selected", enabled = #presets > 0 }

    dlg:separator()
    dlg:button{ id = "close", text = "Close" }

    dlg:show()

    local dlgData = dlg.data

    -- Save outputDir if changed
    if dlgData.outputDir and dlgData.outputDir ~= "" and dlgData.outputDir ~= data.outputDir then
        data.outputDir = dlgData.outputDir
        saveDataForSprite(sprite, data)
    end

    if dlgData.addPreset then
        local newPreset = showPresetEditor(sprite, { name = "", exportName = "", layers = {} }, function(preset)
            table.insert(presets, preset)
            saveDataForSprite(sprite, data)
        end)
        if newPreset then refreshDialog() end
        return
    end

    if dlgData.editPreset and dlgData.selectedPreset then
        local selectedIndex = nil
        for i, preset in ipairs(presets) do
            if (preset.name or ("Preset " .. i)) == dlgData.selectedPreset then
                selectedIndex = i
                break
            end
        end

        if selectedIndex then
            local editedPreset = showPresetEditor(sprite, presets[selectedIndex], function(preset)
                presets[selectedIndex] = preset
                saveDataForSprite(sprite, data)
            end)
            if editedPreset then refreshDialog() end
        end
        return
    end

    if dlgData.deletePreset and dlgData.selectedPreset then
        local result = app.alert{
            title = "Confirm Delete",
            text = "Delete preset '" .. dlgData.selectedPreset .. "'?",
            buttons = { "Yes", "No" }
        }

        if result == 1 then
            for i, preset in ipairs(presets) do
                if (preset.name or ("Preset " .. i)) == dlgData.selectedPreset then
                    table.remove(presets, i)
                    break
                end
            end
            saveDataForSprite(sprite, data)
            refreshDialog()
        end
        return
    end

    if dlgData.previewPreset and dlgData.selectedPreset then
        for i, preset in ipairs(presets) do
            if (preset.name or ("Preset " .. i)) == dlgData.selectedPreset then
                applyPresetVisibility(sprite, preset)
                app.refresh()
                break
            end
        end
        return
    end

    if dlgData.exportAll then
        local outputDir = dlgData.outputDir
        if not outputDir or outputDir == "" then
            outputDir = spriteDir
        end

        if outputDir then
            -- Save the outputDir
            data.outputDir = outputDir
            saveDataForSprite(sprite, data)
            exportAllPresets(sprite, presets, outputDir)
        else
            app.alert("Please select an output folder!")
        end
        return
    end

    if dlgData.exportSelected and dlgData.selectedPreset then
        local outputDir = dlgData.outputDir
        if not outputDir or outputDir == "" then
            outputDir = spriteDir
        end

        if outputDir then
            -- Save the outputDir
            data.outputDir = outputDir
            saveDataForSprite(sprite, data)
            for i, preset in ipairs(presets) do
                if (preset.name or ("Preset " .. i)) == dlgData.selectedPreset then
                    exportAllPresets(sprite, { preset }, outputDir)
                    break
                end
            end
        else
            app.alert("Please select an output folder!")
        end
        return
    end

    if dlgData.importPresets then
        if importPresetsFromFile(sprite) then
            refreshDialog()
        end
        return
    end

    if dlgData.exportPresets then
        exportPresetsToFile(sprite, data)
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

    local data = getDataForSprite(sprite)
    local presets = data.presets

    if #presets == 0 then
        app.alert("No presets defined! Use 'Layer Export Presets > Manage Presets' to create presets first.")
        return
    end

    local outputDir = data.outputDir
    if not outputDir or outputDir == "" then
        outputDir = sprite.filename:match("^(.*[/\\])")
    end

    if outputDir then
        exportAllPresets(sprite, presets, outputDir)
    else
        app.alert("Could not determine output directory!")
    end
end

-- Plugin initialization
function init(p)
    plugin = p

    plugin.preferences = plugin.preferences or {}
    plugin.preferences.spriteData = plugin.preferences.spriteData or {}

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
