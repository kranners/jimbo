import base64
import contextlib
import io
import json
import os
import plistlib
import re
import secrets
import sys
import time
from datetime import date, datetime, timedelta, timezone

os.environ.setdefault("PYTHON_KEYRING_BACKEND", "keyring.backends.null.Keyring")

import requests
from PIL import Image, ImageOps
from pillow_heif import register_heif_opener
from pyicloud import PyiCloudService
from pyicloud.common.cloudkit import CKRecord, CKZoneIDReq
from pyicloud.common.cloudkit.client import CloudKitApiError, CloudKitAuthError
from pyicloud.exceptions import (
    PyiCloudAPIResponseException,
    PyiCloud2FARequiredException,
    PyiCloud2SARequiredException,
    PyiCloudAuthRequiredException,
    PyiCloudException,
    PyiCloudFailedLoginException,
    PyiCloudNoStoredPasswordAvailableException,
    PyiCloudServiceUnavailable,
)
from pyicloud.services.photos import PRIMARY_ZONE, DirectionEnum, PhotoAlbumFolder, PhotoAsset
from pyicloud.services.photos_cloudkit.service import PHOTO_DESIRED_KEYS
from tzlocal import get_localzone

COOKIE_DIRECTORY = "/var/lib/butler/.local/share/pyicloud"
APPLE_ID_FILE = os.path.join(COOKIE_DIRECTORY, "apple-id")
OUTBOX = "/var/lib/butler/outbox"
OUTBOX_DAYS = 2
EX_TEMPFAIL = 75
LOCAL = get_localzone()
DEFAULT_COUNT = 20
MAX_COUNT = 50
LONG_EDGE = 2048
PRIVATE_ALBUMS = {"Hidden", "Recently Deleted"}
COUNTING_SECONDS = 30

SIZES = {
    "small": ["resJPEGThumb"],
    "medium": ["resJPEGMed", "resJPEGThumb"],
    "large": ["resJPEGFull", "resJPEGLarge", "resOriginal", "resJPEGMed"],
}
VIDEO_SIZES = {
    "small": ["resJPEGThumb"],
    "medium": ["resJPEGMed", "resJPEGThumb"],
    "large": ["resJPEGFull", "resJPEGLarge", "resJPEGMed", "resJPEGThumb"],
}

USAGE = """usage: photos albums
       photos recent [count]
       photos album <name> [count]
       photos on <YYYY-MM-DD> [YYYY-MM-DD]
       photos get <id> [small|medium|large]"""

EXPIRED = (
    PyiCloud2FARequiredException,
    PyiCloud2SARequiredException,
    PyiCloudAuthRequiredException,
    PyiCloudFailedLoginException,
    PyiCloudNoStoredPasswordAvailableException,
    CloudKitAuthError,
)


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def expired():
    print(
        "iCloud session expired: ask Aaron to run `sudo -u butler butler-icloud-login <apple-id>`",
        file=sys.stderr,
    )
    sys.exit(EX_TEMPFAIL)


def connect():
    try:
        with open(APPLE_ID_FILE) as file:
            apple_id = file.read().strip()
    except FileNotFoundError:
        expired()
    try:
        api = PyiCloudService(apple_id, cookie_directory=COOKIE_DIRECTORY)
        if api.requires_2fa or api.requires_2sa:
            expired()
        return api.photos
    except EXPIRED:
        expired()
    except PyiCloudServiceUnavailable as error:
        print(f"iCloud Photos is unavailable: {error}", file=sys.stderr)
        sys.exit(1)


def print_json(value):
    json.dump(value, sys.stdout, ensure_ascii=False, indent=1)
    print()


def field(record, name):
    value = record.fields.get_value(name)
    if isinstance(value, dict) and "value" in value:
        return value["value"]
    return value


