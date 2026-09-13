#!/usr/bin/env python3
import re, sys

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <path-to-c-file> <function-name>", file=sys.stderr)
        sys.exit(1)
    path, func = sys.argv[1], sys.argv[2]
    with open(path) as f:
        src = f.read()
    pattern = re.compile(
        r'^[ \t]*(?:static[ \t]+)?(?:inline[ \t]+)?[A-Za-z_][A-Za-z0-9_ \t\*]*\b'
        + re.escape(func) + r'[ \t]*\([^;{]*\)[ \t]*\n?[ \t]*\{',
        re.MULTILINE,
    )
    matches = list(pattern.finditer(src))
    if len(matches) < 2:
        print(f"Found {len(matches)} definition(s) of '{func}' -- nothing to dedupe.")
        sys.exit(0)
    print(f"Found {len(matches)} definitions of '{func}'. Keeping the first, removing the second.")
    second = matches[1]
    start = src.rfind('\n', 0, second.start()) + 1
    brace_open = src.index('{', second.start())
    depth = 0
    i = brace_open
    end = None
    while i < len(src):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                end = i + 1
                break
        i += 1
    if end is None:
        print("ERROR: could not find matching closing brace.", file=sys.stderr)
        sys.exit(1)
    while end < len(src) and src[end] == '\n':
        end += 1
    new_src = src[:start] + src[end:]
    with open(path, 'w') as f:
        f.write(new_src)
    print(f"Removed duplicate definition of '{func}' from {path}.")

if __name__ == "__main__":
    main()
