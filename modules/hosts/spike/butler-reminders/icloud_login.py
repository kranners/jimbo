import getpass
import os
import pwd
import sys

os.environ.setdefault("PYTHON_KEYRING_BACKEND", "keyring.backends.null.Keyring")

from pyicloud import PyiCloudService
from pyicloud.exceptions import PyiCloudAPIResponseException

COOKIE_DIRECTORY = "/var/lib/butler/.local/share/pyicloud"
APPLE_ID_FILE = os.path.join(COOKIE_DIRECTORY, "apple-id")


def fail(message):
    print(f"butler-icloud-login: {message}", file=sys.stderr)
    sys.exit(1)


def complete_2fa(api):
    try:
        if not api.request_2fa_code():
            fail("this Apple ID asks for a security key, which butler-icloud-login cannot use")
    except PyiCloudAPIResponseException:
        print("Could not send a code; enter the one a trusted device already shows.")
        api.use_existing_trusted_device_code()
    for _ in range(3):
        if api.validate_2fa_code(input("2FA code: ").strip()):
            break
        print("That code was not accepted.")
    else:
        fail("no 2FA code was accepted")
    if not api.is_trusted_session:
        api.trust_session()


def main():
    if len(sys.argv) != 2:
        print("usage: sudo -u butler butler-icloud-login <apple-id>", file=sys.stderr)
        sys.exit(2)
    if pwd.getpwuid(os.geteuid()).pw_name != "butler":
        fail("run it as butler: sudo -u butler butler-icloud-login <apple-id>")
    apple_id = sys.argv[1]

    os.makedirs(COOKIE_DIRECTORY, mode=0o700, exist_ok=True)
    api = PyiCloudService(
        apple_id,
        password=getpass.getpass(f"iCloud password for {apple_id}: "),
        cookie_directory=COOKIE_DIRECTORY,
    )
    if api.requires_2fa:
        complete_2fa(api)
    elif api.requires_2sa:
        fail("this Apple ID uses legacy two-step verification, which butler-icloud-login does not support")

    lists = list(api.reminders.lists())
    descriptor = os.open(APPLE_ID_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as file:
        file.write(apple_id + "\n")
    print(f"Logged in as {apple_id}; butler can read {len(lists)} reminder lists.")


main()