def location_of(photo):
    latitude = field(photo.asset_record, "locationLatitude")
    longitude = field(photo.asset_record, "locationLongitude")
    if latitude is not None and longitude is not None:
        return {"latitude": round(float(latitude), 5), "longitude": round(float(longitude), 5)}
    raw = field(photo.asset_record, "locationEnc")
    if not raw:
        return None
    data = raw.encode() if isinstance(raw, str) else raw
    try:
        place = plistlib.loads(data if data.startswith((b"bplist", b"<?xml")) else base64.b64decode(data))
        return {"latitude": round(float(place["lat"]), 5), "longitude": round(float(place["lon"]), 5)}
    except Exception:
        return None


def kind_of(photo):
    if photo.item_type == "movie":
        return "video"
    if photo.is_live_photo:
        return "live"
    return "photo"


def describe(photo):
    width, height = photo.dimensions
    entry = {
        "id": photo.id,
        "taken": photo.asset_date.astimezone(LOCAL).isoformat(timespec="seconds"),
        "filename": photo.filename,
        "width": width,
        "height": height,
        "kind": kind_of(photo),
    }
    location = location_of(photo)
    if location:
        entry["location"] = location
    return entry


def parse_count(args):
    if len(args) > 1 or (args and not re.fullmatch(r"[1-9]\d?", args[0])):
        usage()
    return min(int(args[0]), MAX_COUNT) if args else DEFAULT_COUNT


def parse_day(text):
    if not re.fullmatch(r"(19|20)\d{2}-\d{2}-\d{2}", text):
        usage()
    try:
        return date.fromisoformat(text)
    except ValueError:
        usage()


def local_midnight(day):
    return datetime(day.year, day.month, day.day, tzinfo=LOCAL)


def visible(photo):
    return not field(photo.asset_record, "isHidden") and not field(photo.asset_record, "isDeleted")


def page(album, rank, direction, count):
    unique = {photo.id: photo for photo in album._get_photos_at(rank, direction, count * 2) if visible(photo)}
    ordered = sorted(unique.values(), key=lambda photo: photo.asset_date, reverse=direction == DirectionEnum.DESCENDING)
    return ordered[:count]


def newest(album, count):
    total = len(album)
    if total == 0:
        return []
    return page(album, total - 1, DirectionEnum.DESCENDING, count)


def first_rank_from(total, taken_at, moment):
    low, high = 0, total
    while low < high:
        middle = (low + high) // 2
        if taken_at(middle) < moment:
            low = middle + 1
        else:
            high = middle
    return low


def taken_at_rank(album):
    def taken_at(rank):
        photos = page(album, rank, DirectionEnum.ASCENDING, 1)
        return photos[0].asset_date if photos else datetime.max.replace(tzinfo=timezone.utc)

    return taken_at


def between(album, start, end, count):
    total = len(album)
    rank = first_rank_from(total, taken_at_rank(album), start)
    if rank >= total:
        return [], False
    candidates = page(album, rank, DirectionEnum.ASCENDING, count + 1)
    inside = [photo for photo in candidates if start <= photo.asset_date < end]
    return inside[:count], len(inside) > count


def visible_albums(service):
    return [album for album in service.albums if album.name not in PRIVATE_ALBUMS and not isinstance(album, PhotoAlbumFolder)]


def find_album(service, name):
    albums = visible_albums(service)
    for album in albums:
        if album.name.casefold() == name.casefold():
            return album
    names = ", ".join(album.name for album in albums)
    print(f"no album called {name!r}; the albums are {names}", file=sys.stderr)
    sys.exit(1)


def lookup(service, names):
    response = service.private_client.lookup(
        record_names=names,
        zone_id=CKZoneIDReq(**PRIMARY_ZONE),
        desired_keys=PHOTO_DESIRED_KEYS,
    )
    return [record for record in response.records if isinstance(record, CKRecord)]


