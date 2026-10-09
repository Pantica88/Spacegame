Rocket audio supplied by the user as `qs77arhc6stvpeeaqtfffqt4a58fn2cv.wav`.

`titan_engine.wav` contains exactly the first 308,700 samples (0–7 seconds),
copied losslessly from that upload: 44.1 kHz, mono, 16-bit PCM.
`scripts/titan_audio.gd` plays the same 1.0–3.8 s sustained combustion section
at every nonzero thrust level. Throttle changes only volume, with a smooth
180 ms rise / 120 ms fall for a full-scale change. It never seeks to another
section, changes pitch, or restarts the loop when thrust changes.

The first Titan firing of each flight starts at second 0, preserving the
recording's ignition and pump startup without an added fade-in. Later
throttle restarts begin at second 1 and fade in from silence. Rolling out
again restores the initial ignition. The fixed 160 ms seam crossfade gives 2.64 seconds
between repetitions. Zero thrust fades to silence; pause freezes playback.
The shutdown tail after 7 seconds remains excluded.

Sparrow now uses an original sound, replacing the uploaded recording.
`sparrow_sustain.wav` is an eight-second steady rocket-engine loop generated
with Mirelo (job `1443099184ef4b1aac8c42f1307c6f31`), converted to mono 44.1 kHz
16-bit PCM with a 32 Hz high-pass and 6.5 kHz low-pass filter. The generation
prompt specified deep combustion rumble, turbulent exhaust, fine irregular
crackle and faint stable pump hiss, with constant pitch/thrust and no startup,
shutdown, revving, rhythmic pulsing, speech or music.

`tools/build_sparrow_audio.py` sets a single overall sustain gain and authors
a one-second ignition lead-in with a short pressure pulse, ignition snap
and pump spin-up. It produces `sparrow_engine.wav`: 9 seconds total, with
initial ignition at 0 and an eight-second sustain section from 1–9 seconds.
The 160 ms seam crossfade gives 7.84 seconds between repetitions. Throttle
changes volume only; later starts fade in from second 1 and skip ignition.
The previous source recording's 0–2 s restriction applied to that recording,
which is no longer used for Sparrow.

Rebuild the game asset with `python3 tools/build_sparrow_audio.py`.

Only fueled, active, attached engines use their respective recording.
Titan and Sparrow retain separate playback and first-ignition state on mixed
craft. Multiple engines of the same kind share one voice to avoid stacking
identical samples. Kestrel and boosters keep the legacy audio below; boosters
cannot override either recorded engine's volume. WAV import compression
must remain disabled for all PCM playback.

Legacy audio for other engines:
`rocket_engine.wav` is an unchanged copy (44.1 kHz, mono, 16-bit PCM).

The full 100%–0% thrust range maps from the beginning to the end of the
recording's 0–7 second interval. Overlapping half-second loops are prepared
in memory, with matched RMS loudness and equal-power seams. Neighboring
sections blend as throttle changes; holding throttle keeps the sound looping.
There are no separate ignition or shutdown triggers and no 15% cutoff.

Opening throttle ramps up from silence over up to 450 ms rather than playing
a takeoff transient. Zero throttle stops playback; pause holds it. WAV import
compression must remain disabled for the PCM loop preparation.
