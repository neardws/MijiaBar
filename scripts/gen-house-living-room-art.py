#!/usr/bin/env python3
"""兼容入口 → scripts/gen-house-room-art.py"""
import runpy
from pathlib import Path

runpy.run_path(str(Path(__file__).resolve().parent / "gen-house-room-art.py"), run_name="__main__")
