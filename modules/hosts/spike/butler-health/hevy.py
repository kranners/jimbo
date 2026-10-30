import fcntl
import getpass
import hashlib
import json
import math
import os
import pwd
import re
import sys
import time
from contextlib import contextmanager
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import unquote

import requests

API = "https://api.hevyapp.com"
WEB = "https://hevy.com/"
HEADERS = {
    "x-api-key": "shelobs_hevy_web",
    "Hevy-Platform": "web",
    "Accept": "application/json, text/plain, */*",
    "Origin": "https://hevy.com",
    "Referer": "https://hevy.com/",
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64)",
}

HOME = Path(pwd.getpwuid(os.getuid()).pw_dir)
CACHE = HOME / ".cache" / "hevy"
SESSION = CACHE / "session.json"
LOCK = CACHE / "session.lock"
CATALOG = CACHE / "catalog.json"
DRAFTS = CACHE / "drafts"
BACKUPS = CACHE / "backups"

FOLDER = "Butler plan"
SLOTS = {"A": "Butler A", "B": "Butler B"}
SET_TYPES = {"warmup", "normal", "failure", "dropset"}
MAX_LOAD_STEP_KG = 7.0
EX_TEMPFAIL = 75

USAGE = """usage: hevy workouts [since YYYY-MM-DD]
       hevy workout <id>
       hevy history <template id> [since YYYY-MM-DD]
       hevy templates [search words]
       hevy routines
       hevy routine <id>
       hevy folders
       hevy routine draft <A|B>        (draft JSON on stdin)
       hevy routine diff <A|B> <sha256>
       hevy routine apply <A|B> <sha256>
       hevy bootstrap
       hevy login                       (by hand, as butler, on a terminal)"""


def usage():
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def fail(message, code=1):
    print(f"hevy: {message}", file=sys.stderr)
    sys.exit(code)


def expired():
    fail(
        "the Hevy session is missing or was refused: ask Aaron to run `sudo -u butler hevy login` on spike",
        EX_TEMPFAIL,
    )


def emit(value):
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


def write_private(path, text):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as file:
        file.write(text)
    os.replace(temporary, path)


@contextmanager
def locked():
    CACHE.mkdir(mode=0o700, parents=True, exist_ok=True)
    with open(LOCK, "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def load_session():
    try:
        return json.loads(SESSION.read_text(encoding="utf-8"))
    except FileNotFoundError:
        expired()


def expiring(session):
    raw = session.get("expires_at")
    if not raw:
        return False
    try:
        expires = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
    except ValueError:
        return False
    return datetime.now(timezone.utc) >= expires - timedelta(minutes=5)


def authorised(session):
    return {
        **HEADERS,
        "Authorization": f"Bearer {session['access_token']}",
        "x-client-time": str(time.time()),
    }


def refresh(stale_access_token):
    with locked():
        session = load_session()
        if session["access_token"] != stale_access_token and not expiring(session):
            return session
        response = requests.post(
            f"{API}/auth/refresh_token",
            json={"refresh_token": session["refresh_token"]},
            headers=authorised(session),
            timeout=30,
        )
        if response.status_code in (400, 401, 403):
            expired()
        response.raise_for_status()
        tokens = response.json()
        session.update(
            access_token=tokens["access_token"],
            refresh_token=tokens["refresh_token"],
            expires_at=tokens.get("expires_at"),
        )
        write_private(SESSION, json.dumps(session))
        return session


def call(method, path, params=None, body=None):
    session = load_session()
    if expiring(session):
        session = refresh(session["access_token"])
    response = None
    for attempt in range(2):
        response = requests.request(
            method,
            f"{API}{path}",
            params=params,
            json=body,
            headers=authorised(session),
            timeout=30,
        )
        if response.status_code != 401 or attempt:
            break
        session = refresh(session["access_token"])
    if response.status_code == 401:
        expired()
    if not response.ok:
        fail(f"{method} {path} returned HTTP {response.status_code}: {response.text[:300]}")
    return response.json() if response.content else None


def username():
    session = load_session()
    if not session.get("username"):
        account = call("GET", "/user/account")
        with locked():
            session = load_session()
            session["username"] = account["username"]
            write_private(SESSION, json.dumps(session))
    return session["username"]


def first_list(value, *keys):
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        for key in keys:
            if isinstance(value.get(key), list):
                return value[key]
        lists = [item for item in value.values() if isinstance(item, list)]
        if lists:
            return lists[0]
    return []


def instant(value):
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, timezone.utc).astimezone()
    return datetime.fromisoformat(str(value).replace("Z", "+00:00")).astimezone()


