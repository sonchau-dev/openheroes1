# How to install OpenHeroes1 on Ubuntu

Sections 1 to 4 get you playing. Section 5 is only for packaging the game as a Linux build or an Android `.apk`.

On a Steam Deck, follow the [Steam Deck guide](steamdeck.md) instead.

> [!NOTE]
> This guide has only been tested with Godot 4.7.2.
> If you use a different version, or keep the project in a different location or under a different name (`~/Documents/HOMM1`, for example), change the file names and paths in the guide to match.

---

## 1. Get Godot 4.7.2

1. Open <https://godotengine.org/download/archive/4.7.2-stable/> and download **`Godot_v4.7.2-stable_linux.x86_64.zip`**. Take the Standard version, not the .NET / C# one.
2. Right-click the zip in **Files** (the file manager) and extract it. You get one file, `Godot_v4.7.2-stable_linux.x86_64`.
3. In your Home folder, make a folder named `Applications`. Move the file into it and rename it to `godot`.
4. Open a terminal and run this, so the file is allowed to run:
   ```bash
   chmod +x ~/Applications/godot
   ```

From here on, Godot is `~/Applications/godot`. The commands and the Android build script in this guide expect it there.

Also make sure the Vulkan library is installed:

```bash
sudo apt install libvulkan1
```

---

## 2. Get the project

1. On this repository's GitHub page, click the green **`<> Code`** button and choose **Download ZIP**.
2. Right-click the zip and extract it. It extracts to a folder named `openheroes1-main`.

The folder that holds `project.godot` is the **project folder**. Every step below happens there.

*(If you use Git, `git clone` the repository instead. The cloned folder is the project folder.)*

---

## 3. Set up the game assets (required)

> [!WARNING]
> Original Heroes of Might and Magic I artwork, sounds, and map files are copyrighted by Ubisoft (originally developed by New World Computing / The 3DO Company) and are **not included** in this repository.
> **The game will not launch until you build the assets from your own copy of the game, as below.**

### Step 1: Put a copy of HOMM1 in the project

In the project folder, make a new folder named `external_resources`, next to `project.godot`.

Then pick **one** of the two options below.

#### Option A: The free 1995 demo

Download `hommdemo-cd.zip` (about 55 MB) from <https://www.dosgamesarchive.com/file/heroes-of-might-and-magic-a-strategic-quest/hommdemo-cd> and put it in `external_resources`. Leave it zipped.

```
openheroes1-main/
├── project.godot
└── external_resources/
    └── hommdemo-cd.zip
```

The demo has a small glitch in one frame of the troll's walk. A full copy of the game does not.

#### Option B: Your own copy

From GOG, an original CD-ROM or another source. Copy your game folder into `external_resources` and name it `homm1game`. The folder must contain the game's own files, including `heroes.agg` and a `maps` folder. A disc image (`.iso`, `.bin`, `.cue`) or an installer will not work.

```
openheroes1-main/
├── project.godot
└── external_resources/
    └── homm1game/
        ├── data/
        │   └── heroes.agg
        └── maps/
```

### Step 2: Run the setup

1. Open the project folder in **Files**. Right-click an empty space in it and choose **Open in Terminal**. A terminal opens in the project folder.
2. Copy this line into the terminal (paste with <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>V</kbd>):
   ```bash
   ~/Applications/godot --headless --path . --script tools/setup.gd
   ```
3. Press <kbd>Enter</kbd> and wait a few minutes.

Red errors in the first lines are normal on the first run. When it prints `Setup Complete!`, you are ready to play.

With the demo, add `-- --with-music --with-video` (either or both) to the end of that line to also convert its music and cinematics:

```bash
~/Applications/godot --headless --path . --script tools/setup.gd -- --with-music --with-video
```

---

## 4. Play

### From a terminal

