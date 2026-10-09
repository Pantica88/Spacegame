#!/usr/bin/env python3
"""Build Sparrow's original ignition + eight-second generated sustain asset.

Uses only the standard library. Run from any directory with Python 3.
The source is a Mirelo-generated loop, not either user-supplied recording.
"""
from array import array
import math
from pathlib import Path
import random
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 44100


def build():
    with wave.open(str(ROOT / "assets/audio/sparrow_sustain.wav"), "rb") as source:
        assert (source.getnchannels(), source.getsampwidth(), source.getframerate()) == (1, 2, RATE)
        samples = array("h", source.readframes(source.getnframes()))
    if sys.byteorder != "little":
        samples.byteswap()
    assert len(samples) == RATE * 8
    sustain = [sample / 32768.0 for sample in samples]
    rms = math.sqrt(sum(sample * sample for sample in sustain) / len(sustain))
    gain = 0.14 / rms
    sustain = [sample * gain for sample in sustain]

    # The final source second runs directly into the loop's first second.
    # Add a brief ignition snap, chamber pressure pulse and pump spin-up only
    # to this lead-in. Every throttle restart skips it.
    rng = random.Random(7701)
    ignition = []
    phase = 0.0
    filtered_noise = 0.0
    for index, sample in enumerate(sustain[-RATE:]):
        t = index / RATE
        burn = max(0.0, min(1.0, (t - 0.04) / 0.20))
        burn = burn * burn * (3.0 - 2.0 * burn)
        phase += math.tau * (180.0 + 720.0 * min(t / 0.5, 1.0)) / RATE
        pump = 0.018 * math.sin(phase) * math.sin(math.pi * min(t / 0.8, 1.0)) ** 2
        filtered_noise += 0.32 * (rng.uniform(-1.0, 1.0) - filtered_noise)
        age = max(0.0, t - 0.065)
        strike = min(1.0, age / 0.003) * math.exp(-age / 0.06)
        snap = 0.28 * filtered_noise * strike
        pressure = 0.15 * math.sin(math.tau * 68.0 * age) * strike
        ignition.append(sample * burn + pump + snap + pressure)

    # The generated loop's raw endpoints need not match sample-for-sample.
    # Bridge only the final 2.9 ms of ignition to prevent a one-time click;
    # the in-game player crossfades the longer repeated sustain seam.
    bridge = 128
    first, last = ignition[-bridge - 1], sustain[0]
    for index in range(bridge):
        weight = (index + 1) / (bridge + 1)
        weight = weight * weight * (3.0 - 2.0 * weight)
        ignition[-bridge + index] = first * (1.0 - weight) + last * weight

    audio = ignition + sustain
    peak = max(abs(sample) for sample in audio)
    headroom = min(1.0, 0.9 / peak)
    pcm = array("h", (round(sample * headroom * 32767) for sample in audio))
    if sys.byteorder != "little":
        pcm.byteswap()
    output = ROOT / "assets/audio/sparrow_engine.wav"
    with wave.open(str(output), "wb") as target:
        target.setnchannels(1)
        target.setsampwidth(2)
        target.setframerate(RATE)
        target.writeframes(pcm.tobytes())
    print(f"Built {output.name}: 1 s ignition + 8 s sustain, peak {peak * headroom:.3f}")


if __name__ == "__main__":
    build()