def since_argument(arguments, default_days):
    if not arguments:
        return datetime.now().astimezone() - timedelta(days=default_days)
    if len(arguments) != 1 or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", arguments[0]):
        usage()
    return datetime.combine(date.fromisoformat(arguments[0]), datetime.min.time()).astimezone()


def logged_set(entry):
    keys = ("indicator", "weight_kg", "reps", "rpe", "duration_seconds", "distance_meters")
    return {key: entry[key] for key in keys if entry.get(key) is not None}


def logged_workout(workout, with_notes):
    start = instant(workout.get("start_time"))
    end = instant(workout.get("end_time"))
    summary = {
        "id": workout.get("id"),
        "name": workout.get("name") or workout.get("title"),
        "start": start.isoformat(timespec="minutes") if start else None,
        "minutes": round((end - start).total_seconds() / 60) if start and end else None,
        "routine_id": workout.get("routine_id"),
        "exercises": [],
    }
    if with_notes and workout.get("description"):
        summary["description"] = workout["description"]
    for exercise in workout.get("exercises") or []:
        entry = {
            "template_id": exercise.get("exercise_template_id"),
            "title": exercise.get("title"),
            "sets": [logged_set(entry) for entry in exercise.get("sets") or []],
        }
        if with_notes and exercise.get("notes"):
            entry["notes"] = exercise["notes"]
        summary["exercises"].append(entry)
    return summary


def workouts_since(since):
    name = username()
    for page in range(30):
        batch = first_list(
            call("GET", "/user_workouts_paged", params={"username": name, "limit": 10, "offset": page * 10}),
            "workouts",
        )
        for workout in batch:
            start = instant(workout.get("start_time"))
            if start and start < since:
                return
            yield workout
        if len(batch) < 10:
            return


def catalog():
    try:
        cached = json.loads(CATALOG.read_text(encoding="utf-8"))
        if time.time() - CATALOG.stat().st_mtime < 86400:
            return cached
    except FileNotFoundError:
        cached = None
    try:
        home = requests.get(WEB, headers={"User-Agent": HEADERS["User-Agent"]}, timeout=30)
        home.raise_for_status()
        bundle_path = re.search(r"/_next/static/chunks/pages/_app-[a-f0-9]+\.js", home.text)
        if not bundle_path:
            raise ValueError("no _app bundle on hevy.com")
        bundle = requests.get(WEB.rstrip("/") + bundle_path.group(0), timeout=60)
        bundle.raise_for_status()
    except (requests.RequestException, ValueError) as error:
        if cached:
            return cached
        fail(f"could not fetch Hevy's exercise catalogue: {error}")
    templates = {}
    for segment in bundle.text.split('{"id":"')[1:]:
        segment = segment[:2000]
        identifier = re.match(r"([A-F0-9]{8})\"", segment)
        fields = {
            field: re.search(rf'"{field}":"((?:[^"\\]|\\.)*)"', segment)
            for field in ("title", "muscle_group", "equipment_category", "exercise_type")
        }
        if identifier and fields["title"] and fields["muscle_group"]:
            templates[identifier.group(1)] = {
                field: json.loads(f'"{match.group(1)}"') if match else None for field, match in fields.items()
            }
    if not templates:
        if cached:
            return cached
        fail("found no exercises in Hevy's web bundle")
    write_private(CATALOG, json.dumps(templates))
    return templates


def all_templates():
    templates = dict(catalog())
    for custom in first_list(call("GET", "/custom_exercise_templates"), "custom_exercise_templates", "exercises"):
        if custom.get("is_archived"):
            continue
        templates[str(custom["id"])] = {
            "title": custom.get("title"),
            "muscle_group": custom.get("muscle_group"),
            "equipment_category": custom.get("equipment_category"),
            "exercise_type": custom.get("exercise_type"),
            "custom": True,
        }
    return templates


def folders():
    return first_list(call("GET", "/routine_folders"), "routine_folders", "folders")


