# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal Emacs configuration ("neoemacs") that lives at `~/.config/neoemacs`
(an `XDG`-style Emacs config dir). There is no build or test suite — the
"product" is Emacs itself, configured by these files.

> **IMPORTANT:** `~/.emacs.d` MUST never be read or written. This config lives
> exclusively at `~/.config/neoemacs` — that is the only Emacs configuration
> directory to use. Ignore `~/.emacs.d` entirely.

## Layout

- `early-init.el` — loaded before the package system and UI. Startup
  performance tuning (GC deferral, `file-name-handler-alist` suppression) and
  disabling UI chrome / the built-in package autoloader. It also suppresses
  redisplay/messages until startup finishes so the first visible frame is
  already themed. Both perf hacks and redisplay suppression are *restored* on
  `emacs-startup-hook`; keep that pairing intact when editing.
- `init.el` — the real configuration: package bootstrap followed by one
  `use-package` form per package.
- `README.md` — user-facing overview, install notes, and keybinding table.
- `index.html` — browser-readable annotated walkthrough of `init.el`.
- Everything else in the repo is generated state ignored by git (`elpa/`,
  `eln-cache/`, `transient/`, `recentf`, `projectile-bookmarks.eld`,
  `package-quickstart.el`, `package-quickstart.elc`).

## Package management

- Built-in `package.el` + `use-package`, with archives GNU ELPA and MELPA.
- `package-enable-at-startup` is `nil` (set in `early-init.el`), so `init.el`
  activates packages explicitly. It loads the quickstart bundle by its
  suffix-less name (`(load (locate-user-emacs-file "package-quickstart") 'noerror
  'nomessage)`) for fast startup, falling back to one full `package-initialize` +
  `package-quickstart-refresh` when the bundle is missing. See the load-suffix
  rule under *Notable conventions* for why it isn't loaded as `.elc`.
- `use-package-always-ensure t`: every `use-package` auto-installs from ELPA.
  For packages that ship with Emacs (e.g. `recentf`, `which-key`) add
  `:ensure nil` so it doesn't try to fetch them.

## Keybinding architecture

Three layers, used deliberately:

1. **Leader key** via `general` — `neoemacs/leader` is a definer with prefix
   `SPC` (and `M-SPC` as a global fallback for non-normal states). Mnemonic
   groups: `f` files, `b` buffers, `p` project, `g` git, `o` open/external
   apps, plus top-level shortcuts (`SPC SPC` → `projectile-find-file`,
   `SPC ,` → `consult-buffer`, `SPC u` → `vundo`, `SPC h` → help). Add
   user-facing commands here with a `:which-key` label.
2. **`general-define-key`** for state/keymap-scoped bindings (e.g. `-` →
   `dired-jump` in normal state, `s-hjkl` window movement, `s-n` vsplit +
   follow, `s-w` window delete, `S-s-[` rotate windows, `S-s-]`
   `delete-other-windows`, `v`/`V` expand/contract region in visual state,
   dired `h`/`l` and `TAB` → `dirvish-subtree-toggle`).
3. **`use-package :bind`** for plain global chords tied to a package
   (`C-s` consult-line, `C-x g` magit, `C-x C-b` ibuffer, `C-c f` dirvish,
   `s-]` embark-act, `M-.` embark-dwim, `s-t` →
   `neoemacs/vsplit-ghostel`, etc.).

Evil is the editing model: `evil` + `evil-collection` (with
`evil-want-keybinding nil` set *before* load, as evil-collection requires).
`magit` is removed from `evil-collection-mode-list` before `evil-collection-init`
so its native keymap is preserved (no evil bindings layered on magit buffers).

### Projectile prefix gotcha

`projectile` uses `:bind-keymap ("C-c p" . projectile-command-map)`, which
defers `C-c p` until projectile loads. Do **not** bind a sub-key like
`C-c p SPC` globally via another package's `:bind` — at bind time `C-c p` is
not yet a real prefix and Emacs errors with "starts with non-prefix key".
Bind into `projectile-command-map`, or expose the command through the leader
instead (this is why `consult-projectile` is reached at `SPC p p`).

## Completion stack

`vertico` + `vertico-directory` (UI/path editing) + `orderless` (matching) +
`marginalia` (annotations) + `nerd-icons-completion` (file/buffer icons and
directory-name tinting) + `consult` (commands). These work together — changing
one (e.g. `completion-styles`) affects the others.

`embark` / `embark-consult` provide context actions and exports, and `wgrep`
is installed for editable grep results. `helpful` replaces the main help
commands under `help-map`. `ibuffer` is the bulk buffer-management view,
grouped by project with `ibuffer-projectile`.

## Notable conventions

