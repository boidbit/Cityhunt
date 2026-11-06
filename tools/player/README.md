# Player character bake

Makes the Godot version's player (`godot/assets/player/`) from Microsoft Rocketbox
(https://github.com/microsoft/microsoft-rocketbox, MIT licence, see
`godot/assets/player/LICENSE-rocketbox.txt`): the man `Male_Adult_07` and his motion-captured
walks, runs, starts, stops, turns and crouching, plus a running leap from the CMU motion capture database.

Only needed to change the character or his clips; the baked files are in the repo.

## 1. Get the Rocketbox files

The full repository is several GB, so fetch only what the bake reads:

```
git clone --depth 1 --filter=blob:none --no-checkout https://github.com/microsoft/microsoft-rocketbox
cd microsoft-rocketbox
git checkout HEAD -- Assets/Avatars/Adults/Male_Adult_07 \
  $(git ls-tree -r --name-only HEAD Assets/Animations | grep -E '/(m_idle_neutral_01|m_walk_|m_run_|m_turn_|m_crouch_)')
```

## 2. Get the CMU jumps

Rocketbox has no jumps, so those come from the [CMU Graphics Lab Motion Capture
Database](http://mocap.cs.cmu.edu) ("free for all uses"): subject 127's skeleton and the motions listed
in `CMU_CLIPS` in `bake.gd` (`127_25`, "run jump over", for `gap_jump` and, seen in a mirror, `gap_jump_r`):

```
mkdir cmu && cd cmu
curl -O http://mocap.cs.cmu.edu/subjects/127/127.asf
curl -O http://mocap.cs.cmu.edu/subjects/127/127_25.amc
```

`bake.gd` retargets them onto the man (`read_cmu()`): every bone turns the way the actor's does, from
the actor's rest pose (a T) brought onto the man's (an A), his hips go where the actor's go scaled by
leg length, and the floor is put under his feet. Their metadata also says when he takes off and lands.

## 3. Bake

```
python3 tools/player/make_textures.py <path to microsoft-rocketbox>   # needs numpy and Pillow
godot --headless --path tools/player -s res://bake.gd -- <path to microsoft-rocketbox> <path to cmu>
```

`make_textures.py` writes the colour, normal, roughness and hair textures. `bake.gd` (Godot 4.6)
writes `man.scn`: the skinned body plus every clip, with each gait cycle cut to one step pair that
starts on the left heel strike so any two blend in step, and the travel of starts, stops and turns
kept as root motion. The crouch walk is made from the captured walk (lower hips, bent knees, shorter
steps). `scripts/man.gd` in the game plays it all back.

Then check the movement still holds up:

```
godot --headless --path godot --fixed-fps 30 -s res://tests/man_test.gd
```

## Another man

Rocketbox has over a hundred characters on the same skeleton, so the clips work on any of them. Change `AVATAR`
in `bake.gd` and `AVATAR`/`PREFIX` in `make_textures.py` (the prefix is on the texture file names in
the avatar's `Textures` folder), then bake again.