def routines():
    return first_list(call("POST", "/routines_sync_batch", body={}), "updated", "routines")


def routine(identifier):
    if not re.fullmatch(r"[0-9a-fA-F-]{8,64}", identifier):
        usage()
    found = call("GET", f"/routine/{identifier}")
    return found.get("routine", found) if isinstance(found, dict) else found


def plan_folder():
    matches = [folder for folder in folders() if folder.get("title") == FOLDER]
    if len(matches) > 1:
        fail(f"there are {len(matches)} folders named {FOLDER!r}; Aaron should merge them by hand")
    return matches[0] if matches else None


def slot_routine(slot, folder):
    matches = [
        found
        for found in routines()
        if found.get("title") == SLOTS[slot] and str(found.get("folder_id")) == str(folder["id"])
    ]
    if len(matches) != 1:
        fail(f"found {len(matches)} routines titled {SLOTS[slot]!r} in {FOLDER!r}; run `hevy bootstrap` first")
    return routine(str(matches[0]["id"]))


def kilograms(value):
    value = round(float(value), 2)
    return int(value) if value == int(value) else value


def planned_set(entry):
    planned = {"type": entry.get("indicator") or entry.get("type") or "normal"}
    if entry.get("weight_kg"):
        planned["weight_kg"] = kilograms(entry["weight_kg"])
    for key in ("reps", "duration_seconds"):
        if entry.get(key):
            planned[key] = int(entry[key])
    return planned


def planned(found):
    return {
        "notes": found.get("notes") or "",
        "exercises": [
            {
                "exercise_template_id": exercise.get("exercise_template_id"),
                "rest_seconds": exercise.get("rest_seconds") or 0,
                "notes": exercise.get("notes") or "",
                "sets": [planned_set(entry) for entry in exercise.get("sets") or []],
            }
            for exercise in found.get("exercises") or []
        ],
    }


def number(value, low, high, integer):
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not low <= value <= high:
        raise ValueError(f"{value!r} is not a number from {low} to {high}")
    if integer and value != int(value):
        raise ValueError(f"{value!r} is not a whole number")
    return int(value) if integer else kilograms(value)


def text(value, limit):
    if value is None:
        return ""
    if not isinstance(value, str) or len(value) > limit:
        raise ValueError(f"notes must be text of at most {limit} characters")
    return value


def exact_keys(value, allowed, where):
    if not isinstance(value, dict):
        raise ValueError(f"{where} must be an object")
    unknown = set(value) - allowed
    if unknown:
        raise ValueError(f"{where} has unknown keys {sorted(unknown)}")


def validated(draft, templates):
    exact_keys(draft, {"notes", "exercises"}, "the draft")
    exercises = draft.get("exercises")
    if not isinstance(exercises, list) or not 1 <= len(exercises) <= 12:
        raise ValueError("the draft needs 1 to 12 exercises")
    clean = {"notes": text(draft.get("notes"), 500), "exercises": []}
    for position, exercise in enumerate(exercises, 1):
        where = f"exercise {position}"
        exact_keys(exercise, {"exercise_template_id", "rest_seconds", "notes", "sets"}, where)
        template = exercise.get("exercise_template_id")
        if template not in templates:
            raise ValueError(f"{where} has unknown exercise_template_id {template!r}; look it up with `hevy templates`")
        sets = exercise.get("sets")
        if not isinstance(sets, list) or not 1 <= len(sets) <= 8:
            raise ValueError(f"{where} needs 1 to 8 sets")
        clean_sets = []
        for entry in sets:
            exact_keys(entry, {"type", "weight_kg", "reps", "duration_seconds"}, f"a set of {where}")
            kind = entry.get("type", "normal")
            if kind not in SET_TYPES:
                raise ValueError(f"{where} has set type {kind!r}, not one of {sorted(SET_TYPES)}")
            clean_set = {"type": kind}
            for key, low, high, integer in (
                ("weight_kg", 0, 300, False),
                ("reps", 1, 100, True),
                ("duration_seconds", 1, 3600, True),
            ):
                value = number(entry.get(key), low, high, integer)
                if value:
                    clean_set[key] = value
            if "reps" not in clean_set and "duration_seconds" not in clean_set:
                raise ValueError(f"every set of {where} needs reps or duration_seconds")
            clean_sets.append(clean_set)
        clean["exercises"].append(
            {
                "exercise_template_id": template,
                "rest_seconds": number(exercise.get("rest_seconds"), 0, 900, True) or 0,
                "notes": text(exercise.get("notes"), 300),
                "sets": clean_sets,
            }
        )
    return clean


