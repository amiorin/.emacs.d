# neoemacs

A personal Emacs configuration with Vim-style editing, a `SPC` leader, and a
modern minibuffer completion stack.

## Install

This config lives in an XDG-style Emacs directory. Point Emacs at it via a
symlink (or clone directly to `~/.config/neoemacs`):

```sh
git clone <repo-url> ~/.config/neoemacs
emacs --init-directory ~/.config/neoemacs   # Emacs 29+
```

On first launch the package system fetches everything from ELPA/MELPA
automatically. After that, install the icon fonts once:

```
M-x nerd-icons-install-fonts
```

## What's inside

- **Editing** — [evil](https://github.com/emacs-evil/evil) +
  evil-collection for Vim emulation across Emacs, plus
  [expand-region](https://github.com/magnars/expand-region.el) for growing the
  selection by semantic units.
- **Keybindings** — [general](https://github.com/noctuid/general.el) with a
  `SPC` leader and [which-key](https://github.com/justbur/emacs-which-key)
  popups.
- **Completion** — vertico, orderless, marginalia, and consult.
- **Project & Git** — projectile, consult-projectile, and
  [magit](https://magit.vc/) (`magit-status` opens in the current window).
- **Environment** — [envrc](https://github.com/purcell/envrc) gives each
  buffer the environment from its directory's `.envrc` (needs the `direnv`
  binary).
- **Files** — [dirvish](https://github.com/alexluigit/dirvish) as a polished
  dired replacement: dotfiles shown but `.`/`..` hidden, a visible block
  cursor, and `TAB` to expand/collapse subtrees inline.
- **Markdown** — [markdown-mode](https://github.com/jrblevin/markdown-mode);
  `README.md` opens in `gfm-mode` (GitHub-Flavored Markdown).
- **Look** — doom-one theme, doom-modeline, nerd-icons; line numbers in the
  gutter with the cursor's current line highlighted.
- **Scrolling** — the mouse/trackpad wheel scrolls the buffer view, leaving
  the cursor where it is. This needs `xterm-mouse-mode` (enabled here) so the
  terminal sends real mouse events instead of turning the wheel into arrow
  keys.
- Terminal Emacs gets full key support via the Kitty Keyboard Protocol (kkp),
  and copies to the host clipboard over SSH/tmux via OSC 52
  ([clipetty](https://github.com/spudlyo/clipetty)).
- **Cursor** — the terminal cursor shape follows the evil state (block in
  normal, bar in insert, underline in replace), steady/non-blinking, via
  [evil-terminal-cursor-changer](https://github.com/7696122/evil-terminal-cursor-changer).
- **Zellij** — when running inside [zellij](https://zellij.dev/), the focused
  tab is automatically renamed to `<parent>/<dir>` of the current project,
  dired directory, or file.

## Key bindings

Leader is `SPC` (normal/visual/motion states); `C-SPC` works as a fallback
elsewhere.

| Key       | Action                          |
|-----------|---------------------------------|
| `SPC f f` | find file                       |
| `SPC f r` | recent file                     |
| `SPC b b` | switch buffer                   |
| `SPC b d` | kill buffer                     |
| `SPC p p` | switch project                  |
| `SPC p f` | find file in project            |
| `SPC g g` | magit status                    |
| `SPC g b` | magit blame                     |
| `-`       | jump to dired (current dir)     |
| `s-h/j/k/l` | move between windows          |
| `s-w`     | delete current window           |
| `s-t`     | vsplit + open ghostel terminal in it |
| `v` / `V` | expand / contract region (visual state) |

In dired, `h` goes up a directory, `l` enters the file/directory, and `TAB`
toggles a directory's subtree.

## Files

- `early-init.el` — startup performance tuning and UI chrome removal, loaded
  before packages.
- `init.el` — the main configuration.

See [CLAUDE.md](CLAUDE.md) for architecture notes and editing conventions.
