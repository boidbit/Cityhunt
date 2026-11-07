#!/usr/bin/env python3
"""Turns a clip recorded by godot/tests/short.gd into a finished Short: sound design laid on the moments the
director logged (EVENT lines: bites, the flip and the landing, the ram, each car thrown, the jaws snapping, roars,
slow motion, the heartbeat; footsteps, the take-off and the landing of a rooftop leap), a light wind bed under it all, a short hook caption, loudness evened out for YouTube,
a contact sheet (one frame a second) to check the cuts at a glance, and a .txt with a title, description and tags.

    python3 tools/shorts/compose.py --clip out/clip.avi --log godot.log --recipe flip --seed 1 --out out/flip_seed1.mp4

The effects are the game's own sounds (godot/assets/sounds, getaway/assets/sounds) and a synthesised sub-bass hit.
No music: the sound is the point.
"""
import argparse
import os
import re
import subprocess
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SND = os.path.join(ROOT, "godot", "assets", "sounds")
WHOOSH = os.path.join(ROOT, "getaway", "assets", "sounds", "whoosh.wav")
FONT = os.path.join(ROOT, "getaway", "assets", "fonts", "BigShouldersDisplay.ttf")

HOOK = {"flip": "WAIT FOR IT", "ram": "CAR VS T-REX", "nearmiss": "TOO CLOSE", "freeze": "DO NOT MOVE", "domino": "",
        "hunter": "HUNT IT DOWN", "gapjump": "DON'T LOOK DOWN", "roofrun": "HOW FAR CAN HE GO?",
        "superrun": "NOTHING CAN STOP HIM", "superchase": "EVERY CAR IS AFTER HIM"}

