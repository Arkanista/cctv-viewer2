# CCTV Viewer 2

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

> [!IMPORTANT]
> **Important Disclaimer & User Information:**
> * **Original Author:** This project is a fork and modification of the original [cctv-viewer](https://github.com/iEvgeny/cctv-viewer) created by **Evgeny S. Maksimov** ([@iEvgeny](https://github.com/iEvgeny)).
> * **Built with AI Assistance:** This version has been heavily modified and built using **Gemini** and **Claude** AI assistants.
> * **Not a Professional Programmer:** I am not a professional software developer. This is a personal project created for my own needs.
> * **Use At Your Own Risk:** The program is provided "as is", without warranty of any kind. You use this software entirely at your own responsibility and risk.
> * **Do Not Contact Me for Support:** Please do not contact me with support questions, bug reports, or help requests. I cannot and will not provide technical support.
> * **NEVER Run As Root:** For security and safety reasons, **NEVER run this program as root or with administrator privileges**. 
>
> **Project Goal:** This project was created for the sole purpose of allowing me to completely abandon Windows on my system by replacing the essential camera viewing and playback functionality of the Hikvision iVMS-4200 software on Linux.

---

## About CCTV Viewer 2

**CCTV Viewer 2** is a high-performance desktop application designed for simultaneous viewing of live video feeds (RTSP/ONVIF) and deep integration with Hikvision NVR/DVR video recorders (both Live view and synchronized Playback archives).

It is designed for Linux users who need a robust, lightweight, and smooth alternative to bloated proprietary software.

---

## Detailed Application Features

### 📺 Live View Grid & Viewport Interactions
* **Camera Assignment (Select-and-Click)**: Select a viewport in the main grid layout to focus it, then click the **"+" (Add)** button on any camera in the NVR/DVR list to assign it.
* **Viewport Swapping**: Swap camera feeds between two grid viewports by selecting the **"Swap viewports" ("Zamień miejscami")** option in the right-click context menu of the source viewport and then clicking on the target viewport.
* **Camera Removal**: Quickly clear/remove a camera stream from any grid viewport using the right-click context menu (**"Remove camera" / "Usuń kamerę"**) with a safety confirmation dialog.
* **Double-Click to Maximize**: Double-click any camera viewport in the grid to maximize it to full screen. Double-click again to restore the grid layout.
* **Individual Viewport Settings**: Customize RTSP transport protocols, volume levels, and display properties for each viewport individually via the context menu (**"Change settings" / "Zmień ustawienia"**).
* **Multi-Monitor & Auxiliary Windows**: Spawn multiple independent auxiliary viewport windows (via the **"New Window" / "Nowe Okno"** button or `Ctrl+N` shortcut) to display different camera grid layouts simultaneously across multiple screens or monitors.
* **Real-Time Bidirectional Configuration Sync**: Instantly synchronizes NVR settings, local camera names, and layouts collection definitions bidirectionally in real-time between the main window and all open auxiliary windows using high-performance file watching (`QFileSystemWatcher`). Window positioning and active layout selection indices remain strictly isolated per window via dynamic, automatic unique window ID allocation.


### 🔍 Advanced Image Controls & Zooming
* **Interactive Viewport Zooming (Region Selection)**: Enter zoom mode by clicking the magnifying glass icon on any viewport. Click and drag a rectangular marquee over the video stream to crop and zoom into that specific region. Click the icon again to reset the zoom.
* **1:1 Pixel Mapping Mode**: View camera streams in their native pixel-to-pixel resolution without any scaling distortion.
* **Middle-Click Panning**: While in 1:1 mode, click and hold the middle mouse button (scroll wheel) to pan around the enlarged stream.
* **Mouse Wheel Zoom (Fullscreen)**: Scale the stream dynamically in fullscreen mode by holding the `Ctrl` key and scrolling the mouse wheel.

### 🔌 Hikvision NVR/DVR Deep Integration
* **Auto-Discovery**: Enter your NVR/DVR IP address and credentials to automatically discover and list all active camera channels.
* **Automatic NVR Preset Grid**: Click **"Generate Grid"** in the recorders panel to automatically generate a tailored viewport layout (preset) mapping all discovered cameras to an optimal grid size.
* **Dynamic Quality Selection**: Manually toggle between **Main Stream** (high resolution) and **Sub Stream** (low bandwidth/CPU load) for any viewport via the context menu to save system resources and network bandwidth.
* **Local Camera Renaming (Custom Names)**: Clicking the edit icon (pencil) on a camera tile in the recorder channel list allows setting a custom, local name for that camera. The name update is immediately reflected on the tile, live players, and playback timeline. Custom names are saved locally in the settings JSON and do not alter the physical NVR device. The custom name can be reset to the NVR default at any time.

### ⏱️ Synchronized Playback Archive
* **Multi-Camera Synchronization**: Play back archived video recordings from multiple Hikvision recorders/cameras simultaneously in perfect time synchronization.
* **Interactive Timeline**: Drag the timeline horizontally to navigate through time. Scale the timeline smoothly with the mouse wheel (from a full 24-hour view down to a precise 10-minute resolution).
* **Footage Availability Cache**: Visual colored bars indicating recording segments on NVR storage are cached dynamically to eliminate flickering during timeline manipulation.
* **Timeline Auto-Follow**: The timeline view automatically scrolls to keep the red playback indicator centered, pausing intelligently when the user drags the timeline manually.
* **Manual Re-Center**: Click the **"Center"** button to instantly snap the timeline back to center around the active playback indicator.
* **15-Min Quick Check**: Click the archive icon next to a camera or recorder in the live view to automatically start playback starting **exactly 15 minutes before the current system time**, allowing you to instantly inspect recent events.

### 📸 Snapshot Capture & Path Configuration
* **Instant Snapshot Capturing**: Take high-quality, virtually lossless snapshots (JPEG format, quality 98) directly from any active viewport in both Live View and Playback Archive.
* **Camera Icon Overlay**: Viewports feature a subtle camera overlay icon in the toolbar. Clicking it flashes the icon orange (`#ff7a00`) for exactly 1 second to confirm successful capture.
* **High-Resolution Archive Captures**: Playback snapshots are captured at the stream's full native source resolution directly from the decoded frame buffer in memory, bypassing any display scaling or window size constraints.
* **Custom Paths Configuration**: Configure default storage paths for snapshots (`~/Obrazy/CCTV` by default) and downloaded videos (`~/Wideo/CCTV` by default) inside the **"Saving" ("Zapis")** section of the Settings panel.
* **Native KDE Directory Browser**: Click the `...` browser buttons to open a native-style KDE directory selector. The dialog opens precisely at the folder currently shown in the text input, falling back to the user's home folder (`~/`) if the field is empty or points to a non-existent path.

### 📥 Archive Recording Downloader
* **Direct MP4 Downloader**: Download segments of archived footage directly to your local drive.
* **Flexible Timeframe Range**: Select precise start/end points for the export.
* **Visual Progress Bar**: Track the download process in real-time, with download bandwidth correctly accounted for in the System Statistics panel.

### 📊 Multi-Threaded System Statistics Panel
* **Slide-Out Overlay**: Hover and slide the left edge of the screen to reveal a diagnostic monitoring overlay.
* **Metrics Tracked**:
  * **CPU & RAM**: Total system CPU load (%) and the memory consumed by `cctv-viewer2` and its download subprocesses.
  * **GPU & VRAM**: Core graphics card utilization and video memory usage (real-time XML parsing of `nvidia-smi` data, filtering only relevant process allocations).
  * **Network Bandwidth**: Live download speed aggregated from all active video players and download subprocesses.
* **Pin Feature**: Click the pin icon to keep the stats panel locked open, or let it slide away automatically.
* **Stutter-Free Video Rendering**: Calculations are performed on a separate thread (`StatsWorker`) to guarantee zero frames are dropped during 60 FPS video rendering.

### 🛠️ Global Application Settings & UI
* **Auto-Collapsing Top Bar**: The top options toolbar automatically collapses when the mouse leaves its boundary to maximize video workspace. This behavior is toggleable in Settings or directly using the pin icon on the top bar.
* **Top Bar Controls**: Compact layout controls on the top bar: fullscreen button (with green visual state), window minimize button (with cyan/blue icon), grid locking switch, options, and a hamburger menu for advanced options.
* **Close Confirmation**: Intercepts both system window close buttons and exit button actions, requesting a Polish/English confirmation before quitting.
* **Custom Layout Presets**: Create custom layout presets with configurable row and column counts (e.g., 2x2, 3x3, 4x4).
* **Global Shortcuts**: Complete control via keyboard hotkeys:
  * `F11`: Toggle fullscreen.
  * `M`: Mute/unmute active viewport audio.
  * `Alt + Left` / `Alt + Right`: Switch layouts.
  * `Alt + 1` to `Alt + 9`: Instant preset switching.
* **Multilingual UI**: Live translation switching between English and Polish.

---

## Screenshots

| Main Window Grid (5x5) | Main Window (Obfuscated Feeds) |
| :---: | :---: |
| <a href="images/screenshot_main_grid.png"><img src="images/screenshot_main_grid.png" width="350" alt="Main Window Grid"/></a> | <a href="images/screenshot_main_obfuscated.png"><img src="images/screenshot_main_obfuscated.png" width="350" alt="Main Window Obfuscated"/></a> |

| Playback Archive Timeline | System Statistics Panel (Slide-out) |
| :---: | :---: |
| <a href="images/screenshot_archive_playback.png"><img src="images/screenshot_archive_playback.png" width="350" alt="Playback Archive"/></a> | <a href="images/screenshot_stats_overlay.png"><img src="images/screenshot_stats_overlay.png" width="350" alt="System Statistics"/></a> |

| NVR Settings & Recorders | NVR Cameras List |
| :---: | :---: |
| <a href="images/screenshot_nvr_settings.png"><img src="images/screenshot_nvr_settings.png" width="350" alt="NVR Settings"/></a> | <a href="images/screenshot_nvr_cameras.png"><img src="images/screenshot_nvr_cameras.png" width="350" alt="NVR Cameras"/></a> |

| Archive Timeframe Selection | General Application Settings |
| :---: | :---: |
| <a href="images/screenshot_archive_setup.png"><img src="images/screenshot_archive_setup.png" width="350" alt="Archive Setup"/></a> | <a href="images/screenshot_app_settings.png"><img src="images/screenshot_app_settings.png" width="350" alt="App Settings"/></a> |

---

## System Requirements & Dependencies

### Hardware Environment (Tested On)
The application has been extensively developed and tested across multiple hardware configurations on CachyOS (Arch Linux derivative) running **KDE Plasma 6.6.5 on Wayland**:

**Machine 1 (High-end Desktop):**
- **Operating System:** CachyOS Linux x86_64
- **Kernel:** Linux 7.0.11-1-cachyos
- **Desktop Environment:** KDE Plasma 6.6.5 (KWin Wayland)
- **CPU:** AMD Ryzen 9 5950X (16 Cores / 32 Threads)
- **System Memory:** 64 GB RAM
- **Graphics Card:** NVIDIA GeForce RTX 5070 Ti (16 GB VRAM)

**Machine 2 (Production Environment):**
- **Operating System:** CachyOS Linux x86_64
- **Kernel:** Linux 7.0.11-1-cachyos
- **Desktop Environment:** KDE Plasma 6.6.5 (KWin Wayland)
- **CPU:** Intel Core i7-9700F (8 Cores @ 4.70 GHz)
- **System Memory:** 16 GB RAM
- **Graphics Card:** NVIDIA GeForce GTX 1070 Ti (8 GB VRAM)
- **Performance Details:** Running on a 4K monitor displaying a 30-camera grid view.
  - **CPU System Usage:** ~20%
  - **GPU Utilization:** 25-30%
  - **Total System RAM Usage:** ~5 GB (Application consumes ~2-2.5 GB)
  - **VRAM Usage:** 1-2 GB

**Machine 3:**
- **Operating System:** CachyOS Linux x86_64
- **Kernel:** Linux 7.0.11-1-cachyos
- **Desktop Environment:** KDE Plasma 6.6.5 (KWin Wayland)
- **CPU:** AMD Ryzen 5 5600X (6 Cores / 12 Threads @ 4.65 GHz)
- **System Memory:** 64 GB RAM
- **Graphics Card:** NVIDIA GeForce RTX 3060 Ti (8 GB VRAM)

### Software Dependencies
To build and run the application, the following packages are required:

* **Runtime Dependencies:**
  - `qt5-declarative` (Qt5 QML module)
  - `qt5-multimedia` (Qt5 Multimedia module)
  - `qt5-quickcontrols` (Qt5 Quick Controls 1)
  - `qt5-quickcontrols2` (Qt5 Quick Controls 2)
  - `qt5-graphicaleffects` (Qt5 Graphical Effects)
  - `qt5-svg` (Qt5 SVG icon rendering)
  - `ffmpeg` (for media demuxing and decoding)
  - *Note: Hikvision SDK shared libraries are pre-bundled under `src/hikvision_sdk/lib/` and automatically set up via the build configuration or Pacman package.*

* **Build Dependencies:**
  - `cmake` (>= 3.10)
  - `qt5-tools` (for translation compilation `lrelease`)
  - `git`

---

## Getting Started

To clone this repository, make sure you include the submodules:
```bash
git clone --recurse-submodules https://github.com/arkanista/cctv-viewer2.git
```

### Pre-compiled Arch Linux Package (Arch Linux / CachyOS)

If you are running Arch Linux or CachyOS, you can skip compilation and install the pre-compiled Pacman package directly from the latest release:

* **[Download cctv-viewer2-2.1.9-2-x86_64.pkg.tar.zst](https://github.com/Arkanista/cctv-viewer2/releases/download/v2.1.9/cctv-viewer2-2.1.9-2-x86_64.pkg.tar.zst)**

To install the downloaded package:
```bash
sudo pacman -U cctv-viewer2-2.1.9-2-x86_64.pkg.tar.zst
```

### Building from Source (Arch Linux / CachyOS)

The easiest and recommended way to build and install the application from source on Arch-based distributions is by using `makepkg`, which automatically resolves and installs all required dependencies.

1. Navigate to the Arch packaging directory:
   ```bash
   cd cctv-viewer2/packaging/arch
   ```
2. Build the package (the `-s` flag will automatically download and install all missing dependencies via `pacman`, and `-i` will install the built package):
   ```bash
   makepkg -si
   ```

### Manual Build using CMake (Any Linux distribution)

If you are not using Arch Linux, you can build the application manually using CMake.

1. **Install Dependencies:** Ensure you have installed all required runtime and build dependencies listed above using your distribution's package manager.
   For Arch/CachyOS:
   ```bash
   sudo pacman -S base-devel cmake qt5-declarative qt5-multimedia qt5-quickcontrols qt5-quickcontrols2 qt5-svg qt5-graphicaleffects qt5-tools ffmpeg git
   ```
2. **Configure the build directory:**
   ```bash
   cd cctv-viewer2
   cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
   ```
3. **Compile the project:**
   ```bash
   cmake --build build -j$(nproc)
   ```
4. **Install the application:**
   ```bash
   sudo cmake --install build
   ```

For detailed usage instructions, check out the documentation files:
- [English User Manual (INSTRUCTIONS.md)](INSTRUCTIONS.md)
- [Polish User Manual (INSTRUKCJA.md)](INSTRUKCJA.md)

---

## License

This project is licensed under the GPL v3 License.
