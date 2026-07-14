#!/bin/sh
set -eu

npm run render

render_gif() {
  width="$1"
  height="$2"
  output="$3"

  ffmpeg -y -hide_banner -loglevel error \
    -i out/megaphone-intro.mp4 \
    -filter_complex "fps=18,scale=${width}:${height}:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    -loop 0 "$output"
}

render_gif 1200 750 ../../Resources/demo.gif
render_gif 600 375 ../../website/assets/demo.gif
