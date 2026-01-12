# Aseprite Plugins

A collection of plugins for [Aseprite](https://www.aseprite.org/), the animated sprite editor.

## Plugins

### Layer Export Presets

Configure layer visibility patterns and batch export images with one click.

#### Features

- Save multiple layer visibility presets per sprite
- Export all presets as images with a single button
- Preview presets before exporting
- Auto-backup presets to JSON files (recovers after plugin reload)
- Import/Export presets for sharing or migration

#### Installation

1. Download or clone this repository
2. Copy the `layer-export-presets` folder to your Aseprite extensions directory:
   - **Windows**: `C:\Program Files (x86)\Steam\steamapps\common\Aseprite\data\extensions\`
   - **macOS**: `/Applications/Aseprite.app/Contents/Resources/data/extensions/`
3. Restart Aseprite

For development, you can create a symbolic link (junction on Windows):

```powershell
# Windows (PowerShell)
New-Item -ItemType Junction -Path 'C:\Program Files (x86)\Steam\steamapps\common\Aseprite\data\extensions\layer-export-presets' -Target 'C:\path\to\layer-export-presets'
```

#### Usage

1. Open a sprite and save it (the plugin requires a saved file)
2. Go to **File > Layer Export Presets > Manage Presets...**
3. Click **Add New** to create a preset:
   - Enter a **Preset Name** (e.g., "Character Only")
   - Enter an **Export Filename** (e.g., "character.png")
   - Check/uncheck layers to set visibility
   - Click **Save**
4. Repeat to create more presets
5. Click **Export All Presets** to export all presets as images

#### Quick Export

Use **File > Layer Export Presets > Quick Export All** to export all presets without opening the manager dialog. You can assign a keyboard shortcut to this command.

#### Backup & Migration

Presets are automatically saved to a `.presets.json` file next to your sprite. If you move your sprite to another location:

1. Copy the `.presets.json` file along with the sprite
2. Open the sprite and go to **Manage Presets...**
3. Click **Import from JSON** and select the `.presets.json` file

## License

MIT
