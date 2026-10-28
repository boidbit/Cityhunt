#!/usr/bin/env python3
"""Turns a clip recorded by godot/tests/short.gd into a finished Short: sound design laid on the moments the
director logged (EVENT lines: bites, the flip and the landing, the ram, each car thrown, the jaws snapping, roars,
slow motion, the heartbeat), a light wind bed under it all, a short hook caption, loudness evened out for YouTube,
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

HOOK = {"flip": "WAIT FOR IT", "ram": "CAR VS T-REX", "nearmiss": "TOO CLOSE", "freeze": "DO NOT MOVE", "domino": ""}

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
}
STORY = {
    "flip": "A T-Rex chases a car through an empty city, bites it twice and throws it over. Watch it in slow motion.",
    "ram": "Out of road and out of options: he floors it straight at the T-Rex.",
    "domino": "A T-Rex charges down a street full of parked cars and throws every one of them aside.",
    "nearmiss": "Its jaws snap shut again and again, inches from the car. Can he get away?",
    "freeze": "It sees what moves. He hides beside a car and holds still while the T-Rex sniffs around him.",
}
QUESTION = {
    "flip": "Would you have made it out? 👇", "ram": "Who won this one? 👇", "domino": "How many did you count? 👇",
    "nearmiss": "Closest call you've seen? 👇", "freeze": "Could you stay still? 👇",
}
TAGS = ["t rex", "trex", "dinosaur", "dinosaur chase", "t rex chase", "t rex vs car", "car chase", "dinosaur attack",
        "satisfying", "slow motion", "3d animation", "game", "gameplay", "shorts", "dino", "city", "survival"]
RECIPE_TAGS = {
    "flip": ["car flip", "car crash", "slow motion crash"], "ram": ["car vs dinosaur", "head on crash", "car crash"],
    "domino": ["car smash", "destruction", "satisfying destruction"], "nearmiss": ["near miss", "close call", "escape"],
    "freeze": ["hiding", "suspense", "asmr", "stealth"],
}
HASHTAGS = {"flip": "#trex #dinosaur #slowmotion", "ram": "#trex #dinosaur #carcrash", "domino": "#trex #satisfying #dinosaur",
            "nearmiss": "#trex #dinosaur #closecall", "freeze": "#trex #dinosaur #suspense"}


def metadata(recipe, seed):
    """Title, description and tags for one video, as text ready to copy into YouTube Studio."""
    titles = TITLES.get(recipe, ["T-Rex in the City 🦖"])
    title = titles[seed % len(titles)] + " #shorts"
    desc = "%s\n\n%s\n\n#shorts %s" % (STORY.get(recipe, ""), QUESTION.get(recipe, ""), HASHTAGS.get(recipe, "#trex"))
    tags = ", ".join(RECIPE_TAGS.get(recipe, []) + TAGS)
    return "TITLE\n%s\n\nDESCRIPTION\n%s\n\nTAGS\n%s\n" % (title, desc, tags)


def snd(name):
    return WHOOSH if name == "whoosh" else os.path.join(SND, name + ".wav")


def effects(name, n):
    """The layers for one event: (sound, gain, delay after the event in s, pitch). "SUB" is the sub-bass hit."""
    k = n % 3 + 1
    if name.startswith("bite"):
        return [("clang_2", 1.0, 0, 1), ("growl_1", 0.8, 0.05, 1), ("SUB", 0.8, 0, 1)]
    if name == "flip":
        return [("whoosh", 1.0, 0, 0.7), ("roar_2", 0.9, 0.1, 1)]
    if name == "land":
        return [("boom_1", 1.0, 0, 1), ("shatter_1", 1.0, 0.02, 1), ("clang_3", 0.9, 0.05, 1), ("SUB", 1.0, 0, 1)]
    if name == "ram":
        return [("boom_2", 1.0, 0, 1), ("clang_1", 1.0, 0.01, 1), ("shatter_2", 0.9, 0.03, 1), ("SUB", 1.0, 0, 1),
                ("roar_3", 0.9, 0.7, 1)]
    if name.startswith("toss"):
        return [("clang_%d" % k, 0.95, 0, 1), ("shatter_%d" % (n % 2 + 1), 0.8, 0.04, 1), ("SUB", 0.7, 0, 1)]
    if name.startswith("snap"):
        return [("growl_%d" % k, 0.8, 0, 1), ("clicks_%d" % k, 1.0, 0.12, 1)]
    if name in ("roar", "roar_end"):
        return [("roar_1" if name == "roar" else "roar_3", 1.0, 0, 1)]
    if name == "sniff":
        return [("growl_3", 0.45, 0.3, 0.8)]
    if name.startswith("slow_on"):
        return [("whoosh", 0.7, 0, 0.5)]
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

    meta = a.out[:-4] + ".txt"
    with open(meta, "w", encoding="utf-8") as fh:
        fh.write(metadata(a.recipe, a.seed))

    events = []
    with open(a.log, errors="replace") as fh:
        for line in fh:
            m = re.match(r"^EVENT (\S+) ([0-9.]+)", line)
            if m:
                events.append((m.group(1), float(m.group(2))))
    ev = dict(events)
    dur = float(probe(a.clip, "format=duration"))
    has_audio = bool(probe(a.clip, "stream=index", "a"))
    print("clip %.2f s, audio %s, events %s" % (dur, has_audio, events))

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

    inputs = ["-i", a.clip]
    if not has_audio:
        inputs += ["-f", "lavfi", "-t", "%.2f" % dur, "-i", "anullsrc=r=48000:cl=stereo"]
    game_in = 0 if has_audio else 1
    inputs += ["-stream_loop", "-1", "-i", snd("wind_loop")]
    wind_in = game_in + 1 if not has_audio else 1
    filt = []
    mix = ["[ga]", "[amb]"]
    filt.append("[%d:a]aformat=sample_rates=48000:channel_layouts=stereo,volume=1.0[ga]" % game_in)
    # (atrim by name: its second positional option is another start, not the end)
    filt.append("[%d:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=end=%.2f,volume=0.2[amb]" % (wind_in, dur))
    idx = wind_in + 1
    count = {}
    for name, t in events:
        kind = re.sub(r"_\d+$", "", name)
        count[kind] = count.get(kind, 0) + 1
        for s, gain, delay, pitch in effects(name, count[kind]):
            start = t + delay
            if start >= dur:
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
    # the heartbeat, from when it comes near to when it has gone
    on = ev.get("heart_on", dur)
    off = ev.get("heart_off", dur)
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
        caps.append("drawtext=fontfile=%s:text='%s':fontsize=%d:fontcolor=white:borderw=8:bordercolor=black:"
                    "x=(w-text_w)/2:y=%s:enable='between(t,%.2f,%.2f)'" % (FONT, text, size, y, t0, t1))

    if HOOK.get(a.recipe):
        cap(HOOK[a.recipe], 0.1, 1.5)
    if a.recipe == "domino":
        n = 0
        for name, t in events:
            if name.startswith("toss_"):
                n += 1
                cap(str(n), t, min(t + 0.9, dur), 260, "h*0.12")
    # motion blur: the clip is recorded faster than 30 fps; each output frame is the average of the frames
    # over three quarters of its time (a 270 degree shutter), the way a film camera smears fast motion
    rate = probe(a.clip, "stream=r_frame_rate", "v").split("\n")[0]
    num, _, den = rate.partition("/")
    in_fps = float(num) / float(den or 1) if num else 30.0
    blend = max(1, int(round(in_fps / 30.0 * 0.75)))
    blur = "tmix=frames=%d," % blend if blend > 1 else ""
    print("clip at %.0f fps, blending %d frames into each" % (in_fps, blend))
    vf = blur + "fps=30,scale=1080:1920:flags=lanczos,setsar=1" + "".join("," + c for c in caps)
    filt.append("[0:v]%s[v]" % vf)

    run(["ffmpeg", "-y", "-v", "warning"] + inputs + ["-filter_complex", ";".join(filt), "-map", "[v]", "-map", "[aout]",
         "-t", "%.2f" % dur, "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", a.out])
    sheet = a.out[:-4] + "_sheet.png"
    run(["ffmpeg", "-y", "-v", "error", "-i", a.out, "-vf", "fps=1,scale=216:384,tile=10x4", "-frames:v", "1",
         "-update", "1", sheet])
    print("made %s (%s s), %s and %s" % (a.out, probe(a.out, "format=duration"), sheet, meta))


if __name__ == "__main__":
    main()
