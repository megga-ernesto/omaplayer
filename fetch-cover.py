"""Fetch a cover from a supported media CDN."""

import base64
import re
import subprocess
import sys
from urllib.parse import urlsplit


def main():
    url = sys.argv[1]
    parsed = urlsplit(url)
    if (
        len(url) > 2048
        or parsed.scheme != "https"
        or parsed.netloc not in {"i.scdn.co", "i.ytimg.com", "img.youtube.com", "lh3.googleusercontent.com"}
        or not re.fullmatch(r"/[A-Za-z0-9_./=+%-]+", parsed.path)
        or parsed.query
        or parsed.fragment
    ):
        return 1

    result = subprocess.run(
        ["curl", "-q", "--fail", "--silent", "--proto", "=https",
         "--max-time", "6", "--max-filesize", "2097152", "--", url],
        stdout=subprocess.PIPE,
        timeout=7,
    )
    data = result.stdout
    if result.returncode or len(data) > 2097152:
        return 1
    if data.startswith(b"\xff\xd8\xff"):
        mime = "jpeg"
    elif data.startswith(b"\x89PNG\r\n\x1a\n"):
        mime = "png"
    elif data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        mime = "webp"
    else:
        return 1
    print(f"data:image/{mime};base64,{base64.b64encode(data).decode('ascii')}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.TimeoutExpired):
        sys.exit(1)
