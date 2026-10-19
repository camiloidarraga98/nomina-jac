# SyntheticHDR.mp4

Synthetic color bars/motion generated locally, without personal media or external downloads. MP4/hvc1, HEVC Main10, 128×96, 12fps, one second, BT.2020/HLG. Bundled only with the iOS unit tests. The test verifies HDR detection and conversion to SDR/H.264; it no longer needs to encode HEVC on a cold simulator before exercising the app.

Reproduce with FFmpeg and libx265:

```sh
ffmpeg -f lavfi -i 'testsrc2=size=128x96:rate=12:duration=1' \
  -pix_fmt yuv420p10le -c:v libx265 -preset fast \
  -x265-params 'pools=none:frame-threads=1:log-level=error:no-info=1:colorprim=9:transfer=18:colormatrix=9' \
  -color_primaries bt2020 -color_trc arib-std-b67 -colorspace bt2020nc \
  -tag:v hvc1 -movflags +faststart SyntheticHDR.mp4
```

The separate 1600×900/60fps detail fixture explicitly declares Rec.709 on its source, matching its comparison output. Its 34dB detail threshold is unchanged.
