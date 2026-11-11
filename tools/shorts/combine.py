#!/usr/bin/env python3
"""Joins finished Shorts (made by compose.py) into one video, one action after another: a quick transition
between them, the sound crossfaded under it, a small "2 / 6" counter in the corner of each part, loudness evened
out again over the whole, a contact sheet and a .txt with a title, a description with chapters and tags.

    python3 tools/shorts/combine.py --out out/combo_seed5.mp4 out/flip_seed5.mp4 out/ram_seed6.mp4 out/gapjump_seed7.mp4

Parts that are missing (a render that failed) are left out with a warning; with fewer than one part left it fails.
The parts keep the order they are given in.
"""
import argparse
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compose import FONT, PARKOUR_TAGS, RECIPE_TAGS, ROOF_RECIPES, TAGS, probe, run  # noqa: E402

XF = 0.45                    # seconds each transition takes
SHORT_MAX = 180.0            # YouTube counts a vertical video up to 3 minutes as a Short
# a different transition each time, picked in turn (all in the ffmpeg 6 that the runner installs)
TRANSITIONS = ["fadewhite", "slideleft", "circleopen", "zoomin", "smoothup", "radial", "slideup", "fadeblack"]
# what each part is called in the chapters of the description
CHAPTER = {"flip": "T-Rex flips the car", "hunter": "Hunting the T-Rex", "ram": "Car vs T-Rex",
           "domino": "Every car in the street", "nearmiss": "Inches from its jaws", "freeze": "Don't move",
           "gapjump": "The gap jump", "roofrun": "Rooftop run", "superrun": "Superhero over the roofs",
           "superchase": "Every car is after him"}
TITLES = ["Every Stunt in One Video 😳", "All the Best Moments in One Go 💥", "Which One Was the Best? 👀",
          "The Whole City, One Run 🏙️", "Watch Till the End 😱"]


def part_info(path):
    """recipe, seed and duration of one finished part (its name is <recipe>_seed<n>.mp4)."""
    m = re.match(r"(.+)_seed(\d+)\.mp4$", os.path.basename(path))
    recipe, seed = (m.group(1), int(m.group(2))) if m else (os.path.basename(path)[:-4], 0)
    v = float(probe(path, "stream=duration", "v").split("\n")[0] or 0)
    a = float(probe(path, "stream=duration", "a").split("\n")[0] or 0)
    d = min(v, a) if v > 0 and a > 0 else float(probe(path, "format=duration") or 0)
    return recipe, seed, d


def stamp(t):
    t = int(t)
    return "%d:%02d" % (t // 60, t % 60)


def metadata(parts, starts, total, seed):
    recipes = [p[0] for p in parts]
    short = total <= SHORT_MAX
    title = TITLES[seed % len(TITLES)] + (" #shorts" if short else "")
    lines = ["%d actions in one video, one after another. Which one was the best? 👇" % len(parts), ""]
    # YouTube shows chapters when the first starts at 0:00, there are three or more and each is 10 s or longer
    for (recipe, _, _, _), t in zip(parts, starts):
        lines.append("%s %s" % (stamp(t), CHAPTER.get(recipe, recipe)))
    lines += ["", "(3D animation made in a game engine: nobody gets hurt.)", ""]
    tags = []
    for r in dict.fromkeys(recipes):
        tags += RECIPE_TAGS.get(r, [])
    roof = any(r in ROOF_RECIPES for r in recipes)
    rex = any(r not in ROOF_RECIPES for r in recipes)
    if roof:
        tags += PARKOUR_TAGS
    if rex:
        tags += TAGS
    tags = list(dict.fromkeys(tags + ["compilation", "best moments"]))
    hashtags = "#shorts " if short else ""
    hashtags += " ".join(h for h, on in (("#trex #dinosaur", rex), ("#parkour #superhero", roof), ("#satisfying", True)) if on)
    lines.append(hashtags)
    return "TITLE\n%s\n\nDESCRIPTION\n%s\n\nTAGS\n%s\n" % (title, "\n".join(lines), ", ".join(tags))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=0, help="picks the title")
    ap.add_argument("parts", nargs="+")
    a = ap.parse_args()

    parts = []
    for p in a.parts:
        if not os.path.isfile(p):
            print("warning: %s is missing (its render failed?), left out" % p)
            continue
        info = part_info(p)
        if info[2] < XF * 3:
            print("warning: %s is only %.2f s long, left out" % (p, info[2]))
            continue
        parts.append(info + (p,))
    if not parts:
        sys.exit("no parts to join")
    n = len(parts)
    # where each part starts in the joined video (each transition overlaps the end of one with the next)
    starts = []
    t = 0.0
    for k, (_, _, d, _) in enumerate(parts):
        starts.append(t)
        t += d - XF
    total = t + XF
    print("joining %d parts, %.1f s: %s" % (n, total, ", ".join("%s %.1fs" % (p[0], p[2]) for p in parts)))

    inputs = []
    filt = []
    for k, (_, _, d, path) in enumerate(parts):
        inputs += ["-i", path]
        # the counter, "2 / 6", over the whole part (not on the only part of a one-part video)
        count = ""
        if n > 1:
            count = (",drawtext=fontfile=%s:text='%d / %d':fontsize=64:fontcolor=white:borderw=6:bordercolor=black:"
                     "x=w-text_w-48:y=h*0.045" % (FONT, k + 1, n))
        filt.append("[%d:v]trim=duration=%.3f,setpts=PTS-STARTPTS,fps=30,scale=1080:1920:flags=lanczos,setsar=1,"
                    "format=yuv420p,settb=AVTB%s[v%d]" % (k, d, count, k))
        filt.append("[%d:a]atrim=duration=%.3f,asetpts=PTS-STARTPTS,aformat=sample_rates=48000:channel_layouts=stereo[a%d]"
                    % (k, d, k))
    vlast, alast = "[v0]", "[a0]"
    for k in range(1, n):
        off = starts[k]
        tr = TRANSITIONS[(k - 1) % len(TRANSITIONS)]
        filt.append("%s[v%d]xfade=transition=%s:duration=%.3f:offset=%.3f[vx%d]" % (vlast, k, tr, XF, off, k))
        filt.append("%s[a%d]acrossfade=d=%.3f:c1=tri:c2=tri[ax%d]" % (alast, k, XF, k))
        vlast, alast = "[vx%d]" % k, "[ax%d]" % k
    filt.append("%sloudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[aout]" % alast)
    run(["ffmpeg", "-y", "-v", "warning"] + inputs + ["-filter_complex", ";".join(filt), "-map", vlast, "-map", "[aout]",
         "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", a.out])
    real = float(probe(a.out, "format=duration") or total)
    meta = a.out[:-4] + ".txt"
    with open(meta, "w", encoding="utf-8") as fh:
        fh.write(metadata(parts, starts, real, a.seed))
    # a contact sheet of 40 frames spread over the whole video
    sheet = a.out[:-4] + "_sheet.png"
    run(["ffmpeg", "-y", "-v", "error", "-i", a.out, "-vf", "fps=%.5f,scale=216:384,tile=10x4" % (40.0 / max(real, 1.0)),
         "-frames:v", "1", "-update", "1", sheet])
    print("made %s (%.1f s, %d parts%s), %s and %s" % (a.out, real, n, "" if real <= SHORT_MAX else
          ", longer than 3 minutes: YouTube shows it as a normal video, not a Short", sheet, meta))


if __name__ == "__main__":
    main()
