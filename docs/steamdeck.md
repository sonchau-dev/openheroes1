# How to install OpenHeroes1 on Steam Deck

Sections 1 to 4 get you playing in Desktop Mode. Section 5 adds the game to Gaming Mode.

> [!NOTE]
> This guide has only been tested with Godot 4.7.2.
> If you use a different version, or keep the project in a different location or under a different name (`~/Documents/HOMM1`, for example), change the file names and paths in the guide to match.

---

## 1. Get Godot 4.7.2

Everything in this guide happens in **Desktop Mode**. Press the **Steam** button, choose **Power**, then **Switch to Desktop**.

To type, press **Steam** + **X** to show the on-screen keyboard. A USB or Bluetooth keyboard and mouse make these steps easier.

1. Open a web browser, go to <https://godotengine.org/download/archive/4.7.2-stable/> and download **`Godot_v4.7.2-stable_linux.x86_64.zip`**. Take the Standard version, not the .NET / C# one.
2. In **Dolphin** (the file manager), right-click the zip and choose **Extract** → **Extract archive here**. You get one file, `Godot_v4.7.2-stable_linux.x86_64`.
3. In your Home folder, make a folder named `Applications`. Move the file into it and rename it to `godot`.
4. Open **Konsole** (the terminal) and run this, so the file is allowed to run:
   ```bash
   chmod +x ~/Applications/godot
   ```

From here on, Godot is `~/Applications/godot`. The commands and the build script in this guide expect it there.

---

## 2. Get the project

1. On this repository's GitHub page, click the green **`<> Code`** button and choose **Download ZIP**.
2. In Dolphin, right-click the zip and choose **Extract** → **Extract archive here**. It extracts to a folder named `openheroes1-main`.

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

1. Open the project folder in Dolphin. Right-click an empty space in it and choose **Open Terminal Here**. A terminal opens in the project folder.
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

## 5. Add the game to Gaming Mode

1. Open a terminal in the project folder, as in [Step 2](#step-2-run-the-setup), and run:
   ```bash
   tools/build_steamdeck.sh
   ```
   It packs the game into the folder `build/homm1-steamdeck/`, with a launcher named `start.sh`. It needs no export templates.
2. Open **Steam** and click **Games** → **Add a Non-Steam Game to My Library...**.
3. Click **Browse** and choose `build/homm1-steamdeck/start.sh` in the project folder. If you cannot see the file, set the file type filter to **All Files**.
4. Switch back to **Gaming Mode** and start the game from your library.

The game runs from `build/homm1-steamdeck/`, so do not move or delete that folder. Run the script again after you update the project.

---

## 6. Troubleshooting

- **`Permission denied` when running Godot**
  - The file is not allowed to run yet. Run `chmod +x ~/Applications/godot`.

- **The setup says `No copy of HOMM1 found`**
  - Check that `external_resources` sits next to `project.godot` and holds `hommdemo-cd.zip` or your `homm1game` folder. See [Section 3](#3-set-up-the-game-assets-required).

- **The main menu says `Game data not built`, or the screen is black on startup**
  - The assets were not built yet. Follow [Section 3](#3-set-up-the-game-assets-required).

- **The build script says `Godot executable not found`**
  - It looks for Godot at `~/Applications/godot`. Move and rename the file as in [Section 1](#1-get-godot-471).
