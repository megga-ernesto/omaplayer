"""Temporarily enable compositor blur while an OmaPlayer glass panel is open."""

import fcntl
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

stopping = False


def stop(_signum, _frame):
    global stopping
    stopping = True


def hyprctl(*arguments):
    result = subprocess.run(
        ["hyprctl", *arguments], capture_output=True, text=True, timeout=3, check=True
    )
    return result.stdout


def set_rule(enabled):
    value = "true" if enabled else "false"
    response = hyprctl("eval", f"assert(omaplayerBlurRule); omaplayerBlurRule:set_enabled({value})")
    if response.strip() != "ok":
        raise RuntimeError("Hyprland rejected the OmaPlayer blur rule")


def set_global(enabled):
    value = "true" if enabled else "false"
    response = hyprctl("eval", f"hl.config({{decoration={{blur={{enabled={value}}}}}}})")
    if response.strip() != "ok":
        raise RuntimeError("Hyprland rejected the temporary blur setting")


def main():
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    lock_path = runtime / "omaplayer-backdrop.lock"
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as lock:
        while not stopping:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                time.sleep(0.075)
        if stopping:
            return

        already_enabled = json.loads(hyprctl("getoption", "decoration:blur:enabled", "-j"))["bool"]
        try:
            set_rule(True)
            if not already_enabled:
                set_global(True)
            while not stopping:
                time.sleep(0.075)
        finally:
            try:
                set_rule(False)
            finally:
                if not already_enabled:
                    set_global(False)


if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"OmaPlayer backdrop blur: {error}", file=sys.stderr)
        sys.exit(1)
