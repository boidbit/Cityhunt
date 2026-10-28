#!/usr/bin/env bash
# Joins the recorded clips into one vertical 1080x1920 Short with captions, and fades out on the last line.
#   tools/shorts/compose.sh out/freeze.avi out/chase.avi out/short.mp4
# The clips come from godot/tests/short.gd (freeze 14 s, chase 14 s). Timings below are seconds on the joined video.
set -euo pipefail

freeze="$1"
chase="$2"
out="$3"
font="$(dirname "$0")/../../getaway/assets/fonts/BigShouldersDisplay.ttf"

# one caption: text, from second, to second
cap() {
  printf "drawtext=fontfile=%s:text='%s':fontsize=150:fontcolor=white:borderw=8:bordercolor=black:x=(w-text_w)/2:y=h*0.18:enable='between(t,%s,%s)'" "$font" "$1" "$2" "$3"
}

caps="$(cap 'DO NOT MOVE' 0.2 2.0),$(cap 'IT HUNTS BY MOVEMENT' 2.4 5.4),$(cap 'RUN' 7.3 9.5),$(cap 'ONE FLARE' 18.3 20.6),$(cap 'DID HE MAKE IT?' 28.2 29.9)"

has_audio() { ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$1" | grep -q .; }

if has_audio "$freeze" && has_audio "$chase"; then
  filter="[0:v]fps=30,scale=1080:1920,setsar=1[a];[1:v]fps=30,scale=1080:1920,setsar=1[b];[a][b]concat=n=2:v=1:a=0[v0];[0:a][1:a]concat=n=2:v=0:a=1[a0];[v0]tpad=stop_mode=clone:stop_duration=2,${caps},fade=t=out:st=29:d=1[v];[a0]apad=pad_dur=2,afade=t=out:st=28.5:d=1.5[a]"
  maps=(-map "[v]" -map "[a]")
else
  echo "no audio in the clips, making a silent video"
  filter="[0:v]fps=30,scale=1080:1920,setsar=1[a];[1:v]fps=30,scale=1080:1920,setsar=1[b];[a][b]concat=n=2:v=1:a=0[v0];[v0]tpad=stop_mode=clone:stop_duration=2,${caps},fade=t=out:st=29:d=1[v]"
  maps=(-map "[v]")
fi

ffmpeg -y -i "$freeze" -i "$chase" -filter_complex "$filter" "${maps[@]}" \
  -t 30 -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart "$out"
ls -la "$out"