def find_photo(service, photo_id):
    assets = [record for record in lookup(service, [photo_id]) if record.recordType == "CPLAsset"]
    if not assets or field(assets[0], "isDeleted") or field(assets[0], "isHidden"):
        print(f"no photo with id {photo_id!r}", file=sys.stderr)
        sys.exit(1)
    master_name = getattr(assets[0].fields.get_value("masterRef"), "recordName", None)
    masters = [record for record in lookup(service, [master_name]) if record.recordType == "CPLMaster"] if master_name else []
    if not masters:
        print(f"photo {photo_id!r} has no original", file=sys.stderr)
        sys.exit(1)
    return PhotoAsset(service, masters[0], assets[0])


def picture_urls(photo, size):
    prefixes = (VIDEO_SIZES if photo.item_type == "movie" else SIZES)[size]
    tokens = (field(photo.master_record, f"{prefix}Res") for prefix in prefixes)
    return [url for url in (getattr(token, "downloadURL", None) for token in tokens) if url]


def as_jpeg(data):
    register_heif_opener()
    with Image.open(io.BytesIO(data)) as image:
        picture = ImageOps.exif_transpose(image).convert("RGB")
    picture.thumbnail((LONG_EDGE, LONG_EDGE))
    output = io.BytesIO()
    picture.save(output, "JPEG", quality=85, optimize=True)
    return output.getvalue()


def sweep_outbox():
    cutoff = time.time() - OUTBOX_DAYS * 86400
    with os.scandir(OUTBOX) as entries:
        for entry in entries:
            with contextlib.suppress(FileNotFoundError):
                if entry.is_file(follow_symlinks=False) and entry.stat().st_mtime < cutoff:
                    os.unlink(entry.path)


def write_outbox(kind, data, extension):
    os.makedirs(OUTBOX, exist_ok=True)
    sweep_outbox()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = os.path.join(OUTBOX, f"{kind}-{stamp}-{secrets.token_hex(4)}.{extension}")
    with open(path, "wb") as file:
        file.write(data)
    return path


def albums_command(service, args):
    if args:
        usage()
    deadline = time.monotonic() + COUNTING_SECONDS
    print_json([{"name": album.name, "count": len(album) if time.monotonic() < deadline else None} for album in visible_albums(service)])


def recent_command(service, args):
    count = parse_count(args)
    print_json([describe(photo) for photo in newest(service.all, count)])


def album_command(service, args):
    if not args or not args[0].strip():
        usage()
    count = parse_count(args[1:])
    print_json([describe(photo) for photo in newest(find_album(service, args[0]), count)])


def on_command(service, args):
    if len(args) not in (1, 2):
        usage()
    first = parse_day(args[0])
    last = parse_day(args[1]) if len(args) == 2 else first
    if last < first:
        usage()
    start = local_midnight(first)
    end = local_midnight(last + timedelta(days=1))
    photos, more = between(service.all, start, end, DEFAULT_COUNT)
    print_json({"photos": [describe(photo) for photo in photos], "more": more})


def get_command(service, args):
    if len(args) not in (1, 2) or (len(args) == 2 and args[1] not in SIZES):
        usage()
    size = args[1] if len(args) == 2 else "medium"
    photo = find_photo(service, args[0])
    for url in picture_urls(photo, size):
        data = service.private_client.download_asset_bytes(url)
        try:
            jpeg = as_jpeg(data)
        except (OSError, Image.DecompressionBombError):
            continue
        print(write_outbox("photo", jpeg, "jpg"))
        return
    print(f"photo {photo.id!r} has no {size} picture that converts to JPEG", file=sys.stderr)
    sys.exit(1)


COMMANDS = {
    "albums": albums_command,
    "recent": recent_command,
    "album": album_command,
    "on": on_command,
    "get": get_command,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        usage()
    command = COMMANDS[sys.argv[1]]
    try:
        command(connect(), sys.argv[2:])
    except EXPIRED:
        expired()
    except (CloudKitApiError, PyiCloudAPIResponseException, PyiCloudException, requests.RequestException) as error:
        print(f"iCloud Photos failed: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
