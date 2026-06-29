# User Manual for KVision

**KVision** is an advanced application designed for simultaneous viewing of live video streams (RTSP/ONVIF) and integration with Hikvision NVR/DVR recorders (both in Live mode and Playback archive mode).

The program has been optimized for stability, smooth operation (60 FPS), and minimal system resource consumption.

---

## Table of Contents
1. [Description of Button Actions](#1-description-of-button-actions)
2. [Installation and Launching](#2-installation-and-launching)
3. [Managing NVR/DVR Recorders](#3-managing-nvrdvr-recorders)
4. [Live View and Viewport Overlays](#4-live-view-and-viewport-overlays)
5. [Screen Layouts, Presets, and Toolbar](#5-screen-layouts-presets-and-toolbar)
6. [System Statistics Panel (System Stats)](#6-system-statistics-panel-system-stats)
7. [Playback Archive Player](#7-playback-archive-player)
8. [Downloading Recordings (Downloader)](#8-downloading-recordings-downloader)
9. [Advanced Settings and Customization in Options Sidebar](#9-advanced-settings-and-customization-in-options-sidebar)
10. [Keyboard Shortcuts and Mouse Controls](#10-keyboard-shortcuts-and-mouse-controls)
11. [Taking Snapshots and Path Configuration](#11-taking-snapshots-and-path-configuration)

---

## 1. Description of Button Actions

This section describes the meaning of all graphical icons and buttons used in the application.

### Top Tool Bar
* {ICON:quit} **Close Window**: Prompts for confirmation and closes the active window or application.
* {ICON:pin} **Pin Bar**: Locks the top bar in an expanded state or enables auto-collapsing.
* {ICON:fullscreen} **Full Screen**: Toggles the active window into fullscreen mode.
* {ICON:minimize} **Minimize**: Minimizes the application window to the system taskbar.
* {ICON:options} **Options**: Opens or closes the sliding configuration sidebar (settings and recorders).
* {ICON:new_window} **New Window**: Opens a new, independent auxiliary window for camera streams.
* {ICON:archive} **Archive**: Opens the playback recordings archive window (timeline and calendar).
* {ICON:instructions} **Instructions**: Opens this user manual and technical assistance window.
* {ICON:stats} **Stats**: Toggles the sliding system statistics panel (CPU, RAM, GPU, Net).
* {ICON:lock} **Grid Lock**: Disables grid division adjustments to protect your active layout.
* {ICON:hamburger} **More Options**: Opens the sliding toolbox for advanced division sizes, ratios, and cell merging.

### Viewport Overlays (Cameras)
* {ICON:snapshot} **Snapshot**: Captures a lossless full-resolution image and saves it as a JPEG file.
* {ICON:play} **Camera Archive**: Launches the timeline playback window for this camera (15 minutes backward).
* {ICON:grid_1x1} **Try 1:1**: Displays the video stream in its original, native resolution without stretching.
* {ICON:zoom_in} **Interactive Zoom**: Toggles click-and-drag magnification for a selected marquee region.
* {ICON:zoom_out} **Reset Zoom**: Resets the digital magnification and restores the full camera field of view.
* {ICON:speaker_unmute} **Mute Audio**: Represents an unmuted audio stream; clicking it mutes the stream.
* {ICON:speaker_mute} **Unmute Audio**: Represents a muted audio stream; clicking it unmutes the stream.

### Playback Window Controls

**Top Bar Controls:**
* {ICON:close} **Close**: Closes the playback archive player window.
* {ICON:pin} **Pin Bar**: Locks the top bar in an expanded state or enables auto-collapsing.
* {ICON:fullscreen} **Full Screen**: Toggles the playback window into fullscreen mode.
* {ICON:sidebar} **Show/Hide Sidebar**: Toggles the visibility of the left sidebar containing cameras and recorders.
* {ICON:timeline_show} / {ICON:timeline_hide} **Show/Hide Timeline**: Shows or hides the bottom panel containing the timeline and playback controls.
* {ICON:video_folder} **Video Folder**: Opens the local system folder containing downloaded video clips.
* {ICON:photo_folder} **Snapshot Folder**: Opens the local system folder containing captured snapshots.
* grid buttons `1x1`, `1x2`, `2x1`, `2x2`: Switches the camera display layout of the playback window to 1, 2 (vertical/horizontal) or 4 concurrent views.

**Bottom Bar & Timeline Controls:**
* {ICON:prev_day} **Previous Day**: Navigates to recordings of the previous calendar day.
* {ICON:calendar_select} **Date Picker**: Opens a calendar dialog to select a specific date for playback.
* {ICON:next_day} **Next Day**: Navigates to recordings of the next calendar day.
* {ICON:today} **Today**: Instantly shifts the playback focus to the current calendar day.
* {ICON:refresh_recordings} **Refresh recordings**: Refreshes and re-queries available recording segments from the device.
* {ICON:zoom_1h} / {ICON:zoom_8h} / {ICON:zoom_24h} **Timeline Zoom Presets**: Scales the visible window of the timeline (to 1 hour, 8 hours, or 24 hours) for high-precision navigation.
* {ICON:timeline_center} **Center Timeline**: Centers the timeline view precisely around the current playback timestamp.
* {ICON:speed_1x} / {ICON:speed_2x} / {ICON:speed_4x} **Playback Speed**: Adjusts the video playback multiplier (standard 1x speed, 2x accelerated, or 4x rapid play).
* {ICON:download} **Download**: Opens the download tool to export a defined video segment from the device.
* {ICON:jump_back_60} / {ICON:jump_back_45} / {ICON:jump_back_15} **Jump Backward**: Rewinds the playback timestamp by 60, 45, or 15 seconds.
* {ICON:play} / {ICON:pause} **Play / Pause**: Initiates or pauses the archive video stream playback.
* {ICON:jump_forward_15} / {ICON:jump_forward_45} / {ICON:jump_forward_60} **Jump Forward**: Advances the playback timestamp by 15, 45, or 60 seconds.

**Other Diagnostic & General Icons:**
* {ICON:calendar} **Calendar**: Represents calendar/scheduling configurations.
* {ICON:clock} **Time**: Represents clock or temporal status indicators.
* {ICON:zoom} **Zoom**: Represents scaling or digital zoom configurations.
* {ICON:timeline_toggle} **Timeline Toggle**: Represents toggling or refreshing of chronological views.
* {ICON:trash} **Delete**: Safely removes configured recorders or layouts with confirmation.
* {ICON:warning} **Warning**: Displayed in dialog boxes for irreversible actions or delete warnings.

---

## 2. Installation and Launching

### Installing on Arch Linux (Pacman)
To install the program from the prepared binary package, go to the `packaging/arch/` directory and run:
```bash
sudo pacman -U kvision-2.2.7-3-x86_64.pkg.tar.zst
```
The package will automatically install the program, the `.desktop` activation file, and the required Hikvision SDK libraries to the system path `/usr/lib/kvision`.

### Manual Compilation (from source code)
If you want to compile the program manually (e.g., on another Linux distribution) instead of using the ready-made package:

1. Install the required build and runtime dependencies using your package manager. For Arch Linux / CachyOS:
   ```bash
   sudo pacman -S base-devel cmake qt5-declarative qt5-multimedia qt5-quickcontrols qt5-quickcontrols2 qt5-svg qt5-graphicaleffects qt5-tools ffmpeg git
   ```
2. Configure the project using CMake:
   ```bash
   cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
   ```
3. Compile the code:
   ```bash
   cmake --build build -j$(nproc)
   ```
4. Install the application in the system:
   ```bash
   sudo cmake --install build
   ```

### Launching
The program can be launched from the system menu or by typing in the terminal:
```bash
kvision
```

### Troubleshooting System Scaling (KDE Plasma)
If the program does not automatically adjust to your system's desktop scaling settings in the KDE Plasma environment (appearing too small or too large), you can easily fix this using one of two methods: via the graphical interface (GUI) or by manually editing the launcher file.

#### Method 1: Via KDE Plasma GUI (Edit Applications)
This is the easiest method and does not require using the terminal:
1. Right-click on your system's application launcher (Start Menu) icon and select **"Edit Applications..."** (or run `kmenuedit` from the terminal).
2. In the menu editor window, locate **KVision** (usually found under *System* or *Utilities*, or by searching for it).
3. Click on **KVision** to open its properties.
4. Go to the **"Application"** tab.
5. Locate the **"Command"** field (which defaults to `kvision`) and modify it by prepending the required environment variables. For example, for **150%** scaling, change it to:
   ```ini
   env QT_FONT_DPI=96 QT_SCALE_FACTOR=1.5 kvision
   ```
   *(Note: Adjust the `QT_SCALE_FACTOR` value to match your monitor scaling, e.g., `1.25` for 125%, `2.0` for 200%, etc.)*
6. Click **"Save"** in the toolbar. The changes will be automatically saved to your user profile (creating a local copy of the launcher at `~/.local/share/applications/kvision.desktop`).

#### Method 2: Manually Editing the `.desktop` File (Terminal)
If you prefer text-based configuration or are not using the default menu editor:
1. Copy the system `.desktop` file to your home directory (so future package updates don't overwrite your changes):
   ```bash
   cp /usr/share/applications/kvision.desktop ~/.local/share/applications/
   ```
2. Open the copied file in a text editor (e.g., Kate or KWrite):
   ```bash
   kate ~/.local/share/applications/kvision.desktop
   ```
3. Find the line starting with `Exec=` (default is `Exec=kvision`).
4. Modify this line by prepending the `QT_FONT_DPI` and `QT_SCALE_FACTOR` environment variables. For example, for **150%** scaling, set:
   ```ini
   Exec=env QT_FONT_DPI=96 QT_SCALE_FACTOR=1.5 kvision
   ```
5. Save the file. From now on, launching the program from your system launcher will apply the forced scaling factor correctly.

---

## 3. Managing NVR/DVR Recorders

To configure the connection to a Hikvision recorder:
1. Open the sidebar options panel and go to the **Recorders** tab (server icon).
2. Enter the device access details:
   * **IP Address**: The network address of the recorder.
   * **Port**: The SDK network port (default is `8000`).
   * **Username**: User name (e.g., `admin`).
   * **Password**: Password to access the recorder.
3. Click **Connect & Discover** (or **Save & Update**).
4. Upon successful connection, the application will automatically detect all active cameras (channels) connected to the NVR/DVR and add them to the list.
5. Clicking the **Generate Grid** button will automatically create a viewport layout (preset) containing all active cameras from that NVR in an optimal grid layout.
6. **Displaying Camera Lists (NvrCamerasWindow)**: Clicking the computer monitor icon button on any recorder's card opens a dedicated window showing all detected camera channels as interactive tiles.
7. **Generating Thumbnails (Generate thumbnails)**: In the NVR cameras list window, a *„Generate thumbnails”* button is available. Clicking it commands the application to pull single frames from each channel's Sub Stream in the background, setting them as the tile background thumbnails. This provides a quick visual preview of each camera without launching full live feeds.
8. **Click-and-Add Feature**: The application does not support dragging tiles (drag and drop) from the camera list window to the main grid. Camera assignment is done in a simple and reliable way: first left-click any viewport tile in the main screen grid to select it (it will highlight with a bright border), then click the green **"+" (Assign to active viewport)** button on the desired camera tile in the NVR camera list window. The stream will instantly load in that slot.
9. **SDK Session Status (Dot indicator)**: Beside each recorder's IP on the list, there is a colored status dot:
   * **Green (LOGGED IN)**: Represents an active Hikvision SDK session, which is required for PTZ control, timeline archive requests, and downloading.
   * **Red (NOT LOGGED IN)**: No active SDK session is currently established (e.g. before the first SDK request or after manual/automatic logout). Note that camera RTSP live feeds will continue to play independently of the SDK session status.
10. **Local Camera Renaming**: On any camera tile in the NVR cameras list, click the **Edit** (pencil) icon. This opens a dialog allowing you to set a custom name for the camera. This name is saved locally and instantly updates across the live players, timeline, and tile views without modifying the physical NVR device. You can reset it to the default name at any time.
11. **Removing a Recorder from List**: Beside each configured recorder on the list, there is a red trash can button. Clicking it initiates a two-stage security protocol designed to prevent accidental deletion:
    * **Step 1 (Confirmation)**: A dialog titled *“Confirm NVR Deletion”* appears, asking if you are sure you want to delete the recorder.
    * **Step 2 (Warning)**: A second warning dialog titled *“Warning!”* appears, asking if you are absolutely sure and aware of what you are doing.
    * **Effect of Deletion**: Upon accepting the second warning, the program logs out from that NVR in the background, deletes its entry from the application configuration, and **automatically sweeps the preset layouts list**, removing all dynamic grids generated for this NVR device.

---

## 4. Live View and Viewport Overlays

The main window of the program displays the live feed:
* **Camera Grid**: Displays RTSP streams or feeds directly from the Hikvision SDK.
* **Stream Quality Selection**: By right-clicking a camera viewport, you can select the **Main Stream** for highest resolution, or the **Sub Stream** to reduce network and graphics card load.
* **Double-Click Fullscreen Toggle**: Double-clicking with the left mouse button on any camera viewport instantly maximizes it to fill the entire active window area (single-viewport fullscreen). Double-clicking again restores the original multi-camera grid layout.
* **Auto-hiding Top Bar**: The top options toolbar (topToolBar) can automatically collapse to the top edge of the screen when the mouse cursor leaves its area (this option is configurable in Settings -> *„Automatically collapse top bar”* or directly using the pin icon on the top bar).
* **Multi-Monitor & Auxiliary Windows**: You can open independent additional (auxiliary) windows to run different grid layouts simultaneously on multiple screens or monitors. To open a new window, use the `Ctrl+N` keyboard shortcut, or click the **"New Window"** button on the hover-slide top toolbar. Each window can be configured with its own grid size and selected preset layout.

### Viewport Overlay Buttons
In the bottom-right corner of each camera tile/viewport, a control panel with four functional icons is displayed when hovering the mouse cursor over it (depending on UI preferences):
1. **Camera Icon (Snapshot)**: Allows you to take a screenshot from the camera feed. The snapshot is saved in the full, native resolution of the stream directly from the decoder frame buffer, avoiding any losses due to the current size of the viewport tile or screen resolution scaling. Successful snapshot saving is confirmed by the camera icon flashing orange (`#ff7a00`) for exactly 1 second.
2. **Play Icon (Archive)**: Used to quickly open the recordings archive. Clicking this button automatically launches the timeline `PlaybackWindow` for this specific camera, starting the playback **exactly 15 minutes before the current system time** (a convenient quick backward offset).
3. **1:1 Icon (Native Scale)**: Toggles pixel-to-pixel video display mode. When enabled, the video is not stretched or distorted to fill the tile boundaries, but is instead centered and shown in its original native resolution. When this mode is active, the button background and "1:1" text are highlighted in bright neon light-turquoise.
4. **Magnifying Glass Icon (Interactive Zoom)**: Allows you to magnify any specific region of the video feed:
   * **Activation**: Clicking the icon toggles it into an active state (turquoise highlight). The cursor changes shape, and a tooltip instructs: *“Click and drag on camera feed to zoom”*.
   * **Operation**: Left-click and drag a rectangular marquee region over the live feed. The viewport will automatically crop and scale the selected area to fill the entire tile.
   * **Reset**: When zoomed, the magnifying glass icon changes its icon (red border with a minus sign). Clicking it immediately resets the zoom, returning to the full camera feed.

---

## 5. Screen Layouts, Presets, and Toolbar

Layouts allow you to organize the arrangement of cameras on the screen. From the **Presets** tab (star icon) you can:
* **Create New Presets**: Add your own layout with any configuration of columns and rows (e.g., 2x2, 3x3, 4x4).
* **Assign Cameras**: Click on a viewport in the grid layout to select it, then open the NVR cameras window and click the **"+" (Add)** button on the desired camera tile. You can also swap viewport positions using the right-click context menu (*„Zamień miejscami”* / *„Swap viewports”*) of the source viewport and then clicking on the target viewport.

### Top Bar Buttons (Top Tool Bar)
The top sliding toolbar provides a comprehensive set of navigation and application control buttons:
1. **Close Window (Red ✕ Button)**: Closes the active window. To prevent accidental clicks, it intercepts the closing event and prompts you with a dialog box to confirm exiting the application.
2. **Pin Button**: Controls the auto-hiding behavior of the top toolbar. When the pin is pointing vertically (pinned state), the bar is locked in place and remains permanently visible. When the pin is rotated by -45 degrees (unpinned state), the bar automatically slides upward out of view when the mouse leaves its area.
3. **Full Screen (Green Arrows Icon)**: Instantly switches the active window into fullscreen mode and back. In fullscreen mode, the arrows point inward (collapse), and in windowed mode, they point outward (expand).
4. **Minimize (Cyan Minimization Icon)**: Minimizes the application window to the taskbar. Restoring it returns the window to its exact previous state (e.g. maximized or fullscreen).
5. **⚙️ OPTIONS (OPCJE)**: Toggles the sliding sidebar config window. If the panel is already open, clicking this button closes it.
6. **📺 NEW WINDOW (NOWE OKNO)**: Opens a new, independent, and fully configurable `Auxiliary Window`, perfect for expanding your camera layouts across multiple monitor setups.
7. **ARCHIVE**: Opens an empty `PlaybackWindow` (recordings player) with active timeline and calendar, allowing manual stream and camera channel selections from any configured NVR via the sidebar list.
8. **INSTRUCTIONS (INSTRUKCJA)**: Opens this manual window, loading the complete user documentation in English or Polish depending on your active locale.
9. **📊 STATS (STATYSTYKI) Switch**: Toggle switch to slide out the System Statistics monitoring panel from the left screen edge.
10. **Grid Lock Switch (Padlock)**: Switch that, when turned ON (highlighted in bright orange), disables grid-resizing actions on the adjacent grid buttons, protecting your active camera layout from accidental changes.
11. **Grid Size Selectors (from 1x1 to 9x9)**: A row of nine buttons that lets you instantly define the row and column structure of your viewport (from a single camera 1x1 view up to 81 simultaneous camera feeds in a 9x9 layout). The currently active size highlights in bright orange.
12. **More Options (Hamburger Menu with three lines)**: Button opening the sliding `Layout & Grid Tools` toolbox for advanced grid tuning, geometry adjustments, and debugging options (detailed below).
13. **Preset/View Buttons**: Dynamically rendered buttons on the right side of the toolbar representing your configured and visible preset layouts (e.g. *📹 NVR*, *View 1*, etc.). Clicking a button immediately switches the grid. The active view highlights in bright light-turquoise.

### Advanced Grid Customization & Ratios (Layout & Grid Tools)
Opening the Hamburger (More Options) menu brings up a specialized layout toolbox. To activate its controls:
1. **Unlock tools pane**: Toggle the "Unlock tools pane" switch at the very top. This is an explicit safety measure to prevent accidental changes to complex layouts.
2. **Custom Window Division (F2 or Press-and-Hold)**: The toolbox displays grid division buttons from 1x1 to 9x9. An extremely advanced feature is the ability to **override and edit division sizes**. If you click-and-hold any grid button with the left mouse button (or focus it and press **F2**), a text box appears. You can type any custom or asymmetrical division (such as `2x3`, `1x4`, etc.) and press Enter. The button is instantly reprogrammed, and clicking it applies your custom layout to the main viewport.
3. **Geometry Ratios**: Allows forcing the grid display to specific aspect ratios:
   * **16:9 Aspect Ratio**: Locks and scales the grid container to widescreen 16:9 format (standard for modern IP cameras).
   * **4:3 Aspect Ratio**: Adapts the grid container to the traditional 4:3 ratio (common in legacy analog/IP cameras).
4. **Grid Operations (Merge Highlighted Cells)**: Access the asymmetric cell merging feature (detailed in Section 9.2).

---

## 6. System Statistics Panel (System Stats)

Sliding out from the left edge of the Live View screen, this panel monitors the computer's health and the load generated by the application:
* **Monitored Parameters**:
  * **CPU / RAM**: Usage of the main processor (in % of all cores) and the RAM used directly by the `kvision` process and its related downloader subprocesses.
  * **GPU / VRAM**: Graphics card core utilization (in %) and the amount of VRAM graphic memory occupied by rendering and hardware decoding (supports full listing of GPU processes using the XML parser from `nvidia-smi`).
  * **NETWORK (Net)**: Actual download transfer speed of the application from all active live players, archive players, and recording download processes.
* **Multithreading (Stutter-Free)**: Process and GPU data collection runs on a separate system thread (`StatsWorker`). This prevents any micro-stuttering in video rendering (no frame drops).
* **Pin Feature**: Clicking the **"Pin"** button (pin icon) locks the panel in its expanded state.
* **Aesthetics**: The charts feature bright, neon-green borders, a gradient fill under the chart curve, and a balanced 35% background transparency to ensure text readability.

---

## 7. Playback Archive Player

Available by clicking the clock/play icon next to a specific camera or recorder. It allows for simultaneous viewing of archived recordings from multiple Hikvision cameras in full time synchronization.

### Timeline & Controls:
* **Quick Start (15 minutes back)**: When opening the archive from the live view, the player automatically starts from a moment falling **exactly 15 minutes before the current system time** (instead of starting at midnight). This allows for immediate viewing of an event that just occurred.
* **Navigation**: The timeline can be scrolled left and right by dragging it with the left mouse button.
* **Zoom (Scaling)**: You can smoothly change the timeline scale with the mouse scroll wheel (or Zoom buttons) – from viewing the entire day down to a precise 10-minute precision view.
* **Quick Zoom Shortcuts**: The bottom control bar features dedicated circular icon buttons to instantly scale the timeline view:
  * **„1h” icon**: Zooms the timeline in for detailed inspection over a 1-hour span.
  * **„8h” icon**: Zooms the timeline to display an 8-hour span.
  * **„24h” icon**: Resets zoom to fit the full 24-hour day on a single screen.
  * **Center (Target) icon**: Immediately centers the timeline so that the red playback indicator is exactly in the middle of the screen (replacing the old text button).
* **Date Navigation (Calendar & Days)**: Controls beside the displayed date allow rapid jumps:
  * **„<” (Previous Day)** and **„>” (Next Day)** buttons: Let you jump 24 hours back or forward instantly without opening the calendar dialog.
  * **Calendar icon**: Opens the calendar popup to select a specific date.
  * **Refresh icon**: Forces a fresh search of recordings. Clicking it sweeps the local cache of recording availability segments for all active channels and submits new queries to the NVR, which is highly useful to load files recorded just a few moments ago (replacing the old text button).
  * **Today (Today's date/number) icon**: Instantly jumps back to the current day (replacing the old text button).
* **Playback Speed Shortcuts**:
  * **„1x”, „2x”, and „4x” icons**: Instantly change the playback speed multiplier.
* **VCR Jump Buttons**:
  * **„15”, „45”, and „60” icons with circular arrows**: Let you quickly skip backward or forward by the specified number of seconds.
* **Recording Availability Bars**: Colored bars representing the found video segments on the recorder's disk are rendered below the timeline. A caching system prevents them from flickering while dragging.
* **Auto-follow (Indicator tracking)**: The playback indicator (vertical red line) is constantly monitored. If the indicator goes outside the visible range of the timeline, the view will automatically scroll to center it. This option is intelligently locked during manual indicator dragging by the user.

### Camera Side Panel in Playback Window
A vertical side list on the right edge of the player lists all configured NVRs and their camera channels:
* **Toggling Channels**: Clicking any camera channel on the list adds it as an active playback slot on the timeline (spawning a video player). Clicking it again removes the channel.
* **Channel Context Menu**: Right-clicking an active video slot in the playback grid opens a menu to:
  * Toggle video quality (Main Stream / Sub Stream).
  * Close/remove the active player from the archive playback.

---

## 8. Downloading Recordings (Downloader)

From the Playback Archive window, you can download selected segments of recordings directly to your computer's drive as MP4 files:
1. Click the download icon (downward arrow) next to the selected camera.
2. Select the time range (start and end of the recording).
3. Select the destination file save location.
4. Click **Download**.

### Advanced Download Features:
* **Sequential Segment Downloading (1GB parts)**: The program automatically splits your time range query into physical file segments (roughly 1GB each on the NVR drive) and downloads and converts them one by one (using temporary `.pspart` files that are converted directly to `.mp4` format). This ensures highly stable downloads of long duration ranges without memory overflow or FFmpeg conversion hangs.
* **Overall Progress Visualization**: The progress bar (bright teal color) displays the overall download progress for the camera across all segments. The status text overlaid on the progress bar shows the current part and percentages, e.g., `Downloading part 1 of 3... 45% (Overall: 15%)`, with an outline styling to guarantee legibility on any background.
* **Filename IP Cleaning**: Video filenames (and live/archive snapshots) are automatically stripped of NVR/DVR IP addresses to keep them clean and human-readable (e.g. `4_Wejscie_glowne_2026-06-15.mp4` instead of `<RECORDER_IP>_4_Wejscie...`).

---

## 9. Advanced Settings and Customization in Options Sidebar

The sliding options panel (`SideBar`) consists of six dedicated configuration tabs:

### 1. Viewport Details (Monitor Icon)
Displays advanced parameters of the currently selected grid tile. Allows you to:
* Type a custom **Primary Stream URL** (RTSP/ONVIF) and a **Secondary Backup URL** for manual configurations.
* Toggle muting/unmuting the audio channel of the selected camera feed.
* Input advanced decoder overrides in the **FFmpeg Options Override** text box.
  > [!TIP]
  > For the fastest stream connection and maximum stability over RTSP, the recommended parameters are:
  > ```ini
  > -analyzeduration 0 -probesize 500000 -rtsp_transport tcp
  > ```

### 2. Layout & Grid Tools (Sliders Icon)
Advanced screen grid customization options:
* Quick toggle for Full Screen mode.
* **Asymmetric Cell Merging (Merge Highlighted Cells)**: A highly advanced layout editor. Hold **Ctrl** or **Shift** and click to select multiple adjacent tiles on the grid, or use your keyboard by holding **Shift** and navigating with the **Arrow keys**, then click "Merge Highlighted Cells" to fuse them into a single larger viewport. This allows you to create fully custom asymmetric grid designs (e.g., one huge camera panel with smaller feeds surrounding it).

### 3. Recorders (Server Icon)
Full configuration manager for connections to Hikvision NVR/DVR devices (described in detail in Section 3).

### 4. Presets (Star Icon)
Manager for your saved grid layouts and camera assignments. Allows creating empty grid templates, changing their order, toggling their top-bar visibility (via the "Visible" switch), or activating them in the current window.

### 5. Settings (Gear Icon)
Allows adjusting global application settings:
* **Allow running multiple instances**: Checking this box allows launching multiple parallel copies of the KVision process (by default, it restricts runs to a single active instance).
* **Auto-collapse settings**: Customizes sliding animation timing for the top bar and statistics panel.
* **Allow swapping viewports**: The checkbox *„Allow swapping viewport places”* enables you to rearrange camera positions on the grid on the fly (Right-click source tile -> Choose "Swap viewports" -> Left-click target tile).
* **Right-click permissions**: Switches to lock/unlock interactive controls in the right-click context menu (Enable context menu, Allow swapping viewports, Enable 'Remove camera' option, Allow changing viewport settings, Enable stream Main/Sub quality selection).
* **Auto Unmute**: Automatically unmutes the audio stream of the active viewport when entering Full Screen mode.
* **Hide Cursor in Full Screen**: The checkbox *„Hide cursor in full screen mode”* automatically hides the mouse cursor after a brief inactivity period during fullscreen viewing to ensure an unobstructed view.
* **Language selection**: Instantly switches interface translation (System default, Polish, English).
* **UI Preferences**: Hide/show viewport status labels or control badges (such as auto-hiding the control overlays in the bottom right corner of tiles unless hovering).

### 6. Changelog (Clock/Document Icon)
Presents an interactive timeline showing the complete release history, updates, bug fixes, and feature additions of KVision, ensuring you have direct access to program updates details.

---

## 10. Keyboard Shortcuts and Mouse Controls

### Keyboard shortcuts:
| Key / Shortcut | Action |
|---|---|
| **F** / **F11** | Toggle Full Screen mode. |
| **M** | Mute / unmute audio (works for the active camera with audio). |
| **Space** | Play / Pause playback in the Playback Archive window. |
| **Alt + 1** to **Alt + 9** | Quick switch to a preset/layout at indices 1 to 9. |
| **Alt + Left Arrow** | Quick switch to the previous preset/layout in the collection. |
| **Alt + Right Arrow** | Quick switch to the next preset/layout in the collection. |
| **Arrow keys (Up/Down/Left/Right)** | Navigate and move the active focus/selection between camera viewports. |
| **Shift + Arrow keys** | Select multiple adjacent camera viewports simultaneously (used for cell merging, etc.). |
| **Ctrl + N** | Open a new, independent auxiliary window. |
| **+** / **-** | Zoom in / Zoom out (PTZ-capable Hikvision cameras). |
| **Esc** | Exit Full Screen mode / cancel active viewport selection. |

### Mouse interaction:
* **Left mouse button**:
  * **Double-click** on a camera viewport in the grid maximizes it to full screen. Another double-click restores the grid view.
  * Drag the timeline in the Playback window to navigate.
* **Right mouse button (Context Menu)**:
  * Opens a quick settings menu for the selected viewport (allows removing the camera from the grid, changing between Main/Sub streams, or accessing individual display parameters).
* **Mouse Scroll Wheel**:
  * Adjusts scale (Zoom) of the timeline in the playback archive player.

---

## 11. Taking Snapshots and Path Configuration

The application allows you to quickly capture high-quality snapshots from any camera viewport in both Live View and Playback Archive mode.

### Taking Snapshots:
1. A camera icon overlay button is available in the bottom-right corner of each viewport (detailed in Section 4).
2. Clicking the camera icon captures the frame and saves it as a JPEG image (quality 98 - virtually lossless).
3. A successful capture is confirmed by the camera icon flashing orange (`#ff7a00`) for exactly 1 second.
4. **Full Resolution**: In Playback Archive mode, snapshots are saved at the stream's full native source resolution directly from the decoder's frame buffer, regardless of the active viewport size on screen or display scaling.

### Saving Path Configurations:
1. Go to the **Settings** tab (gear icon in the sidebar).
2. Under the **Saving** ("Zapis") section, you can configure the default paths:
   * **Default snapshots path**: Folder where snapshots will be saved (defaults to `~/Obrazy/CCTV`).
   * **Default recordings path**: Folder where downloaded MP4 videos will be saved (defaults to `~/Wideo/CCTV`).
3. Clicking the `...` browser button opens your operating system's native folder selector (Breeze in KDE).
4. **Browser Button Behavior**: The directory picker opens precisely at the path typed in the text field (if it exists). If the field is empty, invalid, or pointing to a folder you don't have access to, the dialog falls back and opens at your home directory (`~/`).

### User Interface Settings (UI):
1. Go to the **Settings** tab (gear icon in the sidebar) or open the **Options** ("Opcje") sidebar.
2. In the **User Interface Settings** section, you can customize the visibility of elements overlaid on the camera kafelki/viewports:
   * **Show channel status in the top left corner of the viewport** (default enabled) — Displays stream loading, playing, and connection status information.
   * **Show camera info in the bottom left corner of the viewport** (default enabled) — Displays the camera name retrieved from the Hikvision recorder.
   * **Show control icons in the bottom right corner of the viewport only when hovering** (default enabled) — Automatically hides the control button panel (snapshot, archive, 1:1 pixel-to-pixel, region zoom) when the mouse cursor is outside of that specific camera viewport. The icons appear instantly as soon as you move your mouse over the viewport (no click required) and disappear when leaving, maximizing the visibility of your camera streams.
   * **Show info fields only when hovering** (default disabled) — Analogous option that hides the status on top-left and name on bottom-left of viewports, displaying a completely clean camera stream unless the cursor is moved over that specific camera tile.
