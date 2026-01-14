-- Mosaic Tool Plugin for Aseprite
-- Apply mosaic (pixelate) effect to selected pixels

local plugin

-- Get pixel color components based on color mode
local function getColorComponents(image, pixel)
    if image.colorMode == ColorMode.RGB then
        return {
            r = app.pixelColor.rgbaR(pixel),
            g = app.pixelColor.rgbaG(pixel),
            b = app.pixelColor.rgbaB(pixel),
            a = app.pixelColor.rgbaA(pixel)
        }
    elseif image.colorMode == ColorMode.GRAY then
        return {
            v = app.pixelColor.grayaV(pixel),
            a = app.pixelColor.grayaA(pixel)
        }
    elseif image.colorMode == ColorMode.INDEXED then
        return { index = pixel }
    end
    return nil
end

-- Create pixel from color components
local function createPixel(image, components)
    if image.colorMode == ColorMode.RGB then
        return app.pixelColor.rgba(components.r, components.g, components.b, components.a)
    elseif image.colorMode == ColorMode.GRAY then
        return app.pixelColor.graya(components.v, components.a)
    elseif image.colorMode == ColorMode.INDEXED then
        return components.index
    end
    return 0
end

-- Calculate average color for a block (RGB/Gray modes)
local function calculateAverageColor(image, startX, startY, blockSize, selection, celX, celY)
    local sumR, sumG, sumB, sumA = 0, 0, 0, 0
    local sumV, sumGrayA = 0, 0
    local count = 0
    local indexCounts = {}

    for dy = 0, blockSize - 1 do
        for dx = 0, blockSize - 1 do
            local x = startX + dx
            local y = startY + dy

            if x >= 0 and x < image.width and y >= 0 and y < image.height then
                -- Check if pixel is in selection (selection uses canvas coordinates)
                local canvasX = celX + x
                local canvasY = celY + y
                if not selection or selection:contains(canvasX, canvasY) then
                    local pixel = image:getPixel(x, y)
                    local comp = getColorComponents(image, pixel)

                    if image.colorMode == ColorMode.RGB then
                        if comp.a > 0 then
                            sumR = sumR + comp.r
                            sumG = sumG + comp.g
                            sumB = sumB + comp.b
                            sumA = sumA + comp.a
                            count = count + 1
                        end
                    elseif image.colorMode == ColorMode.GRAY then
                        if comp.a > 0 then
                            sumV = sumV + comp.v
                            sumGrayA = sumGrayA + comp.a
                            count = count + 1
                        end
                    elseif image.colorMode == ColorMode.INDEXED then
                        indexCounts[pixel] = (indexCounts[pixel] or 0) + 1
                        count = count + 1
                    end
                end
            end
        end
    end

    if count == 0 then
        return nil
    end

    if image.colorMode == ColorMode.RGB then
        return {
            r = math.floor(sumR / count),
            g = math.floor(sumG / count),
            b = math.floor(sumB / count),
            a = math.floor(sumA / count)
        }
    elseif image.colorMode == ColorMode.GRAY then
        return {
            v = math.floor(sumV / count),
            a = math.floor(sumGrayA / count)
        }
    elseif image.colorMode == ColorMode.INDEXED then
        -- Return most common index
        local maxCount = 0
        local maxIndex = 0
        for idx, cnt in pairs(indexCounts) do
            if cnt > maxCount then
                maxCount = cnt
                maxIndex = idx
            end
        end
        return { index = maxIndex }
    end

    return nil
end

-- Apply mosaic effect
local function applyMosaic(sprite, cel, blockSize)
    local image = cel.image
    local selection = sprite.selection
    local hasSelection = selection and not selection.isEmpty

    -- Get cel position for coordinate conversion
    local celX = cel.position.x
    local celY = cel.position.y

    -- Clone image for modification
    local newImage = image:clone()

    -- Determine bounds to process
    local startX, startY, endX, endY

    if hasSelection then
        -- Use selection bounds (convert to image coordinates)
        local bounds = selection.bounds
        startX = math.max(0, bounds.x - celX)
        startY = math.max(0, bounds.y - celY)
        endX = math.min(image.width, bounds.x + bounds.width - celX)
        endY = math.min(image.height, bounds.y + bounds.height - celY)
    else
        startX = 0
        startY = 0
        endX = image.width
        endY = image.height
    end

    -- Align to block grid
    startX = math.floor(startX / blockSize) * blockSize
    startY = math.floor(startY / blockSize) * blockSize

    -- Process each block
    for blockY = startY, endY - 1, blockSize do
        for blockX = startX, endX - 1, blockSize do
            local avgColor = calculateAverageColor(image, blockX, blockY, blockSize, hasSelection and selection or nil, celX, celY)

            if avgColor then
                local pixel = createPixel(image, avgColor)

                -- Fill the block
                for dy = 0, blockSize - 1 do
                    for dx = 0, blockSize - 1 do
                        local x = blockX + dx
                        local y = blockY + dy

                        if x >= 0 and x < image.width and y >= 0 and y < image.height then
                            local canvasX = celX + x
                            local canvasY = celY + y

                            if not hasSelection or selection:contains(canvasX, canvasY) then
                                newImage:drawPixel(x, y, pixel)
                            end
                        end
                    end
                end
            end
        end
    end

    return newImage
end

-- Show mosaic dialog
local function showMosaicDialog()
    local sprite = app.activeSprite

    if not sprite then
        app.alert("No active sprite!")
        return
    end

    local cel = app.activeCel

    if not cel then
        app.alert("No active cel!")
        return
    end

    local dlg = Dialog("Mosaic")

    dlg:slider{
        id = "blockSize",
        label = "Block Size:",
        min = 2,
        max = 32,
        value = 4
    }

    dlg:button{ id = "apply", text = "Apply" }
    dlg:button{ id = "cancel", text = "Cancel" }

    dlg:show()

    if dlg.data.apply then
        local blockSize = dlg.data.blockSize

        app.transaction(function()
            local newImage = applyMosaic(sprite, cel, blockSize)
            cel.image = newImage
        end)

        app.refresh()
    end
end

-- Plugin initialization
function init(p)
    plugin = p

    plugin:newCommand{
        id = "MosaicTool",
        title = "Mosaic...",
        group = "edit_fx",
        onclick = showMosaicDialog
    }
end

function exit(p)
end
