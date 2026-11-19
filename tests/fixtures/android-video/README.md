# Android video parser fixtures

Synthetic black frames generated locally with the already installed ffmpeg/libx264; no device captures, personal data or downloaded media. Tests read these files and do not require ffmpeg.

```sh
ffmpeg -v error -f lavfi -i color=black:size=320x240 -frames:v 1 -c:v libx264 -profile:v baseline -pix_fmt yuv420p -f h264 baseline-320x240.h264
ffmpeg -v error -f lavfi -i color=black:size=640x360 -frames:v 1 -c:v libx264 -profile:v high -pix_fmt yuv420p -f h264 high-640x360.h264
```

These verify Annex-B, SPS/PPS/IDR extraction and crop/dimension parsing, not Harmony hardware decoding.