# What to paste into YouTube for each Short: a title picked by the seed (so two videos of one recipe differ),
# a description and tags. Titles stay under 100 characters; no film or car brand names.
TITLES = {
    "flip": ["T-Rex Flips the Car in Slow Motion 😳", "Wait for the Flip… 🦖💥", "He Almost Got Away From the T-Rex 🦖",
             "This T-Rex Does Not Let Go 😱", "T-Rex vs Car: The Flip 🦖🚗"],
    "ram": ["Car vs T-Rex: Who Wins? 🦖🚗", "He Rammed a T-Rex at Full Speed 💥", "Head-On With a T-Rex 😳",
            "Never Stand in Front of This Car 🦖", "Full Speed Into a Dinosaur 💥🦖"],
    "domino": ["T-Rex Throws Every Car in the Street 🦖💥", "How Many Cars Can a T-Rex Throw? 🚗🚗🚗",
               "Satisfying T-Rex Car Smash 🦖", "T-Rex Domino Run 💥", "Nothing Stops This T-Rex 🦖🚗"],
    "nearmiss": ["Inches From the T-Rex's Jaws 😱", "Closest T-Rex Escape Ever 🦖", "It Missed by THIS Much 😳",
                 "Don't Look Back… 🦖🚗", "Outrunning a T-Rex 🦖💨"],
    "freeze": ["Don't Move… It Can't See You 🦖", "Hiding From a T-Rex 😰", "The T-Rex Is Right There… 🦖",
               "Hold Your Breath 😶🦖", "It Hunts by Movement… 🦖"],
    "hunter": ["He Hunted Down the T-Rex 🦖💥", "Car vs T-Rex: Round Two 🚗💥", "The Hunter Becomes the Hunted… 🦖",
               "Taking Down a T-Rex With a Car 😳", "Full Speed. Twice. 💥🦖"],
    "gapjump": ["He Jumped the Gap… 😳", "Rooftop Leap in Slow Motion 🏙️", "One Jump, Eight Floors Up 😱",
                "Would You Make This Jump? 🏃💨", "Don't Look Down… 😰"],
    "roofrun": ["Rooftop Run at Full Speed 🏃💨", "Roof to Roof Without Stopping 😳", "How Far Can He Go? 🏙️",
                "Flat Out Over the Rooftops 😱", "One Run, Every Roof 🏃🏙️"],
    "superrun": ["He Jumped 20 Floors Up 😳", "Superhero Run Across the City 🦸", "Nothing Can Stop Him 💥",
                 "The Landing at the End 😱", "Day 1 With Superpowers 🦸💥"],
    "superchase": ["Every Car in the City Is After Him 😳", "He Crushed the Car With One Jump 💥", "Superhero vs Traffic 🦸🚗",
                   "Run. Dodge. Crush. 💥", "The Last Car Never Saw It Coming 😱"],
    # (superchase when it goes wrong: he comes up short of a roof, or a car gets him)
    "superchase_fail": ["He Almost Made It… 😬", "Superpowers Aren't Everything 😳", "Not Every Jump Works Out… 😱",
                        "One Mistake Was Enough 😬", "Day 1 With Superpowers Went Wrong 😳"],
}
STORY = {
    "flip": "A T-Rex chases a car through an empty city, bites it twice and throws it over. Watch it in slow motion.",
    "ram": "Out of road and out of options: he floors it straight at the T-Rex.",
    "domino": "A T-Rex charges down a street full of parked cars and throws every one of them aside.",
    "nearmiss": "Its jaws snap shut again and again, inches from the car. Can he get away?",
    "freeze": "It sees what moves. He hides beside a car and holds still while the T-Rex sniffs around him.",
    "hunter": "This time he goes looking for it. Full speed, head on. Then he backs up and does it again.",
    "gapjump": "A running leap across the alley between two rooftops, high above the street, in slow motion. "
               "(3D animation: motion-captured movement in a game engine city.)",
    "roofrun": "Flat out along the rooftops: down a floor, up a floor, across the alley and back, without "
               "stopping. (3D animation: motion-captured movement in a game engine city.)",
    "superrun": "Across the city over its roofs: up twenty metres in one leap, off the top again, flips, superhero "
                "landings, and a drop all the way to the street. (3D animation made in a game engine.)",
    "superchase": "Over the roofs and down to the street, where every car in the city comes after him. He dodges, "
                  "hides and leaps, makes them crash, kicks one away, and when he has had enough he crushes the last "
                  "one with one jump. (3D animation made in a game engine.)",
    "superchase_fail": "Over the roofs and down to the street with every car after him, but this time it doesn't "
                       "go to plan. (3D animation made in a game engine: nobody gets hurt.)",
}
QUESTION = {
    "flip": "Would you have made it out? 👇", "ram": "Who won this one? 👇", "domino": "How many did you count? 👇",
    "nearmiss": "Closest call you've seen? 👇", "freeze": "Could you stay still? 👇", "hunter": "Round three? 👇",
    "gapjump": "Would you make this jump? 👇",
    "roofrun": "Which leap was the hardest? 👇",
    "superrun": "Which power should he get next? 👇",
    "superchase": "Which dodge was the best? 👇",
    "superchase_fail": "Would you have made it? 👇",
}
# (a rooftop leap has nothing to do with dinosaurs: its own tags)
PARKOUR_TAGS = ["parkour", "rooftop", "rooftop jump", "free running", "stunt", "slow motion", "3d animation", "cgi",
                "motion capture", "game", "gameplay", "shorts", "city", "satisfying"]
TAGS = ["t rex", "trex", "dinosaur", "dinosaur chase", "t rex chase", "t rex vs car", "car chase", "dinosaur attack",
        "satisfying", "slow motion", "3d animation", "game", "gameplay", "shorts", "dino", "city", "survival"]
RECIPE_TAGS = {
    "flip": ["car flip", "car crash", "slow motion crash"], "ram": ["car vs dinosaur", "head on crash", "car crash"],
    "domino": ["car smash", "destruction", "satisfying destruction"], "nearmiss": ["near miss", "close call", "escape"],
    "freeze": ["hiding", "suspense", "asmr", "stealth"], "hunter": ["car vs dinosaur", "t rex knockout", "head on crash"],
    "gapjump": ["gap jump", "roof jump", "high jump"],
    "roofrun": ["rooftop run", "roof run", "sprint", "parkour run"],
    "superrun": ["superhero", "superpowers", "super jump", "superhero landing", "flip"],
    "superchase": ["superhero", "superpowers", "car chase", "dodge", "super jump", "car kick"],
}
HASHTAGS = {"flip": "#trex #dinosaur #slowmotion", "ram": "#trex #dinosaur #carcrash", "domino": "#trex #satisfying #dinosaur",
            "nearmiss": "#trex #dinosaur #closecall", "freeze": "#trex #dinosaur #suspense",
            "hunter": "#trex #dinosaur #carcrash", "gapjump": "#parkour #rooftop #slowmotion",
            "roofrun": "#parkour #rooftop #freerunning", "superrun": "#superhero #superpowers #slowmotion",
            "superchase": "#superhero #carchase #stunt"}


