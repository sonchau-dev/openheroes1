# How to install OpenHeroes1 on Windows

Sections 1 to 4 get you playing. Section 5 is only for packaging the game as an `.exe` or `.apk`.

> [!NOTE]
> This guide was written with Godot 4.7.2.
> If you rename the project name and location (`C:\Documents\HOMM1`, for example), change the names and paths in the guide to match.

---

## 1. Get Godot 4.7.2

1. Open <https://godotengine.org/download/archive/4.7.2-stable/> and download **`Godot_v4.7.2-stable_win64.exe.zip`**. Take the Standard version, not the .NET / C# one.
2. Right-click the zip, choose **Extract All...**, and extract it somewhere easy to find, such as `C:\Godot\`.

Godot has no installer. The zip holds two files. Keep them in the same folder and **do not rename them**:

- `Godot_v4.7.2-stable_win64.exe` opens Godot in its own window.
- `Godot_v4.7.2-stable_win64_console.exe` is the one for commands typed in PowerShell.

If Windows Defender SmartScreen appears when you open Godot, click **More info**, then **Run anyway**.

---

## 2. Get the project

1. On this repository's GitHub page, click the green **`<> Code`** button and choose **Download ZIP**.
2. Right-click the zip and choose **Extract All...**.
3. Open the extracted folder and go into folders until you see a file named `project.godot`. Windows often extracts a folder inside a folder, such as `openheroes1-main\openheroes1-main`.

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

1. Open the project folder in **File Explorer**. Click in the address bar at the top, type `powershell`, and press <kbd>Enter</kbd>. A PowerShell window opens in the project folder.
2. In PowerShell, type `&` and a space. Then drag `Godot_v4.7.2-stable_win64_console.exe` from its folder into the PowerShell window. Windows types its full path for you.
3. Right after that path, type the rest of the command:
   ```
    --headless --path . --script tools/setup.gd
   ```
   The whole line looks like this:
   ```
   PS C:\Users\<YourUsername>\Downloads\openheroes1-main\openheroes1-main> & "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script tools/setup.gd
   ```
   The part before `>` is the folder PowerShell is in. It must be the project folder.
4. Press <kbd>Enter</kbd> and wait a few minutes.

Red errors in the first lines are normal on the first run. When it prints `Setup Complete!`, you are ready to play.

With the demo, add `-- --with-music --with-video` (either or both) to the end of that line to also convert its music and cinematics:

```
& "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script tools/setup.gd -- --with-music --with-video
```

---

## 4. Play

### From PowerShell

1. Open PowerShell in the project folder, as in [Step 2](#step-2-run-the-setup).
2. Tell PowerShell where Godot is. Type `Set-Alias godot` and a space, drag `Godot_v4.7.2-stable_win64_console.exe` into the window, and press <kbd>Enter</kbd>. The line looks like this:
   ```
   PS C:\Users\<YourUsername>\Downloads\openheroes1-main\openheroes1-main> Set-Alias godot "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
   ```
   From now on, `godot` runs Godot in this window. A new PowerShell window needs this line again.
3. Run:
   ```powershell
   godot --path .
   ```

The game opens on the main menu at its original 640×480, scaled to fit your screen.

### From the Godot window

1. Double-click `Godot_v4.7.2-stable_win64.exe`.
2. In the **Project Manager**, click **Import**, select `project.godot` in the project folder, and click **Import & Edit**.
3. Press <kbd>F5</kbd> (or click the **Play** button in the top-right corner).

---

## 5. Export a build (optional)

This packages the game so it runs without Godot. The commands below use the `godot` alias from [Section 4](#4-play), in a PowerShell window opened in the project folder.

### 5.1 Export templates

Needed once, for every kind of export. Open Godot, click **Editor** → **Manage Export Templates**, then **Download and Install** (about 1 GB). The templates must match your Godot version exactly.

### 5.2 Windows `.exe`

```powershell
New-Item -ItemType Directory -Force -Path build\homm1-windows
godot --headless --path . --export-release "Windows Desktop" build\homm1-windows\homm1.exe
```

Or in the Godot window: **Project** → **Export...**, select **Windows Desktop**, click **Export Project...**, uncheck **Export With Debug**, and save as `build\homm1-windows\homm1.exe`.

Double-click `homm1.exe` to play. It needs `homm1.pck` beside it, so share the whole `homm1-windows` folder. SmartScreen warns about a new unsigned program: click **More info**, then **Run anyway**.

### 5.3 Android `.apk`

The preset builds for 64-bit ARM devices (`arm64-v8a`). Set up once:

1. **Java.** Download the Windows `.msi` of **Eclipse Temurin 17 (LTS)** from [adoptium.net](https://adoptium.net) and install it with the default settings. Open a new PowerShell window afterwards so it can find Java.
2. **Android SDK.** Either:
   - **With Android Studio:** open its **SDK Manager** and install **Android SDK Platform 35** and **Android SDK Build-Tools 35.0.1**. The SDK folder is `C:\Users\<YourUsername>\AppData\Local\Android\Sdk`.
   - **Without it:** download **Command line tools** from the [Android Developer website](https://developer.android.com/studio#command-tools) and extract them so that `sdkmanager.bat` ends up at `C:\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat`. Then run this, and type `y` to accept the licences:
     ```powershell
     & "C:\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root=C:\Android\Sdk "platform-tools" "build-tools;35.0.1" "platforms;android-35"
     ```
     The SDK folder is `C:\Android\Sdk`.
3. **Debug keystore.** In PowerShell:
   ```powershell
   keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore "$env:USERPROFILE\debug.keystore" -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
   ```
4. **Tell Godot where they are.** In Godot, click **Editor** → **Editor Settings**, then **Export** → **Android** on the left, and set (with forward slashes `/`):
   - **Android SDK Path**: your SDK folder, such as `C:/Android/Sdk`
   - **Java SDK Path**: your JDK folder, such as `C:/Program Files/Eclipse Adoptium/jdk-17...`
   - **Debug Keystore**: `C:/Users/<YourUsername>/debug.keystore`
   - **Debug Keystore User**: `androiddebugkey`
   - **Debug Keystore Pass**: `android`

Then build:

```powershell
New-Item -ItemType Directory -Force -Path build
godot --headless --path . --export-debug "Android" build\homm1-debug.apk
```

To install it on your phone, do **one** of these:

- **Copy it over.** Copy `homm1-debug.apk` to your phone, open it there, and allow the install when Android asks.
- **Use a USB cable.** Plug the phone in, turn on **USB Debugging**, and run `adb.exe` from the SDK's `platform-tools` folder:
  ```powershell
  & "C:\Android\Sdk\platform-tools\adb.exe" install -r build\homm1-debug.apk
  ```

---

## 6. Troubleshooting

- **PowerShell returns to the prompt at once and Godot's output appears after it**
  - Use `Godot_v4.7.2-stable_win64_console.exe` instead of `Godot_v4.7.2-stable_win64.exe`, and make sure neither file was renamed.

- **`godot` is not recognized**
  - The alias lasts only for the PowerShell window it was typed in. Run the `Set-Alias` line from [Section 4](#4-play) again.

- **The setup says `No copy of HOMM1 found`**
  - Check that `external_resources` sits next to `project.godot` and holds `hommdemo-cd.zip` or your `homm1game` folder. See [Section 3](#3-set-up-the-game-assets-required).

- **The main menu says `Game data not built`, or the screen is black on startup**
  - The assets were not built yet. Follow [Section 3](#3-set-up-the-game-assets-required).

- **Error: `No export template found at the expected path`**
  - The export templates must match your Godot version (`4.7.2.stable`) exactly. See [Section 5.1](#51-export-templates).
