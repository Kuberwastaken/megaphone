#!/bin/sh
set -eu

npm run render

render_gif() {
  width="$1"
  height="$2"
  output="$3"

  ffmpeg -y -hide_banner -loglevel error \
    -i out/megaphone-intro.mp4 \
    -filter_complex "fps=12,scale=${width}:${height}:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    -loop 0 "$output"
}

render_gif 1176 764 ../../Resources/demo.gif
render_gif 588 382 ../../website/assets/demo.gif