ROOF_RECIPES = ("gapjump", "roofrun", "superrun", "superchase")


def metadata(recipe, seed, fail=False):
    """Title, description and tags for one video, as text ready to copy into YouTube Studio."""
    key = recipe + "_fail" if fail and recipe + "_fail" in TITLES else recipe
    titles = TITLES.get(key, ["T-Rex in the City 🦖"])
    title = titles[seed % len(titles)] + " #shorts"
    desc = "%s\n\n%s\n\n#shorts %s" % (STORY.get(key, ""), QUESTION.get(key, ""), HASHTAGS.get(recipe, "#trex"))
    tags = ", ".join(RECIPE_TAGS.get(recipe, []) + (PARKOUR_TAGS if recipe in ROOF_RECIPES else TAGS))
    return "TITLE\n%s\n\nDESCRIPTION\n%s\n\nTAGS\n%s\n" % (title, desc, tags)


def snd(name):
    return WHOOSH if name == "whoosh" else os.path.join(SND, name + ".wav")


def effects(name, n):
    """The layers for one event: (sound, gain, delay after the event in s, pitch). "SUB" is the sub-bass hit."""
    k = n % 3 + 1
    if name.startswith("bite"):
        return [("clang_2", 1.0, 0, 1), ("growl_1", 0.8, 0.05, 1), ("SUB", 0.8, 0, 1)]
    if name == "lift":
        return [("clang_3", 1.0, 0, 0.9), ("growl_2", 1.0, 0.05, 0.9), ("shatter_2", 0.7, 0.1, 1), ("SUB", 0.7, 0, 1)]
    if name == "fall":
        return [("roar_2", 0.9, 0, 0.75), ("boom_1", 1.0, 0.6, 0.8), ("SUB", 1.0, 0.6, 1), ("thud_1", 1.0, 0.65, 0.7)]
    # superchase: the cars, and what he does about them
    if name == "engines":
        return [("ignite", 0.9, 0, 1), ("ignite", 0.7, 0.25, 0.85)]
    if name.startswith("pass"):
        return [("whoosh", 1.0, -0.15, 0.7)]
    if name.startswith("spin"):
        return [("whoosh", 0.55, 0, 1.5), ("thud_1", 0.5, 0.5, 0.8)]
    if name.startswith("dodge"):
        return [("whoosh", 0.5, 0, 1.2), ("step_dry_2", 0.8, 0.1, 1)]
    if name.startswith("dive"):
        return [("whoosh", 0.7, 0, 1.0), ("thud_2", 0.7, 0.45, 1.0), ("step_dry_4", 0.6, 0.9, 1)]
    if name.startswith("vault"):
        return [("step_dry_2", 1.0, 0, 0.9), ("whoosh", 0.7, 0.05, 0.8)]
    if name == "plant":
        return [("step_dry_3", 1.0, 0, 0.8)]
    if name == "kick":
        return [("boom_2", 1.0, 0, 0.8), ("clang_2", 1.0, 0.01, 1), ("shatter_1", 0.9, 0.03, 1), ("SUB", 1.0, 0, 1),
                ("clang_3", 0.9, 1.0, 0.8), ("thud_3", 1.0, 1.0, 0.7), ("shatter_2", 0.6, 1.05, 0.9)]
    if name == "hit":
        return [("thud_1", 1.0, 0, 1), ("clang_1", 1.0, 0, 0.9), ("shatter_2", 0.8, 0.02, 1), ("SUB", 1.0, 0, 1)]
    if name == "crash2":
        return [("boom_2", 1.0, 0, 0.9), ("clang_1", 1.0, 0.01, 0.9), ("clang_2", 0.9, 0.03, 1), ("shatter_1", 1.0, 0.03, 1),
                ("SUB", 1.0, 0, 1), ("thud_3", 0.9, 0.9, 0.8)]
    if name in ("polehit", "smash"):
        return [("boom_1", 1.0, 0, 0.9), ("clang_3", 1.0, 0.01, 0.8), ("shatter_2", 0.9, 0.03, 1), ("SUB", 0.9, 0, 1),
                ("thud_3", 0.8, 0.8, 0.8)]
    if name == "duck":
        return [("step_dry_4", 0.9, 0, 0.9)]
    if name == "roofstep":
        return [("thud_2", 1.0, 0, 1.0), ("clang_3", 0.5, 0.01, 1.2)]
    if name == "shockwave":
        return [("boom_2", 0.8, 0.05, 0.7), ("clang_1", 0.7, 0.1, 0.8), ("shatter_1", 0.6, 0.12, 0.9), ("thud_1", 0.8, 0.7, 0.8)]
    if name == "anger":
        return [("heart", 1.0, 0, 0.8), ("SUB", 0.7, 0.4, 1)]
    if name == "stomp":
        return [("boom_2", 1.0, 0, 0.75), ("SUB", 1.0, 0, 1), ("clang_2", 1.0, 0.01, 0.7), ("shatter_1", 1.0, 0.02, 1),
                ("shatter_2", 0.9, 0.06, 0.9), ("thud_3", 1.0, 0.01, 0.6)]
    if name == "wallhit":
        return [("thud_2", 1.0, 0, 0.8), ("SUB", 0.8, 0, 1), ("step_dry_1", 0.7, 0.02, 0.7)]
    if name == "caught":
        return [("roar_3", 1.0, 0, 1), ("boom_2", 0.9, 0.25, 0.8), ("SUB", 1.0, 0.25, 1), ("growl_2", 0.8, 0.4, 0.9)]
    if name == "flip":
        return [("whoosh", 1.0, 0, 0.7), ("roar_2", 0.9, 0.1, 1)]
    if name == "land":
        return [("boom_1", 1.0, 0, 1), ("shatter_1", 1.0, 0.02, 1), ("clang_3", 0.9, 0.05, 1), ("SUB", 1.0, 0, 1)]
    if name.startswith("ram"):
        return [("boom_2", 1.0, 0, 1), ("clang_1", 1.0, 0.01, 1), ("shatter_2", 0.9, 0.03, 1), ("SUB", 1.0, 0, 1),
                ("roar_3", 0.9, 0.7, 1)]
    if name.startswith("toss"):
        return [("clang_%d" % k, 0.95, 0, 1), ("shatter_%d" % (n % 2 + 1), 0.8, 0.04, 1), ("SUB", 0.7, 0, 1)]
    if name.startswith("snap"):
        return [("growl_%d" % k, 0.8, 0, 1), ("clicks_%d" % k, 1.0, 0.12, 1)]
    if name in ("roar", "roar_2", "roar_end"):
        return [("roar_1" if name == "roar" else ("roar_2" if name == "roar_2" else "roar_3"), 1.0, 0, 1)]
    if name == "sniff":
        return [("growl_3", 0.45, 0.3, 0.8)]
    if name == "fail":
        return [("stinger", 0.8, 0, 1)]
    if name == "crash":
        return [("thud_3", 1.0, 0, 0.8), ("boom_1", 0.7, 0, 0.9), ("SUB", 0.9, 0, 1), ("step_dry_4", 0.8, 0.3, 0.8)]
    if name.startswith("slow_on"):
        return [("whoosh", 0.7, 0, 0.5)]
    # a superhero: blasting off, turning over in the air, coming down hard enough to crack the roof
    if name.startswith("launch"):
        return [("boom_1", 0.9, 0, 0.75), ("SUB", 1.0, 0, 1), ("whoosh", 0.9, 0.05, 0.6), ("thud_3", 0.8, 0, 0.7)]
    if name.startswith("crouch"):
        return [("step_dry_3", 0.8, 0, 0.8)]
    if name.startswith("flip"):
        return [("whoosh", 0.75, 0, 1.0)]
    if name.startswith("impact"):
        return [("thud_2", 1.0, 0, 0.8), ("boom_1", 0.6, 0, 0.9), ("SUB", 0.8, 0, 1), ("clang_1", 0.35, 0.03, 0.8)]
    if name.startswith("slam"):
        return [("boom_2", 1.0, 0, 0.75), ("SUB", 1.0, 0, 1), ("thud_3", 1.0, 0.01, 0.65), ("shatter_2", 0.6, 0.04, 0.8),
                ("clang_3", 0.5, 0.06, 0.8)]
    # a man on a roof: his footsteps, the push off the edge, and the landing a floor lower
    if name.startswith("step"):
        return [("step_dry_%d" % (n % 4 + 1), 0.55, 0, 1)]
    if name.startswith("takeoff"):
        return [("step_dry_2", 1.0, 0, 0.9), ("whoosh", 0.55, 0.05, 0.8)]
    if name.startswith("touchdown"):
        return [("thud_2", 1.0, 0, 0.9), ("step_dry_3", 1.0, 0, 0.85), ("step_dry_1", 0.9, 0.06, 0.85), ("SUB", 0.6, 0, 1)]
    return []


