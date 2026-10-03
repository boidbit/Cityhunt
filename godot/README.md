# Lost City, Godot version

Lost City rebuilt in Godot 4.6 as a native Android app. It started as a port of the browser version
(`index.html` in the repo root) and has since gone its own way:

- **A T-Rex** hunts the city instead of the old creature. It sees movement: stand still and it only
  notices you close up (or in your torch beam). The ground shakes and puddles ripple under its steps
  well before it is in sight. It is too big for doorways, alleys and the subway.
- **Cars you can drive.** Any parked car that isn't a wreck: USE beside it to get in. The engine and
  headlights draw the T-Rex; it chases cars, shoves the one you are in, then throws it over and you
  crawl out. Charging, it throws parked cars out of its way. The horn calls it to you (useful to lure
  it somewhere). With her in the car, driving to the barricade gets you both out.
- **Finding her:** her phone's last known area is marked on the minimap and shrinks with each clue.
  CALL rings her phone: you hear which way it rings, the area narrows, but the T-Rex may hear it too.
  Her trail (a note, her backpack, her rabbit, her footprints) leads from near where you start to her
  door, and the next thing on it glints from down the street and shows on the minimap.
- **Flares:** you start with one and find more. Thrown, a flare burns for half a minute and draws the
  T-Rex to it, even off a chase if it lands close enough.
- **An evacuated city:** cars on their roofs and sides, some burnt out and smoking, two still burning,
  rubble against the buildings (waist high: crouch behind it), and the T-Rex's tracks in the streets.
- **Day or night:** the NIGHT/DAY button on the start screen, or Settings. By day it sees you from
  further away and you start with the torch off.

## Get the APK

Every push to `main` that changes this folder builds a new APK and publishes it on the
`godot-apk-latest` release. On your Android phone open
https://github.com/talibmohd0099/Cityhunt/releases/tag/godot-apk-latest, tap `LostCity-Godot.apk`
and allow installing from your browser when asked. It installs as "Lost City Godot", next to the
web-version app.

## Open it in Godot

1. Install Godot 4.6.2 (standard version) from https://godotengine.org/download.
2. Open Godot, press Import, pick `godot/project.godot`.
3. Press F5 to play. Mouse drag looks around, WASD walks, Shift runs, Space sprints,
   C crouches, F toggles the light, E interacts (and gets in and out of cars), G throws a flare,
   Q rings her phone. Driving: WASD drives, Space is the handbrake, H (or C) the horn, F the headlights.

Graphics can be set under Settings: Auto picks a level from how fast the phone runs; Low, Medium
and High fix it (render resolution, reflections, glow, flashlight shadow, how far cars are drawn).

## What is where

- `scripts/game.gd`: the game rules, clues, her phone, flares, getting in and out of cars, escape,
  director and end screens
- `scripts/player.gd`, `monster.gd`, `child.gd`: the three characters (`monster.gd` is the T-Rex's mind)
- `scripts/rex.gd`: the T-Rex's body: the model, its clips blended by speed, head turns, sniffing,
  roaring and glowing eyes
- `assets/trex/`: the low-poly animated T-Rex by Quaternius (CC0, see `assets/trex/License.txt`)
- `scripts/vehicles.gd`: the parked cars as things that move: driving, crashes, being thrown and
  flipped, wrecks; each keeps its collision box, glows, shadow and alarm with it
- `scripts/dressing.gd`: the evacuated city: wrecks, fires, rubble and the T-Rex's tracks
- `scripts/man.gd`: the player's body: motion-captured walk, jog, run, sprint, starts, stops, turns
  and crouching, blended by speed, with gradual speed-up and slow-down and feet held on the ground
- `assets/player/`: the player character and his clips (Microsoft Rocketbox, MIT), made by
  `tools/player` (see its README)
- `scripts/hud.gd`: HUD, touch controls, start / pause / end / settings screens
- `scripts/world.gd`, `col.gd`: the city, lights, rain and collision
- `assets/baked/`: city, characters and textures exported from the browser version by `tools/bake`
- `assets/pbr/`: close-up surface detail (asphalt, paving slabs, brick relief, rain drops), made by
  `tools/textures/make_textures.py`
- `assets/vehicles/*_far.glb`: light stand-ins for the car models seen from far away, made by
  `tools/vehicles/make_far_lod.py`
- `shaders/`: wet streets, building walls, car paint, light halos and police light bars
- `tests/autoplay.gd`: plays whole games by itself and checks each step (runs on every build)
- `tests/man_test.gd`: walks, runs, stops, turns and crouches the player and checks the speed builds
  up and dies down over time, turns take a curve and feet on the ground don't slide (runs on every build)
- `tests/drive_test.gd`: drives a car, crashes it into a wall, gets out, has the T-Rex throw it and
  plough through a parked one, escapes with her by car, throws a flare, rings her phone, switches day
  and night, and checks the T-Rex misses someone standing still but not someone moving (runs on every build)

## Run the automatic test

```
godot --headless --path godot --fixed-fps 20 -s res://tests/autoplay.gd -- --mode=win --seed=3
```

`--mode=win` must end in a rescue, `--mode=lose` must end with being caught, `--mode=wild` lets the
creature hunt freely. It prints `ok` or `FAIL` for each check and exits with an error if anything failed.

The player's movement on its own:

```
godot --headless --path godot --fixed-fps 30 -s res://tests/man_test.gd
```

Cars, the T-Rex, flares, her phone and day/night:

```
godot --headless --path godot --fixed-fps 30 -s res://tests/drive_test.gd
```
