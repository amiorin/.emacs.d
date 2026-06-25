# neoemacs

A personal terminal Emacs configuration with Vim-style editing, a `SPC`
leader, project/file workflows, and a modern minibuffer completion stack.

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
  evil-collection for Vim emulation across Emacs, plus evil-surround,
  evil-commentary, evil-goggles,
  [expand-region](https://github.com/magnars/expand-region.el), and vundo.
- **Keybindings** — [general](https://github.com/noctuid/general.el) with a
  `SPC` leader and [which-key](https://github.com/justbur/emacs-which-key)
  popups.
- **Completion & actions** — vertico, vertico-directory, orderless,
  marginalia, nerd-icons-completion, consult, embark, embark-consult, and
  wgrep.
- **Project & Git** — projectile, consult-projectile, and
  [magit](https://magit.vc/) (`magit-status` opens in the current window), plus
  diff-hl margin indicators and hunk actions.
- **Environment** — [envrc](https://github.com/purcell/envrc) gives each
  buffer the environment from its directory's `.envrc` (needs the `direnv`
  binary).
- **Files** — [dirvish](https://github.com/alexluigit/dirvish) as a polished
  dired replacement: dotfiles shown but `.`/`..` hidden, long `ls -l` detail
  columns, directory-first sorting when GNU `gls` is available, diredfl
  coloring, omitted generated files, two-pane copy/rename targets, a visible
  block cursor, and `TAB` to expand/collapse subtrees inline.
- **Terminal** — `ghostel`, a libghostty-backed terminal. `s-t` opens a
  vertical split and launches a fresh terminal in it; `evil-ghostel` keeps the
  cursor in sync so normal-state `hjkl` navigation works inside it. In ghostel
  insert state, a single `Esc` is sent to the terminal, while `Esc Esc` returns
  to Evil normal state; `C-c` and `C-x` are forwarded to the running terminal
  program.
- **Help** — in Elisp buffers, `K` (normal state) opens Helpful for the symbol
  under point with no prompt and moves focus into the help window so you can
  scroll it and `q` to dismiss. `SPC h` is the help prefix.
- **External app helpers** — Quick Look previews dired files, Finder opens the
  current directory, and Obsidian opens the current file when it lives inside a
  vault.
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

Leader is `SPC` (normal/visual/motion states); `M-SPC` works as a fallback
elsewhere.

| Key       | Action                          |
|-----------|---------------------------------|
| `SPC SPC` | find file in project            |
| `SPC ,`   | switch buffer                   |
| `SPC f f` | find file                       |
| `SPC f p` | find file in this config        |
| `SPC f r` | recent file                     |
| `SPC f i` | Quick Look dired file at point  |
| `SPC f o` | open current directory in Finder |
| `SPC b b` | switch buffer                   |
| `SPC b d` | kill buffer                     |
| `SPC b i` | ibuffer                         |
| `SPC b n` / `SPC b p` | next / previous buffer |
| `SPC p p` | switch project                  |
| `SPC p f` | find file in project            |
| `SPC p b` | switch to project buffer        |
| `SPC g g` | magit status                    |
| `SPC g b` | magit blame                     |
| `SPC g l` | log for current file            |
| `SPC g j` / `SPC g k` | next / previous hunk   |
| `SPC g s` / `SPC g x` | stage / revert hunk    |
| `SPC o o` | open current file in Obsidian   |
| `SPC u`   | vundo undo tree                 |
| `-`       | jump to dired (current dir)     |
| `s-h/j/k/l` | move between windows          |
| `s-n`     | vertical split + follow focus   |
| `s-w`     | delete current window           |
| `S-s-[`   | rotate windows                  |
| `S-s-]`   | maximize window (delete others) |
| `s-]`     | embark act                      |
| `s-t`     | vsplit + open fresh ghostel terminal in it |
| `v` / `V` | expand / contract region (visual state) |
| `SPC h`   | help prefix                     |
| `SPC h t` | show startup time               |
| `K`       | Helpful for symbol at point (Elisp buffers) |

In dired, `h` goes up a directory, `l` enters the file/directory, and `TAB`
toggles a directory's subtree.

## Files

- `early-init.el` — startup performance tuning and UI chrome removal, loaded
  before packages.
- `init.el` — the main configuration.
- `init-explained.html` — annotated browser walkthrough of `init.el`.

See [CLAUDE.md](CLAUDE.md) for architecture notes and editing conventions, and
[init-explained.html](init-explained.html) for the side-by-side walkthrough.