def run(cmd):
    print("+", " ".join(cmd[:6]), "...")
    subprocess.run(cmd, check=True)


def probe(path, entries, stream=None):
    cmd = ["ffprobe", "-v", "error"]
    if stream:
        cmd += ["-select_streams", stream]
    cmd += ["-show_entries", entries, "-of", "csv=p=0", path]
    return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clip", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--recipe", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=0)
    a = ap.parse_args()

    events = []
    pre = 0.0   # recorded before the shot started (the game's start screen): cut off
    with open(a.log, errors="replace") as fh:
        for line in fh:
            m = re.match(r"^EVENT (\S+) ([0-9.]+)", line)
            if m:
                events.append((m.group(1), float(m.group(2))))
            m = re.match(r"^PREROLL ([0-9.]+)", line)
            if m:
                pre = float(m.group(1))
    ev = dict(events)
    meta = a.out[:-4] + ".txt"
    with open(meta, "w", encoding="utf-8") as fh:
        fh.write(metadata(a.recipe, a.seed, "caught" in ev or "fail" in ev))
    dur = float(probe(a.clip, "format=duration")) - pre
    has_audio = bool(probe(a.clip, "stream=index", "a"))
    # nobody dies on screen: if the creature gets him, cut to black a moment after and hold it under the sound
    vend = min(dur, ev["caught"] + 0.3) if "caught" in ev else dur
    black = 1.4 if "caught" in ev else 0.0
    total = vend + black
    print("clip %.2f s after %.2f s cut, audio %s, events %s" % (dur, pre, has_audio, events))

    # slow-motion windows: impacts inside them are played lower and heavier
    windows = []
    for name, t in events:
        if name.startswith("slow_on_"):
            windows.append((t, ev.get("slow_off_" + name[8:], dur)))

    def slowed(t):
        return any(s - 0.05 <= t <= e for s, e in windows)

    tmp = tempfile.mkdtemp()
    sub = os.path.join(tmp, "sub.wav")
    run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=44:sample_rate=48000:duration=1.5",
         "-af", "volume=3,afade=t=in:d=0.01,afade=t=out:st=0.05:d=1.45,aformat=channel_layouts=stereo", sub])

    inputs = ["-ss", "%.3f" % pre, "-i", a.clip]
    if not has_audio:
        inputs += ["-f", "lavfi", "-t", "%.2f" % dur, "-i", "anullsrc=r=48000:cl=stereo"]
    game_in = 0 if has_audio else 1
    inputs += ["-stream_loop", "-1", "-i", snd("wind_loop")]
    wind_in = game_in + 1 if not has_audio else 1
    filt = []
    mix = ["[ga]", "[amb]"]
    # (atrim by name: its second positional option is another start, not the end)
    filt.append("[%d:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=end=%.2f,apad,volume=1.0[ga]" % (game_in, vend))
    # (up on a roof the wind is the loudest thing there is)
    wind = 0.45 if a.recipe in ROOF_RECIPES else 0.2
    filt.append("[%d:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=end=%.2f,volume=%.2f[amb]" % (wind_in, total, wind))
    idx = wind_in + 1
    count = {}
    for name, t in events:
        kind = re.sub(r"_\d+$", "", name)
        count[kind] = count.get(kind, 0) + 1
        for s, gain, delay, pitch in effects(name, count[kind]):
            start = max(t + delay, 0.0)
            if start >= total:
                continue
            if slowed(t) and s != "whoosh":
                pitch *= 0.72
                gain *= 1.15
            inputs += ["-i", sub if s == "SUB" else snd(s)]
            # asetrate takes a plain number of samples a second, not an expression
            p = "asetrate=%d,aresample=48000," % int(48000 * pitch) if pitch != 1 else ""
            filt.append("[%d:a]aformat=sample_rates=48000:channel_layouts=stereo,%svolume=%.2f,adelay=%d:all=1[s%d]"
                        % (idx, p, gain, int(start * 1000), idx))
            mix.append("[s%d]" % idx)
            idx += 1
    # superrun: the car alarms the last landing sets off in the street
    if a.recipe == "superrun":
        slams = [t for name, t in events if name.startswith("slam")]
        if slams:
            for k, delay in enumerate((0.35, 0.9)):
                start = slams[-1] + delay
                if start < total:
                    inputs += ["-stream_loop", "2", "-i", snd("alarm_loop")]
                    filt.append("[%d:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=end=%.2f,volume=%.2f,adelay=%d:all=1[s%d]"
                                % (idx, max(total - start, 0.1), 0.35 - k * 0.12, int(start * 1000), idx))
                    mix.append("[s%d]" % idx)
                    idx += 1
    # superchase: every engine in the street, from when they start to the end
    if a.recipe == "superchase" and "engines" in ev and ev["engines"] < vend:
        start = ev["engines"]
        inputs += ["-stream_loop", "-1", "-i", snd("engine_loop")]
        filt.append("[%d:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=end=%.2f,asetpts=PTS-STARTPTS,"
                    "volume=0.8,afade=t=in:d=0.6,afade=t=out:st=%.2f:d=0.5,adelay=%d:all=1[s%d]"
                    % (idx, vend - start, max(vend - start - 0.5, 0), int(start * 1000), idx))
        mix.append("[s%d]" % idx)
        idx += 1
    # the heartbeat, from when it comes near to when it has gone
    on = ev.get("heart_on", vend)
    off = ev.get("heart_off", vend)
    if off - on > 1.0:
        inputs += ["-stream_loop", "-1", "-i", snd("heart")]
        filt.append("[%d:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=end=%.2f,asetpts=PTS-STARTPTS,"
                    "volume=0.9,afade=t=out:st=%.2f:d=0.8,adelay=%d:all=1[s%d]"
                    % (idx, off - on, max(off - on - 0.8, 0), int(on * 1000), idx))
        mix.append("[s%d]" % idx)
        idx += 1
    filt.append("%samix=inputs=%d:normalize=0:duration=first,loudnorm=I=-14:TP=-1.5:LRA=11[aout]" % ("".join(mix), len(mix)))

    caps = []

    def cap(text, t0, t1, size=140, y="h*0.14"):
        # (a straight quote would end drawtext's quoted text: the typographic one reads the same)
        text = text.replace("'", "\u2019")
        caps.append("drawtext=fontfile=%s:text='%s':fontsize=%d:fontcolor=white:borderw=8:bordercolor=black:"
                    "x=(w-text_w)/2:y=%s:enable='between(t,%.2f,%.2f)'" % (FONT, text, size, y, t0, t1))

    if HOOK.get(a.recipe):
        cap(HOOK[a.recipe], 0.1, 1.5)
    if "fail" in ev:
        cap("FAIL", ev["fail"], total, 220, "h*0.3")
    if a.recipe == "domino":
        n = 0
        for name, t in events:
            if name.startswith("toss_"):
                n += 1
                cap(str(n), t, min(t + 0.9, total), 260, "h*0.12")
    # motion blur: the clip is recorded faster than 30 fps; each output frame is the average of the frames
    # over three quarters of its time (a 270 degree shutter), the way a film camera smears fast motion
    rate = probe(a.clip, "stream=r_frame_rate", "v").split("\n")[0]
    num, _, den = rate.partition("/")
    in_fps = float(num) / float(den or 1) if num else 30.0
    blend = max(1, int(round(in_fps / 30.0 * 0.75)))
    blur = "tmix=frames=%d," % blend if blend > 1 else ""
    print("clip at %.0f fps, blending %d frames into each" % (in_fps, blend))
    to_black = ("trim=end=%.3f,setpts=PTS-STARTPTS,tpad=stop_mode=add:stop_duration=%.2f:color=black,"
                % (vend, black)) if black > 0 else ""
    vf = blur + "fps=30," + to_black + "scale=1080:1920:flags=lanczos,setsar=1" + "".join("," + c for c in caps)
    filt.append("[0:v]%s[v]" % vf)

    run(["ffmpeg", "-y", "-v", "warning"] + inputs + ["-filter_complex", ";".join(filt), "-map", "[v]", "-map", "[aout]",
         "-t", "%.2f" % total, "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", a.out])
    sheet = a.out[:-4] + "_sheet.png"
    run(["ffmpeg", "-y", "-v", "error", "-i", a.out, "-vf", "fps=1,scale=216:384,tile=10x4", "-frames:v", "1",
         "-update", "1", sheet])
    print("made %s (%s s), %s and %s" % (a.out, probe(a.out, "format=duration"), sheet, meta))


if __name__ == "__main__":
    main()
