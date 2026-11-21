"""Query LRCLIB and return only bounded, validated timed lines."""

import json
import re
import subprocess
import sys
import time
import unicodedata

STAMP = re.compile(r"\[(\d{1,3}):([0-5]\d)(?:[.:](\d{1,3}))?\]")
OFFSET = re.compile(r"(?im)^\[offset:\s*([+-]?\d{1,6})\s*\]$")
MAX_RESPONSE = 131072


def timed_lines(lrc):
    offset = OFFSET.search(lrc)
    shift = int(offset.group(1)) / 1000 if offset else 0
    lines = []
    for row in lrc.splitlines():
        stamps = []
        while stamp := STAMP.match(row):
            minutes, seconds, fraction = stamp.groups()
            time = int(minutes) * 60 + int(seconds) + float(f"0.{fraction or '0'}")
            stamps.append(max(0, time - shift))
            row = row[stamp.end():]
        verse = row.strip()[:360]
        if verse or stamps:
            lines.extend([round(time, 3), verse] for time in stamps)
        if len(lines) >= 400:
            break
    return sorted(lines[:400], key=lambda line: line[0])


def normalized(text):
    plain = unicodedata.normalize("NFKD", text.casefold())
    return "".join(char for char in plain if char.isalnum())


def track_metadata(title, artist):
    split = re.split(r"\s+[-–—]\s+", title, maxsplit=1)
    if len(split) == 2:
        prefix, song = split
        channel = normalized(artist)
        canonical = normalized(prefix)
        if canonical and (not channel or channel in {canonical, canonical + "vevo", canonical + "official", canonical + "topic"}):
            return song.strip(), prefix.strip()
    artist = re.sub(r"\s+[-–—]\s+topic$", "", artist, flags=re.IGNORECASE)
    return title, artist


def fetch(endpoint, params):
    command = [
        "curl", "-q", "--silent", "--proto", "=https", "--max-time", "7",
        "--max-filesize", str(MAX_RESPONSE), "--get", "--write-out", "\n%{http_code}",
        "--user-agent", "OmaPlayer/1.0 (Omarchy desktop widget)",
    ]
    for key, value in params.items():
        command.extend(["--data-urlencode", f"{key}={value}"])
    command.extend(["--", "https://lrclib.net/api/" + endpoint])
    response = subprocess.run(command, stdout=subprocess.PIPE, timeout=8, check=True).stdout
    body, _, status = response.rpartition(b"\n")
    if status == b"404":
        return None
    if status != b"200" or len(body) > MAX_RESPONSE:
        raise ValueError("Invalid LRCLIB response")
    return json.loads(body)


def select_record(records, title, artist, album, duration):
    if not isinstance(records, list):
        return None

    candidates = []
    for record in records[:20]:
        if not isinstance(record, dict):
            continue
        name = record.get("trackName")
        performer = record.get("artistName")
        album_name = record.get("albumName")
        length = record.get("duration")
        if not isinstance(name, str) or not isinstance(performer, str):
            continue
        if normalized(name) != normalized(title) or normalized(performer) != normalized(artist):
            continue
        distance = abs(length - duration) if duration > 0 and isinstance(length, (float, int)) else 0
        if distance > 12:
            continue
        album_differs = bool(album) and (not isinstance(album_name, str) or normalized(album_name) != normalized(album))
        rank = (distance > 2, not bool(record.get("syncedLyrics")), album_differs, distance)
        candidates.append((rank, record))
    return min(candidates, key=lambda candidate: candidate[0])[1] if candidates else None


def lookup(title, artist, album, duration):
    title, artist = track_metadata(title, artist)
    if not title or not artist:
        return {"state": "metadata"}

    identity = {"track_name": title[:256], "artist_name": artist[:256]}
    params = dict(identity)
    if album:
        params["album_name"] = album[:256]
    if 1 <= duration <= 3600:
        params["duration"] = str(duration)

    record = fetch("get", params)
    if record is None:
        time.sleep(0.3)
        record = select_record(fetch("search", identity), title, artist, album, duration)
    if record is None:
        return {"state": "missing"}
    if not isinstance(record, dict):
        return {"state": "error"}
    if record.get("instrumental") is True:
        return {"state": "instrumental"}
    lrc = record.get("syncedLyrics")
    lines = timed_lines(lrc) if isinstance(lrc, str) else []
    if not any(line[1] for line in lines):
        return {"state": "unsynced" if record.get("plainLyrics") else "missing"}
    return {"state": "ready", "lines": lines}


if __name__ == "__main__":
    try:
        result = lookup(*sys.argv[1:4], int(sys.argv[4]))
    except (OSError, ValueError, subprocess.SubprocessError):
        result = {"state": "error"}
    print(json.dumps(result, ensure_ascii=True, separators=(",", ":")))
