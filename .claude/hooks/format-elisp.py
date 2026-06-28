#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""PostToolUse hook: reindent an edited Elisp file the way apheleia's
`lisp-indent' formatter does -- `indent-region' over the whole buffer in the
file's major mode.

This routes the reindent through the *running* neoemacs Emacs server
(`emacsclient -s neoemacs-<pid>') rather than a fresh `emacs --batch'. The live
Emacs has the config's packages loaded, so macros with custom indent specs
(`general-create-definer', `neoemacs/leader', ...) indent correctly. A bare
batch Emacs doesn't know those specs and mis-indents such forms.

Reads the hook payload as JSON on stdin and acts only on *.el files. If no
neoemacs server is reachable it skips silently (the edit still stands; it just
isn't reindented).
"""
import glob
import json
import os
import subprocess
import sys

# Reindent FILE inside the live Emacs. If the file is already visited in an
# unmodified buffer, revert it to pick up the on-disk edit, reindent, and save
# (so the user's open buffer updates in place). Otherwise work in a temp buffer
# read straight from disk and write back only when indentation actually changed
# -- this never clobbers a modified live buffer and never touches mtime for a
# no-op. `%s' is replaced with the JSON-quoted (== Elisp-quoted) file path.
ELISP = """(let* ((file %s)
       (buf (get-file-buffer file)))
  (cond
   ((and buf (not (buffer-modified-p buf)))
    (with-current-buffer buf
      (let ((inhibit-message t) (message-log-max nil))
        (revert-buffer t t t)
        (indent-region (point-min) (point-max))
        (when (buffer-modified-p) (save-buffer)))))
   (t
    (with-temp-buffer
      (insert-file-contents file)
      (delay-mode-hooks (emacs-lisp-mode))
      (let ((inhibit-message t) (message-log-max nil)
            (orig (buffer-string)))
        (indent-region (point-min) (point-max))
        (unless (string= orig (buffer-string))
          (write-region (point-min) (point-max) file nil 'silent)))))))"""


def socket_dir() -> str:
    # Mirror Emacs's default `server-socket-dir': $TMPDIR (or /tmp) + emacs<uid>.
    base = os.environ.get("TMPDIR", "/tmp")
    return os.path.join(base, f"emacs{os.getuid()}")


def neoemacs_sockets() -> list[str]:
    # Newest socket first -- most likely the Emacs the user is actively in.
    paths = glob.glob(os.path.join(socket_dir(), "neoemacs-*"))
    return sorted(paths, key=lambda p: os.path.getmtime(p), reverse=True)


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    file = payload.get("tool_input", {}).get("file_path", "")
    if not file.endswith(".el"):
        return 0

    elisp = ELISP % json.dumps(os.path.abspath(file))

    for sock in neoemacs_sockets():
        try:
            proc = subprocess.run(
                ["emacsclient", "-s", sock, "--eval", elisp],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=15,
                check=False,
            )
        except (subprocess.TimeoutExpired, FileNotFoundError):
            continue
        if proc.returncode == 0:
            return 0  # reached a live server and reindented

    # No reachable neoemacs server (none running, or only stale sockets).
    print("format-elisp: no neoemacs server reachable; skipped reindent.",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
