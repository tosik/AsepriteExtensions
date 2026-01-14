# Aseprite Plugins

A collection of plugins for [Aseprite](https://www.aseprite.org/), the animated sprite editor.

## Installation

### For Users

1. Download or clone this repository
2. Copy the plugin folder to your Aseprite extensions directory:
   - **Windows**: `C:\Users\<username>\AppData\Roaming\Aseprite\extensions\`
3. Restart Aseprite

### For Developers

Create a junction link for live development:

```powershell
New-Item -ItemType Junction -Path 'C:\Users\<username>\AppData\Roaming\Aseprite\extensions\<plugin-name>' -Target 'C:\path\to\<plugin-name>'
```

---

## Plugins

### Layer Export Presets

Configure layer visibility patterns and batch export images with one click.

#### Features

- Save multiple layer visibility presets per sprite
- Export all presets as images with a single button
- Preview presets before exporting
- Auto-backup presets to JSON files
- Import/Export presets for sharing or migration

#### Usage

1. Open a sprite and save it
2. Go to **File > Layer Export Presets > Manage Presets...**
3. Click **Add New** to create a preset
4. Set layer visibility and export filename
5. Click **Export All Presets** to export

#### Quick Export

Use **File > Layer Export Presets > Quick Export All** for fast export without opening the dialog.

---

### Outline Tool

Draw outlines around non-transparent pixels.

#### Features

- Inner outline (inside the sprite boundary)
- Outer outline (around the sprite)
- Uses the closest black color in the palette (for indexed mode)
- 4-directional only (no diagonal)

#### Usage

1. Select a layer with content
2. Right-click on the cel in the timeline
3. Select **Draw Outline...**
4. Choose outline type and click Apply

---

### Outline Thinner

Thin 2-pixel thick outlines to 1-pixel.

#### Features

- Detects and removes redundant outline pixels
- Handles diagonal stair-step patterns
- Handles 2x2 block patterns
- Iterative thinning with configurable passes

#### Usage

1. Select a layer with outline
2. Right-click on the cel in the timeline
3. Select **Outline Thinner...**
4. Adjust iterations and click Apply

---

### Mosaic Tool

Apply pixelation/mosaic effect to selected pixels.

#### Features

- Configurable block size (2-32 pixels)
- Works on selection or entire cel
- Averages colors within each block

#### Usage

1. Optionally make a selection
2. Right-click on the cel in the timeline
3. Select **Mosaic...**
4. Set block size and click Apply

---

### Color Reduction

Merge similar colors within a distance threshold.

#### Features

- Live preview of color reduction
- Adjustable distance threshold
- Uses Union-Find algorithm for color grouping
- Consolidates palette and remaps pixels

#### Usage

1. Convert sprite to Indexed mode first
2. Go to **Sprite > Color Reduction...**
3. Adjust threshold slider to preview
4. Click Apply to confirm

---

### Palette Editor

Edit indexed palette colors with live preview.

#### Features

- Visual color grid for selection
- Full color picker integration
- Live preview of color changes
- Revert individual colors or all changes
- Defaults to foreground color on open

#### Usage

1. Open an Indexed color mode sprite
2. Go to **Sprite > Palette Editor...**
3. Click a color to select, use color picker to edit
4. Click Apply to confirm changes

---

## License

MIT