def describe_sets(sets):
    parts = []
    for entry in sets:
        part = f"{entry.get('weight_kg', 0):g} kg × " if entry.get("weight_kg") else ""
        part += f"{entry['reps']}" if entry.get("reps") is not None else f"{entry.get('duration_seconds')} s"
        if entry.get("type", "normal") != "normal":
            part += f" ({entry['type']})"
        parts.append(part)
    return ", ".join(parts)


def heaviest(exercise):
    return max((entry.get("weight_kg") or 0 for entry in exercise["sets"]), default=0)


def working_sets_by_muscle(plan, templates):
    counts = {}
    for exercise in plan["exercises"]:
        muscle = (templates.get(exercise["exercise_template_id"]) or {}).get("muscle_group") or "other"
        counts[muscle] = counts.get(muscle, 0) + sum(1 for entry in exercise["sets"] if entry["type"] != "warmup")
    return counts


def cap_problems(current, draft, templates):
    if not current["exercises"]:
        return []
    problems = []
    before = {exercise["exercise_template_id"]: heaviest(exercise) for exercise in current["exercises"]}
    for exercise in draft["exercises"]:
        old = before.get(exercise["exercise_template_id"])
        if old and heaviest(exercise) - old > MAX_LOAD_STEP_KG:
            title = templates[exercise["exercise_template_id"]]["title"]
            problems.append(f"{title} rises {heaviest(exercise) - old:g} kg, more than one {MAX_LOAD_STEP_KG:g} kg step")
    old_sets = working_sets_by_muscle(current, templates)
    for muscle, count in working_sets_by_muscle(draft, templates).items():
        allowed = old_sets.get(muscle, 0) + max(1, math.ceil(old_sets.get(muscle, 0) * 0.1))
        if count > allowed:
            problems.append(f"{muscle} goes to {count} working sets, more than {allowed}")
    return problems


def diff_lines(current, draft, templates):
    def title(exercise):
        return (templates.get(exercise["exercise_template_id"]) or {}).get("title") or exercise["exercise_template_id"]

    lines = []
    if current["notes"] != draft["notes"]:
        lines.append(f"notes: {current['notes'] or '(none)'} → {draft['notes'] or '(none)'}")
    old = {exercise["exercise_template_id"]: exercise for exercise in current["exercises"]}
    new_ids = {exercise["exercise_template_id"] for exercise in draft["exercises"]}
    for exercise in draft["exercises"]:
        previous = old.get(exercise["exercise_template_id"])
        now = f"{describe_sets(exercise['sets'])}, rest {exercise['rest_seconds']} s"
        if previous is None:
            lines.append(f"+ {title(exercise)}: {now}")
        else:
            then = f"{describe_sets(previous['sets'])}, rest {previous['rest_seconds']} s"
            lines.append(f"~ {title(exercise)}: {then} → {now}" if then != now else f"= {title(exercise)}: {now}")
        if exercise["notes"] != (previous or {}).get("notes", ""):
            lines.append(f"  notes: {exercise['notes'] or '(none)'}")
    for exercise in current["exercises"]:
        if exercise["exercise_template_id"] not in new_ids:
            lines.append(f"- {title(exercise)}")
    old_order = [e["exercise_template_id"] for e in current["exercises"] if e["exercise_template_id"] in new_ids]
    new_order = [e["exercise_template_id"] for e in draft["exercises"] if e["exercise_template_id"] in old]
    if old_order != new_order:
        lines.append("order changed")
    return lines


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def slot_argument(value):
    if value not in SLOTS:
        usage()
    return value


def stored_draft(slot, digest):
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        usage()
    try:
        raw = (DRAFTS / f"{digest}.json").read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(f"no draft {digest}; make one with `hevy routine draft {slot}`")
    if hashlib.sha256(raw.encode()).hexdigest() != digest:
        fail(f"draft {digest} no longer matches its hash")
    stored = json.loads(raw)
    if stored["slot"] != slot:
        fail(f"draft {digest} is for slot {stored['slot']}, not {slot}")
    return stored["plan"]


