"""Stream compact visualization frames from the default output monitor."""

import array
import json
import math
import os
import signal
import subprocess
import sys

RATE = 16000
SAMPLES = 640
FREQUENCIES = tuple(80 * (5000 / 80) ** (index / 23) for index in range(24))
COEFFICIENTS = tuple(2 * math.cos(2 * math.pi * hz / RATE) for hz in FREQUENCIES)
WINDOW = tuple(0.5 - 0.5 * math.cos(2 * math.pi * i / (SAMPLES - 1)) for i in range(SAMPLES))


def frames(stream):
    while len(data := stream.read(SAMPLES * 2)) == SAMPLES * 2:
        pcm = array.array("h", data)
        if sys.byteorder != "little":
            pcm.byteswap()
        wave = [max(-1, min(1, pcm[i] / 8192)) for i in range(0, SAMPLES, 32)]
        samples = [value * weight / 32768 for value, weight in zip(pcm, WINDOW)]
        bars = []
        for coefficient in COEFFICIENTS:
            previous = older = 0
            for sample in samples:
                previous, older = sample + coefficient * previous - older, previous
            power = previous ** 2 + older ** 2 - coefficient * previous * older
            amplitude = math.sqrt(max(0, power)) / SAMPLES
            bars.append(min(1, math.sqrt(amplitude * 12)))
        yield [bars, wave]


def stop(_signum, _frame):
    raise SystemExit(0)


def main():
    signal.signal(signal.SIGTERM, stop)
    with subprocess.Popen(
        ["parec", "--device=@DEFAULT_MONITOR@", "--raw", "--format=s16le",
         f"--rate={RATE}", "--channels=1", "--latency-msec=40", "--client-name=OmaPlayer"],
        stdout=subprocess.PIPE,
    ) as recorder:
        try:
            for frame in frames(recorder.stdout):
                print(json.dumps(frame, separators=(",", ":")), flush=True)
        except BrokenPipeError:
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        finally:
            if recorder.poll() is None:
                recorder.terminate()
    return recorder.returncode


if __name__ == "__main__":
    sys.exit(main())
