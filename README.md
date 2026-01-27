# KOReader.patches

Useful patches for KOReader that I have either compiled, edited, or created myself.

### [🞂 2-turn-off-frontlight-during-refresh.lua](2-turn-off-frontlight-during-refresh.lua)
This patch removes the frontlight during refreshes in night mode.
Based on [this post by LexamusPrime](https://www.reddit.com/r/koreader/comments/1q9g37j/keep_dark_mode_dark).

It can be configured under **🞂 Screen 🞂 Frontlight refresh** on the <sub><img src="img/appbar.settings.svg" style="width:2%; height:auto;"></sub> **Settings** tab.

### [🞂 2-filemanager-next-prev-page-actions.lua](2-filemanager-next-prev-page-actions.lua)
This patch adds dispatcher actions (assignable to gestures) for going to the next or previous page in filemanager.

Made for [kobo.koplugin](https://github.com/OGKevin/kobo.koplugin).

### [🞂 2-change-progress-bar-color.lua](2-change-progress-bar-color.lua)
This patch adds the ability to change the RGB color of the reader progress bar.

It can be configured under **🞂 Status bar 🞂 Progress bar 🞂 Thickness, height & colors:** on the <sub><img src="img/appbar.settings.svg" style="width:2%; height:auto;"></sub> **Settings** tab.

It adds three menu options: the read and unread colors, and whether or not to invert the unread color in night mode.

This version specifically adds the following features:
- Night mode color correction (the same colors even in night mode)
- Setting persistence (the colors stay the same even after restarts)

Based off of [2-customise-progress-bar-colour-gui.lua](https://gist.github.com/IntrovertedMage/6ea38091292310241ba436f930ee0cb4) by [IntrovertedMage](https://github.com/IntrovertedMage).
