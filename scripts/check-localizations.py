#!/usr/bin/env python3
"""Check that every Resources/<lang>.lproj/Localizable.strings file translates every
user-facing string in Sources/ClaudeUsageBar, and that format specifiers match.

    python3 scripts/check-localizations.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources" / "ClaudeUsageBar"
RESOURCES = ROOT / "Resources"

# Interpolated values that are integers (become %lld); everything else becomes %@.
INT_INTERPOLATIONS = {"minutes", "code"}

# Calls whose first string-literal argument is a localization key.
CALL = re.compile(
    r'(?:\b(?:Text|Label|Toggle|Button|Link|row|LocalizedStringKey)\(|\bString\(localized:)\s*"((?:[^"\\]|\\.)*)"'
)
INTERPOLATION = re.compile(r"\\\(([^()]*(?:\([^()]*\))?[^()]*)\)")
SPECIFIER = re.compile(r"%(?:\d+\$)?(?:@|lld|d)")
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')

# Strings that are not meant to be translated.
IGNORED = {"", "GitHub"}


def to_key(literal: str) -> str:
    def replace(match: re.Match) -> str:
        return "%lld" if match.group(1).strip() in INT_INTERPOLATIONS else "%@"

    return INTERPOLATION.sub(replace, literal)


def keys_in_code() -> set[str]:
    keys = set()
    for path in SOURCES.glob("*.swift"):
        if path.name == "DebugSnapshot.swift":
            continue
        for literal in CALL.findall(path.read_text()):
            key = to_key(literal)
            if key not in IGNORED:
                keys.add(key)
    return keys


def load_strings(path: pathlib.Path) -> dict[str, str]:
    entries = {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("/*") or line.startswith("//"):
            continue
        match = ENTRY.match(line)
        if not match:
            sys.exit(f"{path}:{number}: cannot parse: {line}")
        entries[match.group(1)] = match.group(2)
    return entries


def specifiers(text: str) -> list[str]:
    # Positional (%1$@) and plain (%@) specifiers are equivalent; compare kinds only.
    return sorted(re.sub(r"\d+\$", "", s) for s in SPECIFIER.findall(text))


def main() -> int:
    code_keys = keys_in_code()
    problems = []
    languages = sorted(p.parent.name.removesuffix(".lproj") for p in RESOURCES.glob("*.lproj/Localizable.strings"))

    for language in languages:
        if language == "en":
            continue  # English is the development language: keys are the English text.
        strings = load_strings(RESOURCES / f"{language}.lproj" / "Localizable.strings")
        for key in sorted(code_keys - strings.keys()):
            problems.append(f"[{language}] missing: {key!r}")
        for key in sorted(strings.keys() - code_keys):
            problems.append(f"[{language}] unused: {key!r}")
        for key, value in strings.items():
            if key in code_keys and specifiers(key) != specifiers(value):
                problems.append(f"[{language}] format mismatch: {key!r} -> {value!r}")

    for problem in problems:
        print(problem)
    print(f"{len(code_keys)} keys, {len(languages)} languages: {', '.join(languages)}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