def report(slot, current, draft, templates):
    print(f"{SLOTS[slot]} in {FOLDER!r}:")
    for line in diff_lines(current, draft, templates) or ["no change"]:
        print(line)
    problems = cap_problems(current, draft, templates)
    for problem in problems:
        print(f"over a cap: {problem}")
    return problems


def payload(found, folder, draft):
    return {
        "title": found["title"],
        "folder_id": folder["id"],
        "index": found.get("index", 0),
        "program_id": found.get("program_id"),
        "coach_force_rpe_enabled": found.get("coach_force_rpe_enabled", False),
        "notes": draft["notes"],
        "exercises": [
            {
                "exercise_template_id": exercise["exercise_template_id"],
                "superset_id": None,
                "rest_seconds": exercise["rest_seconds"],
                "notes": exercise["notes"],
                "sets": [
                    {
                        "index": index,
                        "indicator": entry["type"],
                        "weight_kg": entry.get("weight_kg"),
                        "reps": entry.get("reps"),
                        "distance_meters": None,
                        "duration_seconds": entry.get("duration_seconds"),
                    }
                    for index, entry in enumerate(exercise["sets"])
                ],
            }
            for exercise in draft["exercises"]
        ],
    }


def draft_command(slot):
    templates = all_templates()
    try:
        draft = validated(json.loads(sys.stdin.read()), templates)
    except (json.JSONDecodeError, ValueError) as error:
        fail(f"the draft is not valid: {error}", 2)
    folder = plan_folder() or fail("there is no plan folder yet; run `hevy bootstrap` first")
    current = planned(slot_routine(slot, folder))
    problems = report(slot, current, draft, templates)
    if problems:
        fail(f"the draft breaks the progression caps, so it was not stored: {'; '.join(problems)}")
    raw = canonical({"slot": slot, "plan": draft})
    digest = hashlib.sha256(raw.encode()).hexdigest()
    write_private(DRAFTS / f"{digest}.json", raw)
    print(f"draft {slot} {digest}")


def diff_command(slot, digest):
    draft = stored_draft(slot, digest)
    templates = all_templates()
    folder = plan_folder() or fail("there is no plan folder yet; run `hevy bootstrap` first")
    report(slot, planned(slot_routine(slot, folder)), draft, templates)


def apply_command(slot, digest):
    draft = stored_draft(slot, digest)
    templates = all_templates()
    folder = plan_folder() or fail("there is no plan folder yet; run `hevy bootstrap` first")
    found = slot_routine(slot, folder)
    if str(found.get("folder_id")) != str(folder["id"]):
        fail(f"{SLOTS[slot]} is not in {FOLDER!r}, so it was not touched")
    problems = cap_problems(planned(found), draft, templates)
    if problems:
        fail(f"the routine changed since the draft, which now breaks the caps: {'; '.join(problems)}")
    stamp = datetime.now().strftime("%Y%m%dT%H%M%S")
    write_private(BACKUPS / f"{slot}-{stamp}.json", canonical(found))
    call(
        "PUT",
        f"/routine/{found['id']}?sendSyncEventToMobileApp=true",
        body={"routine": payload(found, folder, draft)},
    )
    written = planned(routine(str(found["id"])))
    if canonical(written) != canonical(draft):
        fail(
            f"Hevy saved {SLOTS[slot]} differently from the draft; the previous version is in "
            f"backups/{slot}-{stamp}.json. Saved: {canonical(written)[:1500]}"
        )
    print(f"applied {digest} to {SLOTS[slot]} and read it back unchanged")


def bootstrap_command():
    folder = plan_folder()
    if folder is None:
        call("POST", "/routine_folder?sendSyncEventToMobileApp=true", body={"folder": {"title": FOLDER}})
        folder = plan_folder() or fail(f"Hevy did not create {FOLDER!r}")
        print(f"created folder {FOLDER!r} ({folder['id']})")
    else:
        print(f"folder {FOLDER!r} exists ({folder['id']})")
    existing = {
        found.get("title"): found for found in routines() if str(found.get("folder_id")) == str(folder["id"])
    }
    for slot, title in SLOTS.items():
        if title in existing:
            print(f"{title} exists ({existing[title]['id']})")
            continue
        created = call(
            "POST",
            "/routine?sendSyncEventToMobileApp=true",
            body={
                "routine": {
                    "title": title,
                    "folder_id": folder["id"],
                    "index": list(SLOTS).index(slot),
                    "program_id": None,
                    "coach_force_rpe_enabled": False,
                    "notes": "Managed by Butler: each change is a diff Aaron approves.",
                    "exercises": [],
                }
            },
        )
        print(f"created {title} ({(created or {}).get('routineId', 'id unknown')})")


