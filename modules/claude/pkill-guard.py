import json
import shlex
import sys

GUARDED = {"pkill", "pgrep"}
OPTIONS_TAKING_VALUE = set("FGgJPstUu")
WRAPPERS = {"sudo", "env", "exec", "command", "nice", "nohup", "time", "xargs"}


def simple_commands(command):
    lexer = shlex.shlex(command.replace("\n", ";"), posix=True, punctuation_chars=";&|()")
    lexer.whitespace_split = True
    current = []
    for token in lexer:
        if set(token) <= set(";&|()"):
            yield current
            current = []
        else:
            current.append(token)
    yield current


def program_and_args(words):
    index = 0
    while index < len(words) and "=" in words[index] and not words[index].startswith("-"):
        index += 1
    while index < len(words) and words[index] in WRAPPERS:
        index += 1
        while index < len(words) and (words[index].startswith("-") or "=" in words[index]):
            index += 1
    return words[index:index + 1], words[index + 1 :]


def option_after_pattern(args):
    pattern_seen = False
    expecting_value = False
    for arg in args:
        if expecting_value:
            expecting_value = False
        elif arg == "--":
            return None
        elif arg.startswith("-") and len(arg) > 1:
            if pattern_seen:
                return arg
            expecting_value = arg[-1] in OPTIONS_TAKING_VALUE and len(arg) == 2
        else:
            pattern_seen = True
    return None


def misplaced_option(command):
    for words in simple_commands(command):
        program, args = program_and_args(words)
        if program and program[0].rsplit("/", 1)[-1] in GUARDED:
            found = option_after_pattern(args)
            if found:
                return program[0], found
    return None


try:
    command = json.load(sys.stdin)["tool_input"]["command"]
    found = misplaced_option(command)
except (ValueError, KeyError, TypeError):
    sys.exit(0)

if found:
    program, option = found
    print(
        f"Blocked: macOS {program} stops reading options at the first pattern, so `{option}` "
        "and everything after it become extra patterns, which can match and signal every "
        f"process you own. Put every option before the pattern, e.g. `{program} -U $(id -u) -f 'pattern'`.",
        file=sys.stderr,
    )
    sys.exit(2)
