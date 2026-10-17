# House HD-2D pilot artifacts

Generate on macOS after building:

```bash
swift build -c release
.build/release/MijiaBarApp --house-snapshot artifacts/
```

Outputs:

- `house-hd2d-night.png` — living room with AC, floor lamp, and TV on
- `house-hd2d-off.png` — same scene with devices off