def login_command():
    if pwd.getpwuid(os.getuid()).pw_name != "butler":
        fail("run this as butler: sudo -u butler hevy login", 2)
    if not sys.stdin.isatty():
        fail("hevy login reads the cookie from a terminal", 2)
    print("In a browser logged in to hevy.com, copy the value of its auth2.0-token cookie.")
    raw = unquote(getpass.getpass("auth2.0-token: ").strip())
    try:
        cookie = json.loads(raw)
        session = {
            "access_token": cookie["access_token"],
            "refresh_token": cookie["refresh_token"],
            "expires_at": cookie.get("expires_at"),
        }
    except (json.JSONDecodeError, KeyError, TypeError):
        fail("that is not an auth2.0-token value, which is JSON with access_token and refresh_token", 2)
    with locked():
        write_private(SESSION, json.dumps(session))
    print(f"Logged in to Hevy as {username()}.")


def main(arguments):
    if not arguments or any(argument.startswith("-") for argument in arguments):
        usage()
    verb, rest = arguments[0], arguments[1:]
    if verb == "workouts":
        emit([logged_workout(workout, False) for workout in workouts_since(since_argument(rest, 28))])
    elif verb == "workout" and len(rest) == 1:
        identifier = rest[0]
        if not re.fullmatch(r"[0-9a-fA-F-]{8,64}", identifier):
            usage()
        found = call("GET", f"/workout/{identifier}")
        emit(logged_workout(found.get("workout", found), True))
    elif verb == "history" and 1 <= len(rest) <= 2:
        template = rest[0]
        since = since_argument(rest[1:], 182)
        history = []
        for workout in workouts_since(since):
            start = instant(workout.get("start_time"))
            for exercise in workout.get("exercises") or []:
                if exercise.get("exercise_template_id") == template:
                    history.append(
                        {
                            "date": start.date().isoformat() if start else None,
                            "workout": workout.get("name") or workout.get("title"),
                            "sets": [logged_set(entry) for entry in exercise.get("sets") or []],
                        }
                    )
        emit(history)
    elif verb == "templates":
        words = [word.lower() for word in rest]
        for identifier, template in sorted(all_templates().items(), key=lambda item: item[1]["title"] or ""):
            if all(word in (template["title"] or "").lower() for word in words):
                print(
                    "\t".join(
                        [
                            identifier,
                            template["title"] or "",
                            template.get("muscle_group") or "",
                            template.get("equipment_category") or "",
                            "custom" if template.get("custom") else "",
                        ]
                    ).rstrip()
                )
    elif verb == "routines" and not rest:
        emit(
            [
                {
                    "id": found.get("id"),
                    "title": found.get("title"),
                    "folder_id": found.get("folder_id"),
                    "exercises": [exercise.get("title") for exercise in found.get("exercises") or []],
                }
                for found in routines()
            ]
        )
    elif verb == "folders" and not rest:
        emit([{"id": folder.get("id"), "title": folder.get("title")} for folder in folders()])
    elif verb == "routine" and len(rest) == 1:
        found = routine(rest[0])
        emit({"id": found.get("id"), "title": found.get("title"), "folder_id": found.get("folder_id"), **planned(found)})
    elif verb == "routine" and len(rest) == 2 and rest[0] == "draft":
        draft_command(slot_argument(rest[1]))
    elif verb == "routine" and len(rest) == 3 and rest[0] == "diff":
        diff_command(slot_argument(rest[1]), rest[2])
    elif verb == "routine" and len(rest) == 3 and rest[0] == "apply":
        apply_command(slot_argument(rest[1]), rest[2])
    elif verb == "bootstrap" and not rest:
        bootstrap_command()
    elif verb == "login" and not rest:
        login_command()
    else:
        usage()


try:
    main(sys.argv[1:])
except requests.RequestException as error:
    fail(f"could not reach Hevy: {error}")
