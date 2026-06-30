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

On first launch the package system fetches everything from GNU ELPA, NonGNU
ELPA, and MELPA automatically. After that, install the icon fonts once:

```
M-x nerd-icons-install-fonts
```

## What's inside

- **Editing** — [evil](https://github.com/emacs-evil/evil) +
  evil-collection for Vim emulation across Emacs, plus evil-surround,
  evil-commentary, evil-goggles,
  [expand-region](https://github.com/magnars/expand-region.el), and vundo.
  `/` and `?` use Vim-style incremental search (evil-ex-search) with full-symbol
  matching, an `n`/`N`-aware match count in the mode line (evil-anzu), and
  `<escape>` to clear the search highlight. The current-line highlight is
  suspended while a selection is active so it doesn't obscure the selected
  region.
- **Keybindings** — [general](https://github.com/noctuid/general.el) with a
  `SPC` leader and [which-key](https://github.com/justbur/emacs-which-key)
  popups.
- **Completion & actions** — vertico, vertico-directory, orderless,
  marginalia, nerd-icons-completion, consult, consult-dir (jump/re-root by
  directory from the minibuffer), embark, embark-consult, and wgrep. In-buffer
  completion is [corfu](https://github.com/minad/corfu) (with corfu-terminal for
  `-nw`) plus cape for file/dabbrev fallbacks.
- **Languages** — tree-sitter major modes for TypeScript/TSX,
  [Astro](https://github.com/Sorixelle/astro-ts-mode), and Clojure, with LSP via
  the built-in [eglot](https://github.com/joaotavora/eglot) (astro-ls,
  typescript-language-server, clojure-lsp), on-save formatting via
  [apheleia](https://github.com/radian-software/apheleia), and Clojure REPL
  tooling via [cider](https://github.com/clojure-emacs/cider). The Lisp-family
  modes (Clojure and Emacs Lisp) get structural editing — smartparens strict
  mode, evil-cleverparens paredit motions, and rainbow-delimiters.
- **Project & Git** — projectile, consult-ripgrep project
  search, and [magit](https://magit.vc/) (`magit-status` opens in the current
  window; `e` on a file opens a two-buffer ediff of its working-tree version
  against HEAD), plus diff-hl margin indicators and hunk actions.
- **Environment** — [envrc](https://github.com/purcell/envrc) gives each
  buffer the environment from its directory's `.envrc` (needs the `direnv`
  binary).
- **Files** — [dirvish](https://github.com/alexluigit/dirvish) as a polished
  dired replacement: dotfiles shown but `.`/`..` hidden, long `ls -l` detail
  columns, directory-first sorting when GNU `gls` is available, diredfl
  coloring, omitted generated files, two-pane copy/rename targets, a visible
  block cursor, and `TAB` to expand/collapse subtrees inline.
- **Terminal** — `ghostel`, a libghostty-backed terminal. `s-t` (or `SPC t`)
  opens a vertical split and launches a fresh terminal in it, rooted at the
  current buffer's project root (`SPC u t` starts it in the current directory
  instead); `evil-ghostel` keeps the
  cursor in sync so normal-state `hjkl` navigation works inside it. In ghostel
  insert state, a single `Esc` is sent to the terminal, while `Esc Esc` returns
  to Evil normal state; `C-c` and `C-x` are forwarded to the running terminal
  program.
- **Claude Code sessions** — when Claude Code runs inside a ghostel terminal,
  `consult-claude` tracks each session's live status; `SPC c c` opens a switcher
  to jump between them. Active Claude buffers are switched to ghostel char mode
  so Evil cursor-sync keys are never injected into the TUI.
- **Help** — in Elisp buffers, `K` (normal state) opens Helpful for the symbol
  under point with no prompt and moves focus into the help window so you can
  scroll it and `q` to dismiss. `SPC h` is the help prefix.
- **External app helpers** — open the current file in its default macOS app
  (as if double-clicked), reveal the current directory in Finder, and open the
  current file in Obsidian when it lives inside a vault. All run via macOS
  `open` and work under zellij.
- **Markdown** — [markdown-mode](https://github.com/jrblevin/markdown-mode);
  `README.md` opens in `gfm-mode` (GitHub-Flavored Markdown). Obsidian-style
  `[[wiki links]]` are enabled and resolve names across subdirectories.
- **Editor server** — an Emacs server starts with a per-PID socket, and
  `$EDITOR` points `emacsclient` at it, so git commit messages and other
  `$EDITOR` shell-outs from the embedded terminal open in the running Emacs
  (`C-c C-c`/`ZZ` to finish, `C-c C-k`/`ZQ` to abort).
- **Auto-revert** — buffers (and dired listings) reload automatically and
  silently when their backing files change on disk.
- **Look** — doom-one theme, doom-modeline, nerd-icons; line numbers in the
  gutter with the cursor's current line highlighted.
- **Scrolling** — the mouse/trackpad wheel scrolls the buffer view, leaving
  the cursor where it is. This needs `xterm-mouse-mode` (enabled here) so the
  terminal sends real mouse events instead of turning the wheel into arrow
  keys.
- Terminal Emacs gets full key support via the Kitty Keyboard Protocol (kkp),
  with `key-translation-map` entries restoring shifted Meta chords (`M-S-]` →
  `M-}`, etc.), and copies to the host clipboard over SSH/tmux via OSC 52
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
| `SPC :`   | eval expression                 |
| `SPC /`   | search in project (ripgrep)     |
| `SPC f f` | find file                       |
| `SPC f p` | find file in this config        |
| `SPC f r` | recent file                     |
| `SPC f d` | switch directory (consult-dir)  |
| `SPC b b` | switch buffer                   |
| `SPC b d` | kill buffer                     |
| `SPC b i` | ibuffer                         |
| `SPC b n` / `SPC b p` | next / previous buffer |
| `SPC b u` | vundo undo tree                 |
| `SPC p p` | switch project                  |
| `SPC p f` | find file in project            |
| `SPC p b` | switch to project buffer        |
| `SPC p s` | search in project (ripgrep)     |
| `SPC g g` | magit status                    |
| `SPC g b` | magit blame                     |
| `SPC g l` | log for current file            |
| `SPC g j` / `SPC g k` | next / previous hunk   |
| `SPC g s` / `SPC g x` | stage / revert hunk    |
| `SPC c a` | code actions (eglot)            |
| `SPC c r` | rename symbol (eglot)           |
| `SPC c f` | format buffer (eglot)           |
| `SPC c c` | Claude Code sessions (consult-claude) |
| `SPC c d` | buffer diagnostics (flymake)    |
| `SPC o o` | open current file in Obsidian   |
| `SPC o f` | open current file in default app |
| `SPC o d` | open current directory in Finder |
| `SPC s`   | save buffer                     |
| `SPC w`   | delete current window           |
| `SPC n`   | vertical split + follow focus   |
| `SPC t`   | vsplit + ghostel terminal (project root) |
| `SPC u t` | vsplit + ghostel terminal (current dir) |
| `,`       | alias for the `C-c` prefix (normal/visual/motion) |
| `j` / `k` | down / up by visual line (`gj`/`gk` logical) |
| `-`       | jump to dired (current dir)     |
| `ff`      | recent file (normal state)      |
| `s-h/j/k/l` | move between windows          |
| `s-n`     | vertical split + follow focus   |
| `s-w`     | delete current window           |
| `S-s-[`   | rotate windows                  |
| `S-s-]`   | maximize window (delete others) |
| `s-]`     | embark act                      |
| `s-t`     | vsplit + open fresh ghostel terminal (project root) |
| `v` / `V` | expand / contract region (visual state) |
| `SPC h`   | help prefix                     |
| `SPC h t` | show startup time               |
| `K`       | Helpful for symbol at point (Elisp buffers) |

In dired, `h` goes up a directory, `l` enters the file/directory, and `TAB`
toggles a directory's subtree. `y` is a "yank" prefix that copies the entry's
path to the kill ring (`yl` true path, `yn` name, `yp` path, `yr` remote path),
with `yy` kept as the classic copy.

## Files

- `early-init.el` — startup performance tuning and UI chrome removal, loaded
  before packages.
- `init.el` — the main configuration.
- `index.html` — annotated browser walkthrough of `init.el`.

See [CLAUDE.md](CLAUDE.md) for architecture notes and editing conventions, and
[index.html](index.html) for the side-by-side walkthrough.
