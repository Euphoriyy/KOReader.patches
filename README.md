# KOReader.patches

Useful patches for KOReader that I have either compiled, edited, or created myself.

### [🞂 2-dim-during-refresh.lua](2-dim-during-refresh.lua)
This patch lowers the brightness during refreshes in night mode to prevent bright flashes on e-ink.
Based on [this post by LexamusPrime](https://www.reddit.com/r/koreader/comments/1q9g37j/keep_dark_mode_dark).

It can be configured under **🞂 Screen 🞂 Dim frontlight on refreshes** on the <sub><img src="img/appbar.settings.svg" style="width:2%; height:auto;"></sub> **Settings** tab.

It has the following options:
- A toggle to enable dimming.
- A toggle to force dimming every page turn/refresh.
- A toggle for dimming on UI refreshes.
- A toggle for dimming in the reader only.
- A toggle to dim relative to the current brightness.
- A numeric stepper for the level of dimming (absolute/relative).

### [🞂 2-filemanager-next-prev-page-actions.lua](2-filemanager-next-prev-page-actions.lua)
This patch adds dispatcher actions (assignable to gestures) for going to the next or previous page in filemanager.

Made for [kobo.koplugin](https://github.com/OGKevin/kobo.koplugin).

### [🞂 2-correct-screen-borders.lua](2-correct-screen-borders.lua)
This patch adds border lines to the sides of the screen to correct for e-ink issues.
Made for [this post by wigglytoad](https://www.reddit.com/r/koreader/comments/1r7l5co/request_patch_to_remove_1pixelwide_vertical_white/).

It can be configured under **🞂 Screen 🞂 Border correction** on the <sub><img src="img/appbar.settings.svg" style="width:2%; height:auto;"></sub> **Settings** tab.

### [🞂 2-percent-badge.lua](2-percent-badge.lua)
This patch adds a customizable badge that displays the percentage read for each book. It also displays whether a book has been completed or paused.

It has inline option variables at the start of the file.

In comparison to the original, it adds two new additional features:
- The ability to not be inverted in night mode when used together with the [UI background color patch](#-2-ui-background-colorlua).
- The inline option to exclude the text color from being modified by the [UI font color patch](#-2-ui-font-colorlua).

Edited from [the version by angelsangita](https://github.com/angelsangita/Koreader-Patches?tab=readme-ov-file#-2-percent-badge).

### [🞂 2-rounded-covers.lua](2-rounded-covers.lua)
This patch adds rounded corners to the book covers in the file browser.

The core feature that distinguishes this version is that it is background-agnostic, meaning that it works on any background without requiring any corner icons. Due to that, this patch works well with the [Appearance plugin](https://github.com/Euphoriyy/appearance.koplugin).

Based on the [original patch by SeriousHornet](https://github.com/SeriousHornet/KOReader.patches?tab=readme-ov-file#-2--rounded-coverslua).

### [🞂 2-rounded-folder-covers.lua](2-rounded-folder-covers.lua)
This patch adds rounded corners to the folder covers in the file browser.

The core feature that distinguishes this version is that it is background-agnostic, meaning that it works on any background without requiring any corner icons. Due to that, this patch works well with the [Appearance plugin](https://github.com/Euphoriyy/appearance.koplugin).

It also adds an option to show/hide the file count.

Based on the [original patch by SeriousHornet](https://github.com/SeriousHornet/KOReader.patches?tab=readme-ov-file#-2-rounded-folder-coverslua).

### [🞂 2-custom-widgets.lua](2-custom-widgets.lua)
This patch adds support for custom widgets that can be used by other patches and plugins.

Widgets are auto-loaded from: `<koreader_dir>/widgets/`

Each .lua file in that directory is loaded and registered under its
filename (without the .lua extension). For example:
    widgets/colorwheelwidget.lua  →  "colorwheelwidget"

Information on how to use it in patches/plugins can be found in the patch comments.

### [🞂 2-invert-document.lua](2-invert-document.lua)

> [!WARNING]
> This patch is now obsolete as of the newest release (v2026.03) with koreader/koreader#14954.
> It should be removed when updating to new releases or the nightly.

This patch adds a document option to invert CBZs/PDFs in night mode.
It is useful for reading comics/manga in night mode.

Made for koreader/koreader#9899.

<img src="img/invert-document.png" style="width:50%; height:auto;">

---

> [!IMPORTANT]
> The features of the following patches have been merged into [appearance.koplugin](https://github.com/Euphoriyy/appearance.koplugin).

### [🞂 2-progress-bar-color.lua](https://github.com/Euphoriyy/appearance.koplugin)
### [🞂 2-ui-themes.lua](https://github.com/Euphoriyy/appearance.koplugin)
### [🞂 2-ui-font-color.lua](https://github.com/Euphoriyy/appearance.koplugin)
### [🞂 2-ui-background-color.lua](https://github.com/Euphoriyy/appearance.koplugin)
### [🞂 2-ui-background-image.lua](https://github.com/Euphoriyy/appearance.koplugin)

## Widgets

Widgets allow for additional functionality for patches. Developers use them to provide unique ways to configure options.

### *How do I install widgets?*
You can install widgets by using the [custom widgets patch](#-2-custom-widgetslua). After installing that patch, you have to create a custom `widgets` folder (just like the `patches` folder) inside of the `koreader directory`. Any widgets can now be placed inside this new `widgets` folder.

### [🞂 colorwheelwidget.lua](widgets/colorwheelwidget.lua)

Adds a visual color wheel for selecting colors. It can be used with numerous different options.

The options are:
- `title_text`
- `width`
- `width_factor`
- `hue`
- `saturation`
- `value`
- `invert_in_night_mode`
- `draw_scale`
- `cancel_text`
- `apply_text`

<img src="img/colorwheelwidget.png" style="width:50%; height:auto;">

## Support
If you want to support me, you can star this repository or buy me a coffee. :)

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/X8X21UH4E1)

## License
This project is licensed under the **GNU General Public License v3.0**.
See the [LICENSE](./LICENSE) file for full details.
