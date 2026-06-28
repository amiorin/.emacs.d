#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""PostToolUse hook: reindent an edited Elisp file the way apheleia's
`lisp-indent' formatter does -- `indent-region' over the whole buffer in the
file's major mode. Runs headless so it does not need the live Emacs.

Reads the hook payload as JSON on stdin and acts only on *.el files.
"""
import json
import subprocess
import sys

ELISP = """(progn
  (emacs-lisp-mode)
  (let ((inhibit-message t) (message-log-max nil))
    (indent-region (point-min) (point-max)))
  (when (buffer-modified-p) (save-buffer)))"""


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    file = payload.get("tool_input", {}).get("file_path", "")
    if not file.endswith(".el"):
        return 0

    subprocess.run(
        ["emacs", "--batch", file, "--eval", ELISP],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