- **Load files by their suffix-less name, never with an explicit `.elc`.** When
  calling `load` (or `require`), pass the name without a suffix and let Emacs
  append `load-suffixes` (`.elc` then `.el`). An explicit `.elc` suffix sets the
  C loader's `no_native` flag (`lread.c` `Fload`: `bool no_native = suffix_p
  (file, ".elc")`); `maybe_swap_for_eln` then returns before the eln lookup
  *and* records the file in `V_comp_no_native_file_h`, so it loads the slower
  byte-code and opts the file out of native compilation entirely. Suffix-less is
  the native-comp path — the `load-no-native` docvar documents this contract.
  This is why the `package-quickstart` load uses the bare name (see *Package
  management*).
- `custom-set-variables` / `custom-set-faces` blocks at the end of `init.el`
  are written by Emacs's Custom system. Edit configuration by hand above them,
  not inside those blocks.
- Evil extras: `evil-surround`, `evil-commentary`, and `evil-goggles` are
  enabled globally. `vundo` is a visualizer over built-in undo, not a
  replacement undo engine.
- This config is built to run in a terminal (`emacs -nw`) **inside zellij**.
  Several features below send raw terminal escape sequences (cursor shape, tab
  name); zellij forwards them to the host terminal natively and, unlike tmux,
  needs no passthrough wrapping (and sets no `$TMUX`).
- Terminal key support: `kkp` (Kitty Keyboard Protocol) is enabled so chords
  the terminal would otherwise swallow reach Emacs. **Gotcha:** kkp re-encodes
  `C-g` as an escape sequence (`ESC [ 103;5 u`) instead of the raw byte 7, so
  Emacs's low-level quit detection during a blocking `call-process` can't see
  it. `envrc--export` runs direnv synchronously and advertises "C-g to abort",
  so an `:around` advice (`neoemacs--envrc-export-restore-quit`) tears kkp down
  for the duration of the call and re-enables it after — restoring the abort.
  Any other synchronous command that relies on `C-g` would need the same.
- Cursor: `evil-terminal-cursor-changer` reflects the evil state in the host
  terminal's cursor via DECSCUSR sequences (`cursor-type` alone only affects
  GUI Emacs). Shapes: normal/visual/motion = block, insert = bar,
  replace/operator = underline, emacs = hollow. `visible-cursor nil` is a
  Ghostty workaround, and `etcc-use-blink nil` forces the *steady* variants in
  every state (no blinking).
- Zellij tab name: `neoemacs--zellij-update-tab-name` keeps the focused zellij
  tab named `<parent>/<dir>` for the current buffer — projectile root, else a
  dired buffer's listed dir, else the visited file's dir (else unchanged). It's
  gated on `$ZELLIJ`, deduped per-frame (via a frame parameter), and runs on
  `window-selection-change-functions` / `window-buffer-change-functions` /
  `dired-after-readin-hook` / `dirvish-setup-hook` — the dired/dirvish hooks
  are needed because in-place directory navigation doesn't change the selected
  window, so the window hooks alone miss it.
- Clipboard: `clipetty` (`global-clipetty-mode`) sends kills to the host
  system clipboard via the OSC 52 escape sequence, so copying works over SSH
  and through tmux.
- Terminal: `ghostel` is a libghostty-backed terminal (the native module is a
  prebuilt binary that auto-downloads on first use). `s-t` runs
  `neoemacs/vsplit-ghostel`, which vsplits, follows focus into the new window,
  creates a fresh buffer, and calls `(ghostel '(4))` — the non-numeric prefix
  arg forces a *new* terminal rather than reusing an existing one.
  `evil-ghostel` (`evil-ghostel-mode`, hooked on `ghostel-mode`) keeps the
  terminal cursor in sync with point across evil state changes so normal-state
  `hjkl` works in the terminal buffer. **Anchor seam:** each redraw,
  `ghostel--redraw-now` re-anchors any window following the live viewport via
  `ghostel--anchor-window`, whose `set-window-point` snaps point back to the
  terminal cursor. On an *animated* terminal (~30fps) that fights normal-state
  motion — evil-ghostel preserves point in its `ghostel--redraw` advice but not
  the anchor. The `evil-ghostel-roam` advice (in `init.el`) skips the anchor
  while point is parked off the live cursor in a motion-capable evil state
  (`normal`/`visual`/`operator`/`motion`); auto-follow resumes on return to
  insert or to the cursor row, and FORCE anchors (paste/yank) are untouched.
  **Wheel scroll:** in insert state the anchor is still live, so a mouse-wheel
  scroll into scrollback is snapped right back. The `evil-ghostel-wheel-normal`
  advice (in `init.el`) flips the buffer to normal state on any wheel event —
  ghostel redispatches the wheel to `mwheel-scroll` when it scrolls the Emacs
  buffer, so that's the advised function. It only switches *from* `insert`/`emacs`
  (normal/visual already roam, and a visual selection mustn't be dropped); press
  `i`/`a` to return to insert and resume live auto-follow.
  **Escape routing:** `neoemacs/ghostel-escape-dwim` replaces the
  `evil-ghostel` insert-state `<escape>` binding. It waits
  `neoemacs/ghostel-escape-timeout` seconds (0.25s) for a second Escape; a
  single `Esc` is sent to the terminal, while `Esc Esc` is intercepted and runs
  Evil's insert-state Escape binding so the terminal receives no Escape.
  `C-c` and `C-x` in ghostel insert state are forwarded as real terminal
  Ctrl-letter keys instead of being swallowed by Emacs prefix maps.
- Display: `global-display-line-numbers-mode` + `global-hl-line-mode` show
  gutter line numbers and highlight the cursor's line. `display-line-numbers-
  type` is `t` (absolute); switch to `'relative`/`'visual` for Vim-style.
  Dired/dirvish and ghostel buffers turn line numbers off locally.
- `dirvish` overrides `dired` globally (`dirvish-override-dired-mode`).
  `dirvish-hide-cursor nil` keeps a real (block) cursor visible instead of
  hiding it behind the hl-line. `dirvish-hide-details nil` keeps the long
  `ls -l` columns visible. `dired-listing-switches` is `-Al` (`-A` =
  "almost all": shows dotfiles but omits `.`/`..`), with
  `--group-directories-first` added when Homebrew `gls` is available. `TAB`
  toggles subtrees. `diredfl` colorizes long-listing columns, `dired-x`
  `dired-omit-mode` hides uninteresting generated files, and
  `dired-dwim-target` supports two-pane copy/rename targets.
- `magit-display-buffer-function` is
  `magit-display-buffer-same-window-except-diff-v1`, so `magit-status` opens in
  the current window (diffs still pop elsewhere).
- `diff-hl` renders VC hunk indicators in the terminal margin, refreshes around
  Magit operations, and supplies leader hunk actions at `SPC g j/k/s/x`.
- Help: `neoemacs/describe-symbol-at-point` (`K` in normal state in
  `emacs-lisp-mode`/`lisp-interaction-mode`) calls Helpful on the symbol under
  point with no minibuffer prompt, then selects the `helpful-mode` window so
  focus lands there (so you can immediately scroll/navigate it and `q` to
  dismiss). `SPC h` is bound to `help-command` for the rest of the help map,
  and `SPC h t` / `C-h t` show `emacs-init-time`.
- macOS external helpers: `SPC f i` previews the dired file at point with Quick
  Look, `SPC f o` reveals the current directory in Finder, and `SPC o o` opens
  the current file in Obsidian by detecting the nearest `.obsidian` vault root.
- Environment: `envrc` (`envrc-global-mode`) applies each buffer's directory
  `.envrc` via direnv. It's enabled on `after-init` *deliberately* — the
  global mode must layer on top of other global modes, so don't move it
  earlier. Requires the `direnv` executable on PATH.
- Wheel scrolling moves the view, not point. This config runs in a
  **terminal** (`emacs -nw`), so the scrolling setup is terminal-specific (no
  GUI/`pixel-scroll-precision-mode` config):
  - `xterm-mouse-mode` is enabled so Emacs receives real mouse events. Without
    it the terminal's "alternate scroll" sends Up/Down arrow keys for the
    wheel, which move point instead of scrolling (the bug we chased). The
    terminal wheel then arrives as `mouse-4`/`mouse-5` → `mwheel-scroll`.
    Trade-off: with it on, text selection uses Emacs's mouse, not the
    terminal's (hold Shift/Fn for native selection).
  - `scroll-margin 0` lets the cursor reach the window edge before it's
    dragged; `make-cursor-line-fully-visible nil` avoids a post-scroll
    recenter. **Deliberately leave `scroll-preserve-screen-position` nil** —
    setting it pins point to a screen row so the cursor tracks the scroll.
  - Inherent Emacs constraint: point must stay visible, so once you scroll far
    enough the cursor sticks to the window edge and its buffer position moves.

## Verifying changes

There is no test command. To check a change, restart Emacs (or
`M-x eval-buffer` on the edited file) and watch `*Messages*` / startup for
errors. A fast syntax/load sanity check without a full GUI session:

```sh
emacs --batch --init-directory=$HOME/.config/neoemacs \
  -l early-init.el -l init.el 2>&1 | grep -i error
```

(Note this will install any newly-added packages on first run.)

> **IMPORTANT:** The `--init-directory` flag is mandatory. Without it
> `user-emacs-directory` (and therefore `package-user-dir`) defaults to
> `~/.emacs.d` — a *separate, unrelated* Emacs config — and the batch run
> will install this config's packages into `~/.emacs.d/elpa`, polluting it.
> `~/.emacs.d` MUST never be read or written (see the warning at the top).
