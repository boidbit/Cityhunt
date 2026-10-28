#!/usr/bin/env bash
# Turns one recorded clip into a vertical 1080x1920 Short: captions on top, two more seconds held at the end
# and a fade to black over the last one, plus a contact sheet (one frame a second) to check the cuts at a glance.
#   tools/shorts/compose.sh out/short.mp4 out/clip.avi "TEXT|from|to" "TEXT|from|to" ...
# from/to are seconds on the video. The clip comes from godot/tests/short.gd.
set -euo pipefail

out="$1"
clip="$2"
shift 2
font="$(dirname "$0")/../../getaway/assets/fonts/BigShouldersDisplay.ttf"

caps=""
for spec in "$@"; do
  IFS='|' read -r text from to <<< "$spec"
  caps+=",drawtext=fontfile=${font}:text='${text}':fontsize=150:fontcolor=white:borderw=8:bordercolor=black:x=(w-text_w)/2:y=h*0.16:enable='between(t,${from},${to})'"
done

dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$clip")"
fade_at="$(awk -v d="$dur" 'BEGIN { printf "%.2f", d + 1 }')"
total="$(awk -v d="$dur" 'BEGIN { printf "%.2f", d + 2 }')"
echo "clip is ${dur} s, the Short will be ${total} s"

vf="fps=30,scale=1080:1920,setsar=1,tpad=stop_mode=clone:stop_duration=2${caps},fade=t=out:st=${fade_at}:d=1"
if ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$clip" | grep -q .; then
  ffmpeg -y -i "$clip" -vf "$vf" -af "apad=pad_dur=2,afade=t=out:st=${fade_at}:d=1" -t "$total" \
    -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart "$out"
else
  echo "no audio in the clip, making a silent video"
  ffmpeg -y -i "$clip" -vf "$vf" -t "$total" -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -movflags +faststart "$out"
fi
ls -la "$out"

sheet="${out%.mp4}_sheet.png"
ffmpeg -y -i "$out" -vf "fps=1,scale=216:384,tile=10x3" -frames:v 1 "$sheet"
ls -la "$sheet"