1. Open a terminal in the project folder, as in [Step 2](#step-2-run-the-setup).
2. Run:
   ```bash
   ~/Applications/godot --path .
   ```

The game opens on the main menu at its original 640×480, scaled to fit your screen.

### From the Godot window

1. Open Godot: double-click `godot` in your `Applications` folder, or run `~/Applications/godot` in a terminal.
2. In the **Project Manager**, click **Import**, select `project.godot` in the project folder, and click **Import & Edit**.
3. Press <kbd>F5</kbd> (or click the **Play** button in the top-right corner).

---

## 5. Export a build (optional)

This packages the game so it runs without Godot. Run the commands below in a terminal opened in the project folder.

### 5.1 Export templates

Needed once, for every kind of export. Open Godot, click **Editor** → **Manage Export Templates**, then **Download and Install** (about 1 GB). The templates must match your Godot version exactly.

### 5.2 Linux build

```bash
mkdir -p build/homm1-linux
~/Applications/godot --headless --path . --export-release "Linux/X11" build/homm1-linux/homm1.x86_64
chmod +x build/homm1-linux/homm1.x86_64
```

Or in the Godot window: **Project** → **Export...**, select **Linux/X11**, click **Export Project...**, uncheck **Export With Debug**, and save as `build/homm1-linux/homm1.x86_64`.

Run `./build/homm1-linux/homm1.x86_64` to play. It needs `homm1.pck` beside it, so share the whole `homm1-linux` folder.

### 5.3 Android `.apk`

The preset builds for 64-bit ARM devices (`arm64-v8a`). Set up once:

1. **Java.**
   ```bash
   sudo apt install openjdk-17-jdk unzip curl
   ```
2. **Android SDK.** Either:
   - **With Android Studio:** open its **SDK Manager** and install **Android SDK Platform 35** and **Android SDK Build-Tools 35.0.1**. The SDK folder is `~/Android/Sdk`.
   - **Without it:**
     ```bash
     mkdir -p ~/Android/Sdk/cmdline-tools
     curl -Lo /tmp/cmdline-tools.zip "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
     unzip /tmp/cmdline-tools.zip -d ~/Android/Sdk/cmdline-tools
     mv ~/Android/Sdk/cmdline-tools/cmdline-tools ~/Android/Sdk/cmdline-tools/latest
     ~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root="$HOME/Android/Sdk" "platform-tools" "build-tools;35.0.1" "platforms;android-35" "cmdline-tools;latest"
     ~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root="$HOME/Android/Sdk" --licenses
     ```

Then build:

```bash
tools/build_android.sh
```

The script finds Java and the SDK, creates a debug keystore, tells Godot where they are, and writes `build/homm1-debug.apk`. If something is missing, it stops and says what.

To install it on your phone, do **one** of these:

- **Copy it over.** Copy `homm1-debug.apk` to your phone, open it there, and allow the install when Android asks.
- **Use a USB cable.** Plug the phone in, turn on **USB Debugging**, and run:
  ```bash
  tools/build_android.sh --install
  ```

---

## 6. Troubleshooting

- **`Permission denied` when running Godot**
  - The file is not allowed to run yet. Run `chmod +x ~/Applications/godot`.

- **The setup says `No copy of HOMM1 found`**
  - Check that `external_resources` sits next to `project.godot` and holds `hommdemo-cd.zip` or your `homm1game` folder. See [Section 3](#3-set-up-the-game-assets-required).

- **The main menu says `Game data not built`, or the screen is black on startup**
  - The assets were not built yet. Follow [Section 3](#3-set-up-the-game-assets-required).

- **Vulkan driver warnings or crashes**
  - If your graphics driver does not support Vulkan 1.2 or newer, start the game with the compatibility renderer:
    ```bash
    ~/Applications/godot --path . --rendering-driver opengl3
    ```

- **Error: `No export template found at the expected path`**
  - The export templates must match your Godot version (`4.7.2.stable`) exactly. See [Section 5.1](#51-export-templates).
