# external_resources/

Your own copy of the game goes here. Nothing in this directory is tracked or
committed; you supply all of it. A `.gdignore` here stops Godot scanning the
tree; the game loads art from `res://assets/`, which is built from these files.

To play, either leave the 1995 demo's `hommdemo-cd.zip` in this directory or
unpack a copy of the original game (your GOG or CD copy, or any other source)
under `homm1game/`, then run `tools/setup.gd`. The guide for your platform
under [`docs/`](../docs/) has the exact steps (section 3).

Expected structure:

```
external_resources/
├── hommdemo-cd.zip   the 1995 CD demo, left zipped, or
├── homm1game/        a full HOMM1 DOS install: heroes.agg and heroes.exe under game/Resources/hmm/
└── assets_flat/      flat browse copy of every PNG, only if you ask for it:
                        godot --headless --path . --script tools/extract.gd -- --flat-mirror
```
