# How to install OpenHeroes1 on macOS

Sections 1 to 4 get you playing. Section 5 is only for packaging the game as an `.app`, an Android `.apk` or an iOS app.

> [!NOTE]
> This guide has only been tested with Godot 4.7.2.
> If you use a different version, or keep the project in a different location or under a different name (`~/Documents/HOMM1`, for example), change the file names and paths in the guide to match.

---

## 1. Get Godot 4.7.2

1. Open <https://godotengine.org/download/archive/4.7.2-stable/> and download **`Godot_v4.7.2-stable_macos.universal.zip`**. Take the Standard version, not the .NET / C# one. It runs on both Apple Silicon and Intel Macs.
2. Double-click the zip in **Finder** to extract `Godot.app`.
3. Drag `Godot.app` into your **Applications** folder. The commands and build scripts in this guide expect it there.

If macOS refuses to open Godot, see [Troubleshooting](#6-troubleshooting).

---

## 2. Get the project

1. On this repository's GitHub page, click the green **`<> Code`** button and choose **Download ZIP**.
2. Double-click the zip in **Finder**. It extracts to a folder named `openheroes1-main`.

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

Download `hommdemo-cd.zip` (about 55 MB) from <https://www.dosgamesarchive.com/file/heroes-of-might-and-magic-a-strategic-quest/hommdemo-cd> and put it in `external_resources`. Leave it zipped. If Safari unzips it for you, download it with another browser or turn off **Open "safe" files after downloading** in Safari's settings.

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

1. In **Finder**, right-click the project folder and choose **New Terminal at Folder** (it may be under **Services**). A Terminal window opens in the project folder.

   If you do not have that menu item, open **Terminal**, type `cd` and a space, drag the project folder into the window, and press <kbd>Return</kbd>.
2. Copy this line into Terminal:
   ```bash
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/setup.gd
   ```
3. Press <kbd>Return</kbd> and wait a few minutes.

Red errors in the first lines are normal on the first run. When it prints `Setup Complete!`, you are ready to play.

With the demo, add `-- --with-music --with-video` (either or both) to the end of that line to also convert its music and cinematics:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/setup.gd -- --with-music --with-video
```

---

## 4. Play

### From Terminal

1. Open Terminal in the project folder, as in [Step 2](#step-2-run-the-setup).
2. Run:
   ```bash
   /Applications/Godot.app/Contents/MacOS/Godot --path .
   ```

The game opens on the main menu at its original 640×480, scaled to fit your screen.

### From the Godot window

1. Open **Godot** from your Applications folder.
2. In the **Project Manager**, click **Import**, select `project.godot` in the project folder, and click **Import & Edit**.
3. Press <kbd>F5</kbd> or <kbd>Cmd</kbd> + <kbd>B</kbd> (or click the **Play** button in the top-right corner).

---

## 5. Export a build (optional)

This packages the game so it runs without Godot. Run the commands below in a Terminal window opened in the project folder.

### 5.1 Export templates

Needed once, for every kind of export. Open Godot, click **Editor** → **Manage Export Templates**, then **Download and Install** (about 1 GB). The templates must match your Godot version exactly.

### 5.2 macOS `.app`

```bash
tools/build_macos.sh
```

Or in the Godot window: **Project** → **Export...**, select **macOS**, click **Export Project...**, uncheck **Export With Debug**, and save as `build/homm1-macos/homm1.zip`.

Either way you get `build/homm1-macos/homm1.zip`. Double-click it to extract `homm1.app`, then open the app to play. To share the game, send the zip.

### 5.3 Android `.apk`

The preset builds for 64-bit ARM devices (`arm64-v8a`). Set up once, with [Homebrew](https://brew.sh):

```bash
brew install openjdk@17
brew install --cask android-commandlinetools
sdkmanager --sdk_root="$HOME/Library/Android/sdk" "platform-tools" "build-tools;35.0.1" "platforms;android-35" "cmdline-tools;latest"
sdkmanager --sdk_root="$HOME/Library/Android/sdk" --licenses
```

If you already have Android Studio, skip the last three lines. Open its **SDK Manager** instead and install **Android SDK Platform 35** and **Android SDK Build-Tools 35.0.1**.

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

### 5.4 iOS (iPhone and iPad)

You need **Xcode** from the Mac App Store and an Apple ID. A free Apple ID is enough to play on your own device.

1. Export the Xcode project:
   ```bash
   mkdir -p build/homm1-ios
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-debug "iOS" build/homm1-ios/homm1.ipa
   ```
2. Open it in Xcode:
   ```bash
   open build/homm1-ios/homm1.xcodeproj
   ```
3. In Xcode, click the **homm1** project at the top of the left sidebar and open the **Signing & Capabilities** tab. Check **Automatically manage signing** and choose your Apple ID under **Team**. If Xcode reports a bundle identifier conflict, change the **Bundle Identifier** to one of your own.
4. Plug in your iPhone or iPad (or choose a Simulator in Xcode's top toolbar) and click the **Run** button, or press <kbd>Cmd</kbd> + <kbd>R</kbd>.
5. The first time, iOS says the developer is untrusted. On the device, open **Settings** → **General** → **VPN & Device Management**, tap your Apple ID, and tap **Trust**. Then open the game.

---

## 6. Troubleshooting

- **macOS will not open Godot or the exported game ("is damaged" or "cannot be verified")**
  - Open **System Settings** → **Privacy & Security** and click **Open Anyway**. Or clear the download flag in Terminal, for Godot or for the exported game:
    ```bash
    xattr -cr /Applications/Godot.app
    xattr -cr build/homm1-macos/homm1.app
    ```

- **The setup says `No copy of HOMM1 found`**
  - Check that `external_resources` sits next to `project.godot` and holds `hommdemo-cd.zip` or your `homm1game` folder. See [Section 3](#3-set-up-the-game-assets-required).

- **The main menu says `Game data not built`, or the screen is black on startup**
  - The assets were not built yet. Follow [Section 3](#3-set-up-the-game-assets-required).

- **Error: `No export template found at the expected path`**
  - The export templates must match your Godot version (`4.7.2.stable`) exactly. See [Section 5.1](#51-export-templates).
