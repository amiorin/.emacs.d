;;; init.el --- Main initialization -*- lexical-binding: t; -*-

;;; Commentary:
;; Main configuration entry point.  Bootstraps the package system, then
;; configures each package with one `use-package' form.  See CLAUDE.md for
;; the architecture overview (keybinding layers, completion stack, terminal
;; integration).

;;; Code:

;;; --- Package system --------------------------------------------------------

;; `package-enable-at-startup' is disabled in early-init.el, so set the package
;; system up explicitly here.
(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))

;; Fast activation via `package-quickstart'. A full `package-initialize' scans
;; every installed package's directory and `*-autoloads.el' on each startup
;; (~80ms here); the quickstart file is a single precompiled bundle of all those
;; autoloads plus the `load-path' and `package-activated-list', so loading it
;; performs the same activation in ~25ms. Setting `package-quickstart' also makes
;; package.el regenerate *and* byte-compile that file automatically whenever a
;; package is installed or removed, so it never goes stale.
;;
;; We deliberately skip the full `package-initialize': the quickstart file
;; populates `package-activated-list', and `package-installed-p' short-circuits
;; on that list while `package--initialized' is nil (its documented "usable
;; before package is fully initialized" path), so `use-package's `:ensure' is
;; satisfied without the expensive descriptor scan. The final branch handles the
;; first run (or a deleted quickstart file): full-initialize once, then build the
;; quickstart file so every subsequent startup takes the fast path.
;;
;; Load the bundle by its *suffix-less* name: `load' appends `load-suffixes'
;; (".elc" then ".el"), so it resolves the same compiled-first preference, and
;; -- crucially -- lets native-comp swap in a `.eln' when one exists. Passing an
;; explicit `.elc' would force the slower byte-code: the C loader sets
;; `no_native' from the `.elc' suffix and `maybe_swap_for_eln' then returns
;; before the eln lookup *and* marks the file no-native (see lread.c). `load'
;; with NOERROR returns nil if neither file exists, triggering the fallback.
(setq package-quickstart t)
;; Some `*-ts-mode' packages (e.g. astro-ts-mode) gate their `auto-mode-alist'
;; entry on a top-level `(treesit-ready-p ...)' call in their autoload file.
;; package.el bakes those autoload forms into package-quickstart.el, which we
;; load below -- *before* anything else pulls in treesit.el -- so the form would
;; hit a void `treesit-ready-p' and abort the whole bundle. `treesit-ready-p'
;; lives in treesit.el; preload it so those autoload forms evaluate cleanly.
;; (Guarded: `treesit-available-p' is a C builtin present on every build, but
;; treesit.el itself only exists on builds compiled with tree-sitter support.)
(when (treesit-available-p)
  (require 'treesit))
(unless (load (locate-user-emacs-file "package-quickstart") 'noerror 'nomessage)
  (package-initialize)
  (package-quickstart-refresh))

;; Ensure use-package is available.
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t)

;;; --- Core editor settings --------------------------------------------------

;; Disable backup files (the `filename~' clutter).
(setq make-backup-files nil)

;; Answer long yes/no prompts with a single `y' or `n', no RET required.
(setq use-short-answers t)

;; Keep Custom's machine-written settings out of init.el. With `custom-file'
;; unset, Custom defaults to `user-init-file' and rewrites its blocks into
;; init.el (which is how stale entries crept in before). Point it at its own
;; (gitignored) file so init.el stays hand-edited only.
(setq custom-file (locate-user-emacs-file "custom.el"))
(load custom-file 'noerror 'nomessage)

;; --- Mouse-wheel scrolling: scroll the buffer (view), not point ---
;;
;; In a terminal the wheel scrolls the buffer ONLY when Emacs receives real
;; mouse events. `xterm-mouse-mode' enables mouse reporting; without it the
;; terminal's "alternate scroll" turns the wheel into Up/Down arrow keys,
;; which move point (the cursor) instead of scrolling -- the symptom we saw.
;; (Harmless in GUI frames; it only affects terminal frames.)
(xterm-mouse-mode 1)

;; Steady, line-based wheel scrolling.  Point keeps its buffer position; the
;; cursor only gets dragged once it would otherwise leave the window (an
;; inherent Emacs constraint -- point must stay visible).
;; NOTE: `scroll-preserve-screen-position' is deliberately left nil -- setting
;; it pins point to a screen row and makes the cursor track the scroll, the
;; opposite of what we want.
(setq mouse-wheel-follow-mouse t
      mouse-wheel-progressive-speed nil
      mouse-wheel-scroll-amount '(2 ((shift) . 1) ((control) . text-scale))
      ;; Smooth keyboard scrolling too: one line at a time, no recentering.
      ;; (`scroll-step' is intentionally omitted -- it's ignored whenever
      ;; `scroll-conservatively' is > 100.)
      scroll-conservatively 101
      ;; Let the cursor reach the very window edge before it's pushed along.
      scroll-margin 0
      ;; Don't force the cursor line fully visible after a wheel scroll.
      make-cursor-line-fully-visible nil)

;; Line numbers in the gutter, and highlight the line the cursor is on.
(setq display-line-numbers-type t)
(global-display-line-numbers-mode 1)
(global-hl-line-mode 1)

;; recentf: track recently opened files (used by `consult-recent-file').
(use-package recentf
  :ensure nil
  :custom
  (recentf-max-saved-items 100)
  :init
  (recentf-mode 1)
  :config
  ;; Multiple Emacs instances each keep their own in-memory `recentf-list'
  ;; and overwrite the shared save file on exit, losing the other's entries.
  ;; Re-read the on-disk list and merge it in before every save so the last
  ;; writer wins without discarding what the other instance recorded.
  (defun neoemacs--recentf-merge-on-save (&rest _)
    (let ((mem recentf-list))
      (recentf-load-list)               ; reloads `recentf-list' from disk
      (setq recentf-list
            (seq-take (delete-dups (append mem recentf-list))
                      recentf-max-saved-items))))
  (advice-add 'recentf-save-list :before #'neoemacs--recentf-merge-on-save)

  ;; Closing the host terminal (e.g. Ghostty) kills Emacs with SIGHUP, and
  ;; Emacs's C-level shutdown on a fatal signal does NOT run `kill-emacs-hook'
  ;; — so `recentf-mode's normal save-on-exit never fires and the list is lost.
  ;; Save on an idle timer (quietly) instead: 5s after you stop interacting,
  ;; so a freshly visited file is persisted almost immediately with no churn
  ;; while idle. The merge advice above keeps each save from clobbering a
  ;; concurrent instance.
  (defun neoemacs--recentf-save-quietly ()
    (let ((save-silently t)
          (inhibit-message t))
      (recentf-save-list)))
  (run-with-idle-timer 5 t #'neoemacs--recentf-save-quietly))

;; autorevert: reload buffers whose backing file changed on disk, as long as the
;; buffer has no unsaved edits. `global-auto-revert-non-file-buffers' extends
;; this to dired/dirvish (and other non-file buffers) so directory listings
;; refresh too. Reverts are silent (`auto-revert-verbose nil').
(use-package autorevert
  :ensure nil
  :custom
  (global-auto-revert-non-file-buffers t)
  (auto-revert-verbose nil)
  :init
  (global-auto-revert-mode 1))

;;; --- Appearance: theme, icons, modeline ------------------------------------

;; doom-one theme.
(use-package doom-themes
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (load-theme 'doom-one t))

;; nerd-icons: icon fonts used by doom-modeline and others.
;; Run `M-x nerd-icons-install-fonts' once after first launch.
(use-package nerd-icons)

;; doom-modeline: fancy modeline matching the doom themes.
(use-package doom-modeline
  :after nerd-icons
  :init
  (doom-modeline-mode 1))

;;; --- Evil: Vim emulation ---------------------------------------------------

;; Evil: Vim emulation.
(use-package evil
  :init
  (setq evil-want-integration t
        evil-want-keybinding nil
        evil-want-C-u-scroll t
        ;; Don't echo "-- INSERT --"/"-- VISUAL --" etc. in the echo area.
        evil-echo-state nil)
  :config
  (evil-mode 1))

;; Evil-collection: Evil bindings for the rest of Emacs.
(use-package evil-collection
  :after evil
  :config
  ;; Don't load evil bindings for magit — keep its native keymap.
  (setq evil-collection-mode-list (delq 'magit evil-collection-mode-list))
  (evil-collection-init))

;; evil-terminal-cursor-changer: reflect the current evil state in the host
;; terminal's cursor shape. `cursor-type' only affects GUI Emacs, so in
;; `emacs -nw' the shape must be set with DECSCUSR escape sequences; this
;; package sends them on each evil state transition. We run inside zellij,
;; which forwards DECSCUSR to the real terminal natively -- no tmux-style DCS
;; passthrough is needed, and since $TMUX is unset the package sends the plain
;; sequences. Shapes: normal/visual/motion = block, insert = vertical bar,
;; replace/operator = underline, emacs = hollow box.
(use-package evil-terminal-cursor-changer
  :after evil
  :init
  (setq evil-normal-state-cursor   'box
        evil-visual-state-cursor   'box
        evil-motion-state-cursor   'box
        evil-insert-state-cursor   'bar
        evil-replace-state-cursor  'hbar
        evil-operator-state-cursor 'hbar
        evil-emacs-state-cursor    'hollow
	;; workaround for Ghostty
	visible-cursor             nil
        ;; Never blink the terminal cursor in any state: emit the steady
        ;; DECSCUSR codes (ESC [ 2/4/6 q) instead of the blinking ones.
        etcc-use-blink             nil)
  :config
  (evil-terminal-cursor-changer-activate))

;; evil-surround: operate on surrounding pairs. `ys{motion}{char}' adds, `cs'
;; changes, `ds' deletes a surrounding pair (e.g. `cs"'' turns "x" into 'x',
;; `ysiw)' wraps a word in parens). In visual state `S{char}' surrounds the
;; selection. tpope's vim-surround, ported to evil.
(use-package evil-surround
  :after evil
  :config
  (global-evil-surround-mode 1))

;; evil-commentary: comment toggling as an evil operator. `gcc' toggles the
;; current line, `gc{motion}' a region (e.g. `gcap' a paragraph), `gc' in
;; visual state the selection. Uses the major mode's comment syntax.
(use-package evil-commentary
  :after evil
  :config
  (evil-commentary-mode))

;; evil-goggles: briefly flash the region an edit acts on (yank, delete,
;; change, paste, indent, ...) so the affected text is visible -- useful in a
;; terminal where there's no other visual cue. `evil-goggles-use-diff-faces'
;; tints adds/deletes with the `diff-added'/`diff-removed' faces. Pulsing is
;; disabled (steady flash) since pulse animation is costly over a terminal.
(use-package evil-goggles
  :after evil
  :config
  (setq evil-goggles-duration 0.1
        evil-goggles-pulse nil)
  (evil-goggles-use-diff-faces)
  (evil-goggles-mode))

;;; --- Window management helpers ---------------------------------------------

(defun neoemacs/vsplit-window-follow ()
  "Split the window horizontally and move focus into the new split."
  (interactive)
  (evil-window-vsplit)
  (evil-window-right 1))

(defun neoemacs/vsplit-ghostel (&optional here)
  "Open a vertical split, move focus into it, and launch ghostel there.
If the current buffer belongs to a project, the terminal starts in the
project root; otherwise it inherits the current `default-directory'.
With a prefix arg (or non-nil HERE), always start in the current
`default-directory', ignoring the project root."
  (interactive "P")
  ;; Capture the project root from the *original* buffer before splitting,
  ;; since the split/placeholder buffer can carry a different directory.
  ;; projectile is deferred, so load it on demand if it hasn't loaded yet.
  (unless here (require 'projectile))
  (let ((root (and (not here) (projectile-project-root))))
    (neoemacs/vsplit-window-follow)
    (evil-buffer-new)
    ;; `evil-buffer-new' shows the empty "*new*" buffer in the window via
    ;; `set-window-buffer' without making it current, so grab it from the window.
    (let* ((placeholder (window-buffer))
           ;; Root the new terminal at the project root when there is one.
           ;; `let*' so `default-directory' is in effect before ghostel reads it.
           (default-directory (or root default-directory))
           ;; Non-numeric prefix arg => always create a fresh ghostel buffer in
           ;; the new split, rather than switching to an existing terminal.
           (ghostel-buffer (ghostel '(4))))
      ;; ghostel swaps in its own buffer; drop the empty placeholder.
      (when (and (buffer-live-p placeholder)
                 (not (eq placeholder ghostel-buffer)))
        (kill-buffer placeholder)))))

(defun neoemacs/vsplit-ghostel-here ()
  "Like `neoemacs/vsplit-ghostel' but ignore the project root.
The terminal always starts in the current `default-directory'."
  (interactive)
  (neoemacs/vsplit-ghostel t))

(defun neoemacs/describe-symbol-at-point ()
  "Describe the symbol under point without prompting in the minibuffer.
Uses Helpful, then selects the `helpful-mode' window so focus lands there
\(so you can scroll/navigate it and `q' to dismiss)."
  (interactive)
  (let ((sym (symbol-at-point)))
    (if sym
        (progn
          (helpful-symbol sym)
          (when-let ((win (seq-find
                           (lambda (w)
                             (provided-mode-derived-p
                              (buffer-local-value 'major-mode (window-buffer w))
                              'helpful-mode))
                           (window-list))))
            (select-window win)))
      (user-error "No symbol at point"))))

(defun neoemacs/find-file-in-config ()
  "Find a file under the Emacs config directory (`user-emacs-directory').
Opens a `find-file' prompt rooted at the private config dir (currently
`~/.config/neoemacs')."
  (interactive)
  (let ((default-directory user-emacs-directory))
    (call-interactively #'find-file)))

(defun neoemacs/dired-quick-look ()
  "Preview the file under point in dired/dirvish via macOS Quick Look.
Terminal Emacs (`emacs -nw') can't render images itself, and ghostel
only draws Kitty-graphics images under GUI Emacs, so previewing is
delegated to the OS: `qlmanage -p' pops a native Quick Look panel over
the frame (Esc/Space to dismiss).  Runs async so Emacs isn't blocked."
  (interactive)
  (let ((file (dired-get-filename nil t)))
    (unless file
      (user-error "No file on this line"))
    ;; BUFFER nil discards qlmanage's chatty stdout/stderr.
    (start-process "ql" nil "qlmanage" "-p" file)))

(defun neoemacs/open-in-finder ()
  "Reveal the current directory in macOS Finder.
In a dired/dirvish buffer this is the directory listed at point (so it
follows you into subdirs); elsewhere it's the visited file's directory,
falling back to `default-directory'.  Delegates to `open' so the
existing Finder window is reused."
  (interactive)
  (let ((dir (cond ((derived-mode-p 'dired-mode) (dired-current-directory))
                   (t default-directory))))
    (start-process "open-finder" nil "open" (expand-file-name dir))))

(defun neoemacs/open-in-obsidian ()
  "Open the current file in Obsidian.
In a dired/dirvish buffer this is the file under point; elsewhere it is
the visited file.  The vault is auto-detected by walking up to the
directory containing `.obsidian', whose folder name becomes the vault
name.  Hands an `obsidian://open' URL to macOS `open' (async)."
  (interactive)
  (let ((file (cond ((derived-mode-p 'dired-mode)
                     (or (dired-get-filename nil t)
                         (user-error "No file on this line")))
                    ((buffer-file-name))
                    (t (user-error "No file on this line or in this buffer")))))
    (setq file (expand-file-name file))
    (let ((root (locate-dominating-file file ".obsidian")))
      (unless root
        (user-error "Not inside an Obsidian vault (no .obsidian above %s)" file))
      (setq root (expand-file-name root))
      (let ((url (format "obsidian://open?vault=%s&file=%s"
                         (url-hexify-string
                          (file-name-nondirectory (directory-file-name root)))
                         (url-hexify-string (file-relative-name file root)))))
        (start-process "open-obsidian" nil "open" url)))))

;;; --- Keybindings -----------------------------------------------------------

;; General: convenient keybinding definitions, used here for a SPC leader.
(use-package general
  :after evil
  :config
  (general-create-definer neoemacs/leader
			  :states '(normal visual motion)
			  :keymaps 'override
			  :prefix "SPC"
			  :global-prefix "M-SPC")
  ;; `,' as a true alias for the `C-c' prefix. `general-simulate-key' replays
  ;; the real `C-c' sequence through the live keymaps, so `, x' invokes whatever
  ;; `C-c x' is bound to in the current buffer -- including major-mode maps
  ;; (`, C-c' -> `C-c C-c', etc.) -- without re-declaring anything. Restricted
  ;; to normal/visual/motion so a literal comma still types in insert state;
  ;; this does shadow evil's `,' (repeat-find-backwards) in those states.
  (general-define-key
   :states '(normal visual motion)
   :keymaps 'override
   "," (general-simulate-key "C-c"))
  (neoemacs/leader
   "SPC" '(projectile-find-file :which-key "find file in project")
   ","  '(consult-buffer :which-key "switch buffer")
   "f"  '(:ignore t :which-key "files")
   "ff" '(find-file :which-key "find file")
   "fp" '(neoemacs/find-file-in-config :which-key "find file in private config")
   "fr" '(consult-recent-file :which-key "recent file")
   "fd" '(consult-dir :which-key "switch dir (consult-dir)")
   "fi" '(neoemacs/dired-quick-look :which-key "quick look (dired)")
   "fo" '(neoemacs/open-in-finder :which-key "open dir in Finder")
   "b"  '(:ignore t :which-key "buffers")
   "bb" '(consult-buffer :which-key "switch buffer")
   "bd" '(kill-current-buffer :which-key "kill buffer")
   "bi" '(ibuffer :which-key "ibuffer")
   "bn" '(next-buffer :which-key "next buffer")
   "bp" '(previous-buffer :which-key "previous buffer")
   "bu" '(vundo :which-key "undo tree")
   "p"  '(:ignore t :which-key "project")
   "pp" '(consult-projectile :which-key "switch project")
   "pf" '(projectile-find-file :which-key "find file in project")
   "pb" '(projectile-switch-to-buffer :which-key "project buffer")
   "ps" '(consult-ripgrep :which-key "search in project")
   "g"  '(:ignore t :which-key "git")
   "gg" '(magit-status :which-key "status")
   "gb" '(magit-blame :which-key "blame")
   "gl" '(magit-log-buffer-file :which-key "log (this file)")
   "gj" '(diff-hl-next-hunk :which-key "next hunk")
   "gk" '(diff-hl-previous-hunk :which-key "prev hunk")
   "gs" '(diff-hl-stage-current-hunk :which-key "stage hunk")
   "gx" '(diff-hl-revert-hunk :which-key "revert hunk")
   "o"  '(:ignore t :which-key "open")
   "oo" '(neoemacs/open-in-obsidian :which-key "open file in Obsidian")
   "c"  '(:ignore t :which-key "code")
   "ca" '(eglot-code-actions :which-key "code actions")
   "cr" '(eglot-rename :which-key "rename symbol")
   "cf" '(eglot-format-buffer :which-key "format buffer")
   "cd" '(flymake-show-buffer-diagnostics :which-key "diagnostics")
   "n"  '(neoemacs/vsplit-window-follow :which-key "vsplit & follow")
   "s"  '(save-buffer :which-key "save buffer")
   "t"  '(neoemacs/vsplit-ghostel :which-key "ghostel (project root)")
   "w"  '(evil-window-delete :which-key "delete window")
   "u"  '(:ignore t :which-key "ghostel")
   "ut" '(neoemacs/vsplit-ghostel-here :which-key "ghostel here (current dir)")
   "/"  '(consult-ripgrep :which-key "search in project")
   "h"  '(help-command :which-key "help"))
  ;; Startup time readout. The dashboard used to show "Emacs started in N
  ;; seconds"; with it gone, expose `emacs-init-time' under the help map so it's
  ;; reachable as both `SPC h t' (via the leader's help prefix) and `C-h t'.
  ;; Bound into `help-map' the same way embark-bindings is (see the embark form).
  (define-key help-map "t" #'emacs-init-time)
  ;; `-' in normal state jumps to dired (vinegar-style).
  (general-define-key
   :states 'normal
   :keymaps 'override
   "-" 'dired-jump)
  ;; s-hjkl: move between windows.
  (general-define-key
   :keymaps 'override
   "s-h" 'evil-window-left
   "s-j" 'evil-window-down
   "s-k" 'evil-window-up
   "s-l" 'evil-window-right
   "s-n" 'neoemacs/vsplit-window-follow
   "s-w" 'evil-window-delete
   "S-s-[" 'evil-window-rotate-downwards
   "S-s-]" 'delete-other-windows)
  ;; `K' in Elisp buffers describes the symbol under point (no prompt).
  (general-define-key
   :states 'normal
   :keymaps '(emacs-lisp-mode-map lisp-interaction-mode-map)
   "K" 'neoemacs/describe-symbol-at-point)
  ;; Make `j'/`k' move by *visual* line so navigation follows wrapped text
  ;; instead of jumping over a whole logical line. `gj'/`gk' are swapped to the
  ;; logical-line motions so the old behaviour is still one keystroke away.
  ;; (`h'/`l' are character motions that already walk through a wrap.)
  (general-define-key
   :states '(normal visual motion)
   "j"  'evil-next-visual-line
   "k"  'evil-previous-visual-line
   "gj" 'evil-next-line
   "gk" 'evil-previous-line))

;; expand-region: grow/shrink the selection by semantic units. In visual
;; state `v' expands the region and `V' contracts it.
;; `:after (evil general)' alone would *load* expand-region as soon as general
;; loads (at startup). The `v'/`V' bindings only reference its autoloaded
;; commands, so set them up in `:init' (which still runs after evil+general are
;; available) and keep the package itself deferred via `:commands' -- it loads
;; the first time you expand a region in visual state.
(use-package expand-region
  :after (evil general)
  :commands (er/expand-region er/contract-region)
  :init
  (general-define-key
   :states 'visual
   "v" 'er/expand-region
   "V" 'er/contract-region))

;; vundo: visualize the undo history as a tree in a transient buffer. Unlike
;; `undo-tree' it does not replace Emacs's undo system -- it sits on top of the
;; built-in undo that evil already drives, so it stays a pure visualizer with
;; no persistent history files. Reached via `SPC b u' (see the leader block).
;; Use the Unicode box-drawing glyphs for a cleaner tree in the terminal.
(use-package vundo
  :commands (vundo)
  :config
  (setq vundo-glyph-alist vundo-unicode-symbols))

;; which-key: popup showing available keybindings.
(use-package which-key
  :ensure nil
  :config
  ;; Mirrors Doom's which-key tuning for readability.
  (setq which-key-sort-order #'which-key-key-order-alpha
        which-key-sort-uppercase-first nil
        which-key-add-column-padding 1
        which-key-max-display-columns nil
        which-key-min-display-lines 6
        which-key-side-window-slot -10)
  (which-key-setup-side-window-bottom)
  (add-hook 'which-key-init-buffer-hook
            (lambda () (setq-local line-spacing 3)))
  (which-key-mode 1))

;;; --- Completion stack ------------------------------------------------------

;; Vertico: vertical completion UI in the minibuffer.
(use-package vertico
  :init
  (vertico-mode 1))

;; vertico-directory: ships with the vertico package (`:ensure nil', it's an
;; extension file on vertico's load-path). Makes the minibuffer behave like a
;; path editor when completing file names: `RET' on a directory enters it
;; instead of exiting, `DEL'/`M-DEL' delete a path component at a time. The
;; `rfn-eshadow-update-overlay' tidy hook removes the shadowed `~/' or `/'
;; prefix when you type an absolute path.
(use-package vertico-directory
  :ensure nil
  :after vertico
  :bind (:map vertico-map
              ("RET"   . vertico-directory-enter)
              ("DEL"   . vertico-directory-delete-char)
              ("M-DEL" . vertico-directory-delete-word))
  :hook (rfn-eshadow-update-overlay . vertico-directory-tidy))

;; Orderless: space-separated, order-independent completion matching.
(use-package orderless
  :init
  (setq completion-styles '(orderless basic)
        completion-category-overrides '((file (styles partial-completion)))))

;; Marginalia: rich annotations in the minibuffer margin.
(use-package marginalia
  :init
  (marginalia-mode 1))

;; nerd-icons-completion: prepend a colored nerd-font icon to each completion
;; candidate (file/dir/buffer/...), matching the icons dirvish already shows.
;; It works by wrapping the category's `affixation-function' (via an advice on
;; `completion-metadata-get'), so files get an extension-colored icon and
;; directories a distinct folder icon -- the "icons" half of colored find-file.
;;
;; The "text color" half: `neoemacs--completion-color-dirs' is a second advice
;; that runs *outside* nerd-icons (added last => outermost), post-processing the
;; affixation tuples nerd-icons returns and tinting the *name* of directory
;; candidates (those ending in `/') with `nerd-icons-completion-dir-face' -- the
;; same color as the folder icon. File names keep their default face; their type
;; color comes from the icon. Composes cleanly because nerd-icons preserves the
;; candidate string it's handed, and we only add a face property to it.
(use-package nerd-icons-completion
  :after (marginalia nerd-icons)
  :config
  (defun neoemacs--completion-color-dirs (orig metadata prop)
    "Tint directory candidate names in `file' completion.
Wraps the affixation-function returned further down the advice chain
\(including nerd-icons') and faces the name of any candidate ending in `/'."
    (let ((res (funcall orig metadata prop)))
      (if (and (eq prop 'affixation-function)
               res
               (eq (completion-metadata-get metadata 'category) 'file))
          (lambda (cands)
            (mapcar (lambda (item)
                      ;; Each item is (CAND PREFIX SUFFIX); CAND is the name.
                      (if (and (consp item)
                               (stringp (car item))
                               (string-suffix-p "/" (car item)))
                          (cons (propertize (car item)
                                            'face 'nerd-icons-completion-dir-face)
                                (cdr item))
                        item))
                    (funcall res cands)))
        res)))
  ;; Enable nerd-icons' advice first so ours, added next, sits outermost and
  ;; post-processes its output.
  (nerd-icons-completion-mode 1)
  (advice-add 'completion-metadata-get :around #'neoemacs--completion-color-dirs))

;; Consult: enhanced search and navigation commands.
(use-package consult
  :bind (("C-s"   . consult-line)
         ("C-x b" . consult-buffer)
         ("M-y"   . consult-yank-pop)
         ("M-g g" . consult-goto-line)
         ("M-g i" . consult-imenu)))

;; consult-dir: switch the *directory context* from inside the minibuffer.
;; `C-x C-d' globally jumps to a directory (recent dirs, projectile roots,
;; bookmarks -- it reads recentf/projectile, both already configured); the same
;; chord *inside* an active find-file/consult prompt re-roots that prompt at the
;; chosen directory without restarting it, and `C-x C-j' fuzzy-jumps to any file
;; beneath it. Also on the leader at `SPC f d'.
;;
;; Startup: `:bind' autoloads the commands and installs the bindings without
;; loading the package -- it loads on first use. Deliberately NO `:after
;; (consult vertico)': that would force consult-dir to load the moment both are
;; up (vertico is on at startup), spending its load cost eagerly for no gain.
;; The minibuffer binding only needs `vertico-map' to be defined, which it is
;; once `vertico-mode' has run (the vertico form above), so pure autoload
;; deferral is the cheaper path and the `:map' binding still resolves.
(use-package consult-dir
  :bind (("C-x C-d" . consult-dir)
         :map vertico-map
         ("C-x C-d" . consult-dir)
         ("C-x C-j" . consult-dir-jump-file)))

;; Embark: "right-click for Emacs" — a context menu of actions on the target at
;; point or the current minibuffer candidate. `s-]' acts (matching this config's
;; other s- chords); `M-.' runs the most likely default action (this overrides
;; the default `xref-find-definitions' on M-.). Rebinding `b' in `help-map'
;; makes embark-bindings — a searchable, actionable list of active bindings —
;; the replacement for the default `describe-bindings' (which it's a superset
;; of) under every help prefix, i.e. both `C-h b' and the leader's `SPC h b'.
(use-package embark
  :bind (("s-]" . embark-act)
         ("M-." . embark-dwim)
         :map help-map
         ("b" . embark-bindings))
  :init
  ;; Replace the prefix-key help (e.g. `C-x C-h') with a filterable, actionable
  ;; list of that prefix's bindings; complements which-key's passive popup.
  (setq prefix-help-command #'embark-prefix-help-command))

;; embark-consult: glue between Embark and Consult — lets Embark export/act on
;; consult candidates (e.g. consult-line/grep -> an editable results buffer) and
;; previews candidates at point inside Embark Collect buffers.
(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;; wgrep: edit grep results in place and write the changes back to the files.
;; The project-wide search-and-replace loop: `consult-ripgrep' to find,
;; `embark-export' (s-] then E) the candidates into a `grep-mode' buffer, then
;; `C-c C-p' (wgrep-change-to-wgrep-mode) makes it editable — query-replace as
;; usual and `C-c C-c' saves every touched file (`C-c C-k' aborts).
(use-package wgrep
  :commands (wgrep-change-to-wgrep-mode)
  :custom (wgrep-auto-save-buffer t))

;; Helpful: richer replacements for the built-in help buffers. Each command
;; opens a `helpful-mode' buffer that adds the symbol's source, callers/
;; references, current value, and key bindings on top of the default help.
;; Bindings go in `help-map' (same pattern as the embark form above), so they
;; apply under both `C-h' and the leader's `SPC h': `f' callable (functions and
;; macros), `v' variable, `k' key, `x' command, `o' any symbol. `K' in Elisp
;; buffers (see `neoemacs/describe-symbol-at-point') routes here too.
(use-package helpful
  :bind (:map help-map
              ("f" . helpful-callable)
              ("v" . helpful-variable)
              ("k" . helpful-key)
              ("x" . helpful-command)
              ("o" . helpful-symbol))
  :config
  ;; Drop the "References" section. It hands off to `elisp-refs', which reads
  ;; the *entire* file where the symbol is defined into a buffer and walks
  ;; every sexp looking for callers — for big core files (`simple.el',
  ;; `subr.el', ...) that parse is what makes opening a help page take
  ;; seconds. `ignore' swallows the args and returns nil, so the section is
  ;; empty and the scan never runs; every other section is untouched.
  (advice-add 'helpful--calculate-references :override #'ignore))

;; ibuffer: a `dired'-like buffer list with marks and bulk actions, the heavy
;; counterpart to `consult-buffer' (`SPC ,'/`SPC b b'). Built in, so `:ensure
;; nil'. Replaces the default `list-buffers' on `C-x C-b' and is on the leader
;; at `SPC b i'. Evil keys come from evil-collection (ibuffer is in its list, so
;; `j'/`k' move, `m'/`u' mark/unmark, `x' executes, `d'/`D' flag/kill, `g'
;; refreshes, `RET'/`o' visit, `/' filters). `ibuffer-expert' drops the
;; per-buffer "really kill?" confirmation; `ibuffer-auto-mode' keeps the list
;; live as buffers come and go. Groups come from `ibuffer-projectile' below.
;;
;; Embark + ibuffer workflow: the two meet through `embark-export'. From
;; `consult-buffer' (`SPC ,'), type to narrow to the buffers you care about,
;; then `embark-act' (`s-]') and `E' (export) — for buffer candidates Embark
;; exports straight into an *Ibuffer* showing exactly that filtered set. Mark
;; (`m'), then bulk-act (`D' kill, `S' save, `Q' query-replace, `s-]' on the
;; row for the full Embark action menu) — i.e. filter in the minibuffer, hand
;; off to ibuffer for the multi-buffer operation.
(use-package ibuffer
  :ensure nil
  :bind (("C-x C-b" . ibuffer))
  :hook (ibuffer-mode . ibuffer-auto-mode)
  :custom
  (ibuffer-expert t)
  (ibuffer-show-empty-filter-groups nil))

;; ibuffer-projectile: group ibuffer by Projectile project.
(use-package ibuffer-projectile
  :hook (ibuffer-mode . ibuffer-projectile-set-filter-groups))

;;; --- In-buffer completion (corfu/cape) -------------------------------------

;; Corfu: the at-point completion popup -- the in-buffer counterpart to the
;; vertico minibuffer stack above (vertico handles `M-x'/find-file prompts;
;; corfu handles completion *inside* a buffer, e.g. the candidates eglot
;; produces while typing code). Together they give the whole completion surface.
;;
;; Deferred: `global-corfu-mode' is autoloaded, so adding it to
;; `emacs-startup-hook' arms it without loading corfu during init -- the package
;; loads when the hook fires, right after the first frame paints and after
;; `emacs-init-time' is recorded, i.e. off the startup critical path (same
;; pattern as diff-hl above). Nothing can trigger completion before then anyway.
(use-package corfu
  :defer t
  :init
  (add-hook 'emacs-startup-hook #'global-corfu-mode)
  :custom
  ;; Pop up automatically as you type (don't wait for an explicit TAB).
  (corfu-auto t)
  (corfu-auto-prefix 2)            ; ...after 2 chars
  (corfu-auto-delay 0.1)
  (corfu-cycle t)                  ; wrap around at the ends of the list
  ;; Don't preselect a candidate -- keep the typed prefix selected so RET inserts
  ;; what you typed unless you've explicitly moved into the list.
  (corfu-preselect 'prompt))

;; corfu-terminal: corfu's default popup is a child frame, which doesn't exist
;; in `emacs -nw'. This package re-renders the popup as a buffer overlay so it
;; works in the terminal. `:after corfu' loads it when corfu loads (on the
;; startup hook above), and the `display-graphic-p' guard makes it a no-op if
;; this config is ever opened in a GUI frame (where the native child frame is
;; better).
(use-package corfu-terminal
  :after corfu
  :config
  (unless (display-graphic-p)
    (corfu-terminal-mode 1)))

;; Cape: extra `completion-at-point' backends. eglot installs its own LSP capf
;; buffer-locally in managed buffers (so code completion there comes from the
;; language server); these add file-path and dabbrev (in-buffer word) completion
;; as fallbacks everywhere else -- e.g. completing a `./src/...' path or a word
;; already in the buffer. The functions are autoloaded, so adding them to the
;; hook in `:init' doesn't force-load cape; the package loads on first use.
(use-package cape
  :after corfu
  :init
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-dabbrev))

;;; --- Git -------------------------------------------------------------------

;; Magit: Git interface.
(use-package magit
  :bind (("C-x g" . magit-status)
         ;; In magit-status, `e' diffs the working tree against HEAD via ediff
         ;; (overrides the default `magit-ediff-dwim').
         :map magit-status-mode-map
         ("e" . magit-ediff-show-working-tree))
  :custom
  ;; Open magit-status in the current window instead of splitting; diffs and
  ;; other secondary buffers still pop to another window as usual.
  (magit-display-buffer-function
   #'magit-display-buffer-same-window-except-diff-v1))

;; Transient: the popup-menu engine behind magit (and many other packages).
;; Make `<escape>' an alias for `C-g' (transient-quit-one) so pressing Esc backs
;; out of any transient popup one level, just like C-g. Bound in `transient-map'
;; so it applies to every transient, not only magit's. Note: in a terminal Esc
;; is also the Meta prefix, so this slightly trades away Meta chords *inside* an
;; open transient — acceptable here since transient popups rarely need them.
;; Deferred (`:defer t'): nothing at startup uses transient -- it's pulled in
;; lazily when magit (or another transient command) first opens a popup, and the
;; `:config' keybinding applies then. Loading it eagerly only slows startup.
(use-package transient
  :ensure nil
  :defer t
  :config
  (define-key transient-map (kbd "<escape>") #'transient-quit-one))

;; Ediff: skip the "Quit this Ediff session? (y or n)" confirmation. `ediff-quit'
;; hard-codes a `y-or-n-p' before tearing down; locally stub it to always answer
;; yes for the duration of the call so `q' quits immediately.
;; Deferred (`:defer t'): ediff is a large package only needed when a diff
;; session starts (e.g. from magit). `:custom' is applied without loading it;
;; the `:config' quit advice runs once ediff loads on first use.
(use-package ediff
  :ensure nil
  :defer t
  :custom
  ;; Side-by-side diff buffers (vertical divider) instead of stacked, and keep
  ;; the control panel in the same frame rather than a popup.
  (ediff-split-window-function #'split-window-horizontally)
  (ediff-window-setup-function #'ediff-setup-windows-plain)
  :config
  (defun neoemacs--ediff-quit-no-confirm (orig-fn &rest args)
    "Run ORIG-FN with `y-or-n-p' auto-confirmed so ediff quits silently."
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
      (apply orig-fn args)))
  (advice-add 'ediff-quit :around #'neoemacs--ediff-quit-no-confirm))

;; diff-hl: VC diff indicators (added/changed/removed) next to each line.
;; `diff-hl-margin-mode' renders them in the *margin* with text glyphs rather
;; than the fringe -- the fringe doesn't exist in terminal Emacs (`emacs -nw'),
;; so the default fringe display would show nothing. `global-diff-hl-mode' turns
;; it on everywhere; both modes are autoloaded, so the startup hook below can
;; enable them after init without requiring the package during the init path.
;;
;; Magit doesn't update VC state the way save-based diff-hl expects, so the two
;; refresh hooks keep the indicators in sync when magit stages/commits. They're
;; added to magit's hooks here; magit loads lazily and runs them when it does.
;; Hunk navigation/staging is on the leader: `SPC g j/k/s/x' (see the general
;; block).
(use-package diff-hl
  :defer t
  :init
  ;; Enable on `emacs-startup-hook' rather than eagerly. At startup the only
  ;; buffers are `*scratch*'/`*Messages*' (no VC state to show), so loading
  ;; diff-hl during init buys nothing but ~50ms on the critical path. The hook
  ;; fires once, right after init -- after `emacs-init-time' is recorded and
  ;; after the first frame paints -- so the package (and its dired/magit hooks
  ;; in `:config') is ready before you could open a file, off the startup clock.
  (add-hook 'emacs-startup-hook
            (lambda ()
              (global-diff-hl-mode 1)
              (diff-hl-margin-mode 1)))
  :custom
  ;; The text glyphs shown in the margin per change type. These are diff-hl's
  ;; own defaults, pinned here explicitly so the look is stable and documented
  ;; (and matches the terminal indicators in my Doom config). The defcustom's
  ;; `:set' clears `diff-hl-margin-spec-cache', so setting it via `:custom'
  ;; (rather than a bare `setq') refreshes the rendered glyphs correctly.
  (diff-hl-margin-symbols-alist '((insert    . "+")
                                  (delete    . "-")
                                  (change    . "!")
                                  (unknown   . "?")
                                  (ignored   . "i")
                                  (reference . " ")))
  :config
  ;; FIX: doom-one defines `diff-hl-insert/delete/change' with foreground EQUAL
  ;; to background (e.g. `(diff-hl-insert :foreground vc-added :background
  ;; vc-added)'). The margin faces inherit those, so the +/-/! glyph is drawn in
  ;; the same color as the cell behind it -- visible only as a solid colored
  ;; block. Stripping the background (as my Doom vc-gutter module does for the
  ;; fringe) leaves just the foreground, so the glyphs actually show.
  ;;
  ;; Loading/enabling any theme re-applies its own face specs, restoring the
  ;; offending background, so we run this on `enable-theme-functions' (Emacs 29+,
  ;; called with the theme name after each theme is enabled) and once now for the
  ;; theme that's already active.
  (defun +diff-hl-strip-margin-face-backgrounds (&rest _)
    (dolist (face '(diff-hl-insert diff-hl-delete diff-hl-change))
      (set-face-background face nil)))
  (add-hook 'enable-theme-functions #'+diff-hl-strip-margin-face-backgrounds)
  (+diff-hl-strip-margin-face-backgrounds)
  (add-hook 'magit-pre-refresh-hook  #'diff-hl-magit-pre-refresh)
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)
  ;; Per-file VC status in dired/dirvish buffers. Dirvish buffers are derived
  ;; dired buffers, so this covers both. It renders via `diff-hl-margin-mode'
  ;; (enabled above), so the glyphs are visible in terminal Emacs -- unlike
  ;; dirvish's own `vc-state' attribute, which uses overlays and shows nothing
  ;; in `emacs -nw'. `-unless-remote' skips TRAMP dirs where the per-file VC
  ;; lookups would be slow.
  (add-hook 'dired-mode-hook #'diff-hl-dired-mode-unless-remote))

;;; --- Dired / file management -----------------------------------------------

;; Dirvish: a polished dired replacement with previews and icons.
(use-package dirvish
  :after (nerd-icons general)
  :init
  (dirvish-override-dired-mode 1)
  ;; `global-display-line-numbers-mode' turns the gutter on everywhere; a file
  ;; manager has no use for it, so switch it back off in dired/dirvish buffers.
  (add-hook 'dired-mode-hook (lambda () (display-line-numbers-mode -1)))
  :custom
  ;; `vc-state' is dropped here: it's an overlay-based attribute that shows
  ;; nothing in terminal Emacs. Per-file VC status comes from `diff-hl-dired-mode'
  ;; instead (see the diff-hl block), which renders in the margin.
  (dirvish-attributes '(nerd-icons subtree-state))
  ;; Show the full `ls -l' detail columns (permissions, link count, owner,
  ;; group, size, mtime) instead of dirvish's default hidden-details view.
  ;; `file-size' is dropped from the attributes above because `-l' already
  ;; prints a real size column, so the overlay would be redundant.
  (dirvish-hide-details nil)
  ;; `-A' ("almost all") lists dotfiles but omits the `.' and `..' entries;
  ;; `-l' keeps the long format. (Plain `-a' is what shows `.' and `..'.)
  ;; `--group-directories-first' sorts directories ahead of files, but it's a
  ;; GNU `ls' extension; macOS ships BSD `ls' which lacks it, so use Homebrew
  ;; coreutils `gls' when present and fall back to plain `-Al' otherwise.
  (insert-directory-program (if (executable-find "gls") "gls" "ls"))
  (dired-listing-switches (if (executable-find "gls")
                              "-Al --group-directories-first"
                            "-Al"))
  ;; Show a real block cursor in dired/dirvish buffers. By default dirvish
  ;; hides it (`cursor-type' nil + a zero-width `evil-normal-state-cursor')
  ;; and relies on the hl-line highlight; keeping it visible makes dirvish
  ;; use a `(box . 4)' block, which etcc renders as a terminal block cursor.
  (dirvish-hide-cursor nil)
  ;; Two-pane file manager: with two dired/dirvish windows side by side, the
  ;; rename/copy (`R'/`C') operations default their target to the directory
  ;; shown in the *other* window, so `R' moves marked files across panes. The
  ;; prompt is still editable/confirmable.
  (dired-dwim-target t)
  :bind ("C-c f" . dirvish)
  :config
  ;; Vim-style navigation: h goes up a directory, l enters the file/dir.
  (general-define-key
   :states 'normal
   :keymaps 'dired-mode-map
   "h" 'dired-up-directory
   "l" 'dired-find-file
   "TAB" 'dirvish-subtree-toggle))

;; Colorize the `ls -l' columns (permission flags, link count, owner, group,
;; size, mtime) with distinct faces. Dirvish buffers are derived dired
;; buffers, so hooking `diredfl-mode' onto `dired-mode' tints them too.
(use-package diredfl
  :hook (dired-mode . diredfl-mode))

;; dired-x ships with Emacs. `dired-omit-mode' hides uninteresting files: the
;; default `dired-omit-files' regexp drops auto-save/lock files and `.'/`..',
;; while `dired-omit-extensions' (which defaults to `completion-ignored-
;; extensions': `.elc', `.o', `.pyc', ...) drops compiled/generated artifacts.
;; This keeps them out of the listing entirely rather than just dimming them
;; with diredfl. Covers dirvish too (derived dired).
(use-package dired-x
  :ensure nil
  :hook (dired-mode . dired-omit-mode)
  :config
  (setq dired-omit-verbose nil))

;;; --- Terminal integration --------------------------------------------------

;; kkp: Kitty Keyboard Protocol support for terminal Emacs, enabling
;; key combinations the terminal would otherwise swallow (e.g. C-S-x).
(use-package kkp
  :config
  (global-kkp-mode 1))

;; clipetty: send kills to the host system clipboard via the OSC 52 escape
;; sequence, so copying in terminal Emacs works through SSH and tmux.
(use-package clipetty
  :hook (after-init . global-clipetty-mode))

;; Ghostel: terminal emulator powered by libghostty. The native module is a
;; prebuilt binary that auto-downloads on first use.
(use-package ghostel
  :commands (ghostel)
  :bind ("s-t" . neoemacs/vsplit-ghostel)
  ;; `global-display-line-numbers-mode' turns the gutter on everywhere; a
  ;; terminal buffer has no use for it, so turn it off in ghostel buffers.
  :hook (ghostel-mode . (lambda () (display-line-numbers-mode -1))))

;; evil-ghostel: keeps the terminal cursor in sync with Emacs point across
;; evil state transitions, so normal-state hjkl navigation works.
(use-package evil-ghostel
  :after (ghostel evil)
  :hook (ghostel-mode . evil-ghostel-mode)
  :config
  (defvar neoemacs/ghostel-escape-timeout 0.25
    "Seconds to wait for a second ESC in ghostel insert state.")

  (defun neoemacs/ghostel--escape-event-p (event)
    "Return non-nil when EVENT is an Escape key event."
    (or (eq event 'escape)
        (and (integerp event) (= event ?\e))))

  (defun neoemacs/ghostel--evil-insert-escape ()
    "Run Evil's insert-state Escape binding."
    (let ((cmd (lookup-key evil-insert-state-map (kbd "<escape>"))))
      (call-interactively (if (commandp cmd) cmd #'evil-force-normal-state))))

  (defun neoemacs/ghostel-escape-dwim ()
    "Send a single ESC to ghostel, but let double ESC leave insert state."
    (interactive)
    ;; `read-key' decodes KKP/input-decode-map sequences; `read-event' would
    ;; see raw bytes and can leak them to ghostel as control characters.
    (let ((event (with-timeout (neoemacs/ghostel-escape-timeout nil)
                   (read-key nil t))))
      (if (neoemacs/ghostel--escape-event-p event)
          (neoemacs/ghostel--evil-insert-escape)
        (when event
          (setq unread-command-events (cons event unread-command-events)))
        (ghostel-send-key "escape"))))

  (defun neoemacs/ghostel-send-current-control ()
    "Send the current Ctrl+letter key to ghostel."
    (interactive)
    (let ((base (event-basic-type last-command-event)))
      (unless (and (integerp base) (<= ?a base) (<= base ?z))
        (user-error "Not a Ctrl+letter key: %S" last-command-event))
      (ghostel-send-key (string base) "ctrl")))

  (evil-define-key* 'insert evil-ghostel-mode-map
		    (kbd "<escape>") #'neoemacs/ghostel-escape-dwim
		    (kbd "C-c") #'neoemacs/ghostel-send-current-control
		    (kbd "C-x") #'neoemacs/ghostel-send-current-control)

  ;; Let normal-state motion roam over animated output. Each redraw,
  ;; `ghostel--redraw-now' re-anchors any window following the live viewport
  ;; via `ghostel--anchor-window', whose final `set-window-point' snaps point
  ;; back to the terminal cursor (`ghostel--cursor-char-pos'). On a static
  ;; terminal redraws are rare so it's invisible; on an animated one (~30fps)
  ;; it fights every hjkl. evil-ghostel preserves point in its `ghostel--redraw'
  ;; advice but never touches the anchor, so off-prompt normal-state motion is
  ;; the unhandled seam. Skip the anchor while parked off the live cursor in a
  ;; motion-capable evil state; auto-follow resumes on return to insert or to
  ;; the cursor row. FORCE anchors (paste/yank) are always honored.
  (define-advice ghostel--anchor-window
      (:around (orig &optional window force) evil-ghostel-roam)
    (if (and (bound-and-true-p evil-ghostel-mode)
             (not force)
             (memq evil-state '(normal visual operator motion))
             ghostel--cursor-char-pos
             (/= (point) ghostel--cursor-char-pos))
        nil
      (funcall orig window force)))

  ;; Wheel scroll => leave insert. In insert state the redraw anchor
  ;; (`ghostel--anchor-window') re-snaps the viewport to the live cursor, so a
  ;; mouse-wheel scroll into scrollback is immediately yanked back. Normal state
  ;; is exactly where `evil-ghostel-roam' (above) suppresses that anchor, so flip
  ;; to normal on any wheel event over a ghostel buffer. ghostel redispatches
  ;; wheel events to `mwheel-scroll' when it scrolls the Emacs buffer (mouse
  ;; tracking off); advise that. Only switch *from* insert/emacs (normal/visual
  ;; already roam, and we mustn't drop a visual selection). Re-enter insert
  ;; (`i'/`a') yourself to resume live auto-follow.
  (define-advice mwheel-scroll
      (:before (event &rest _) evil-ghostel-wheel-normal)
    (let ((buf (window-buffer (posn-window (event-start event)))))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (when (and (bound-and-true-p evil-ghostel-mode)
                     (memq evil-state '(insert emacs)))
            (evil-normal-state)))))))

;;; --- Project navigation ----------------------------------------------------

;; Projectile: project interaction and navigation.
;;
;; Deferred (`:defer t'): loading projectile eagerly cost ~85ms+ on the startup
;; path because projectile.el pulls in `transient' (for its dispatch menu),
;; `compile' and `comint' the moment it loads. Nothing needs it before the first
;; project command, so let the autoloaded commands (`projectile-find-file' etc.,
;; reached via the leader and `C-c p') and `:bind-keymap' pull it in on demand;
;; `projectile-mode' is then turned on from `:config'. The zellij tab-name hook
;; calls `projectile-project-root', which is NOT autoloaded, so its
;; `(fboundp ...)' guard short-circuits to the dired/file-dir fallback until a
;; real projectile command loads the package -- it never force-loads it at
;; startup. (Before, the dashboard's projects section forced projectile in; with
;; the dashboard gone, this deferral is finally a clean win.)
(use-package projectile
  :defer t
  :bind-keymap ("C-c p" . projectile-command-map)
  :config
  (projectile-mode 1))

;; consult-projectile: consult-powered project navigation.
;; Reached via the leader at `SPC p p' (see the general config above).
(use-package consult-projectile
  :after (consult projectile))

;;; --- Languages -------------------------------------------------------------

;; markdown-mode: major mode for editing Markdown. `gfm-mode' is used for
;; README.md and other GitHub-Flavored Markdown files.
;;
;; Wiki links (`[[note]]') are enabled for Obsidian-style linking. The defaults
;; are tuned for vaults: `markdown-wiki-link-search-subdirectories' resolves a
;; bare `[[note]]' to a file anywhere under the vault (Obsidian flattens names),
;; and `markdown-link-space-sub-char' " " keeps the link text matching real
;; filenames with spaces instead of substituting underscores. Follow the link
;; under point with `C-c C-o' (`markdown-follow-thing-at-point').
(use-package markdown-mode
  :mode (("README\\.md\\'" . gfm-mode)
         ("\\.md\\'"       . markdown-mode)
         ("\\.markdown\\'" . markdown-mode))
  :custom
  (markdown-enable-wiki-links t)
  (markdown-wiki-link-search-subdirectories t)
  (markdown-link-space-sub-char " "))

;; --- Tree-sitter grammars --------------------------------------------------
;;
;; All the `*-ts-mode' major modes below need their tree-sitter grammar compiled
;; and on `treesit-extra-load-path'. `treesit-language-source-alist' tells
;; `treesit-install-language-grammar' where to fetch and how to build each one;
;; populating it is cheap (just an alist), so it's done eagerly. The actual
;; install (a git clone + C compile) only runs lazily from each mode's `:config'
;; below, and only when the grammar is missing -- never on the startup path.
;;
;; Astro injects other languages into a `.astro' file (TS in the frontmatter,
;; CSS in <style>, TSX-ish markup), so `astro-ts-mode' relies on the css and tsx
;; grammars in addition to its own. tsx/typescript live in subdirectories of one
;; repo, hence the explicit SOURCE-DIR field.
(setq treesit-language-source-alist
      '((astro      "https://github.com/virchau13/tree-sitter-astro")
        (css        "https://github.com/tree-sitter/tree-sitter-css")
        (clojure    "https://github.com/sogaiu/tree-sitter-clojure")
        (typescript "https://github.com/tree-sitter/tree-sitter-typescript" nil "typescript/src")
        (tsx        "https://github.com/tree-sitter/tree-sitter-typescript" nil "tsx/src")))

(defun neoemacs--ensure-treesit-grammars (&rest langs)
  "Install each grammar in LANGS via tree-sitter if it isn't already built.
A no-op once the grammars exist, so it's safe to call from a mode `:config'
\(it runs the slow git-clone + compile only on first use of each language)."
  (dolist (lang langs)
    (unless (treesit-language-available-p lang)
      (treesit-install-language-grammar lang))))

;; typescript-ts-mode / tsx-ts-mode ship with Emacs (29+), so `:ensure nil'.
;; Astro projects are full of `.ts'/`.tsx' siblings; route them here and let
;; eglot (below) attach for LSP. `:mode' keeps the mode -- and the grammar
;; install in `:config' -- deferred until such a file is opened.
(use-package typescript-ts-mode
  :ensure nil
  :mode (("\\.ts\\'"  . typescript-ts-mode)
         ("\\.tsx\\'" . tsx-ts-mode))
  :config
  (neoemacs--ensure-treesit-grammars 'typescript 'tsx))

;; astro-ts-mode: tree-sitter major mode for `.astro' single-file components.
;; `:mode' defers the whole package (and its grammar install) until the first
;; `.astro' file is visited -- zero startup cost. eglot attaches via the shared
;; hook in the eglot block below.
(use-package astro-ts-mode
  :mode "\\.astro\\'"
  :config
  (neoemacs--ensure-treesit-grammars 'astro 'css 'tsx))

;; clojure-ts-mode: tree-sitter major mode for Clojure/ClojureScript/cljc/edn.
;; Deferred via `:mode' like astro/typescript -- the grammar is ensured
;; (compiled if missing) on first visit, so there's zero startup cost. eglot
;; attaches via the shared hook in the eglot block below; cider and
;; evil-cleverparens hook on at the end of the file.
(use-package clojure-ts-mode
  :mode (("\\.clj\\'"  . clojure-ts-mode)
         ("\\.cljs\\'" . clojure-ts-clojurescript-mode)
         ("\\.cljc\\'" . clojure-ts-clojurec-mode)
         ("\\.edn\\'"  . clojure-ts-mode))
  :init
  (neoemacs--ensure-treesit-grammars 'clojure))

;; --- LSP via eglot ---------------------------------------------------------
;;
;; eglot is built in (`:ensure nil'). It's fully deferred: `eglot-ensure' is
;; autoloaded, so listing it on the language hooks arms LSP without loading
;; eglot at startup -- the package loads the first time one of those modes turns
;; on (i.e. when you open a real source file), never during init. The `:config'
;; (server table + perf tweaks) then runs once, at that first attach.
(use-package eglot
  :ensure nil
  :defer t
  :hook ((astro-ts-mode                 . eglot-ensure)
         (typescript-ts-mode            . eglot-ensure)
         (tsx-ts-mode                   . eglot-ensure)
         (clojure-ts-mode               . eglot-ensure)
         (clojure-ts-clojurescript-mode . eglot-ensure)
         (clojure-ts-clojurec-mode      . eglot-ensure))
  :config
  ;; The Astro language server (`@astrojs/language-server', binary `astro-ls';
  ;; install with `npm i -g @astrojs/language-server'). It needs to be pointed at
  ;; the project's own TypeScript via `tsdk' -- a relative path resolves against
  ;; the project root eglot starts the server in, so the project's
  ;; `node_modules/typescript' is used. TS/TSX files use eglot's built-in
  ;; `typescript-language-server' entry, so only Astro needs registering here.
  (add-to-list 'eglot-server-programs
               '(astro-ts-mode . ("astro-ls" "--stdio"
                                  :initializationOptions
                                  (:typescript (:tsdk "node_modules/typescript/lib")))))
  ;; clojure-lsp drives the clojure-ts-mode family. eglot's built-in server
  ;; table only knows the classic clojure-mode names, so register the tree-sitter
  ;; modes explicitly. clojure-lsp bundles clj-kondo, so linting arrives over
  ;; eglot's flymake alongside completion/nav/rename -- no separate linter
  ;; package. Requires the `clojure-lsp' binary on PATH.
  (add-to-list 'eglot-server-programs
               '((clojure-ts-mode clojure-ts-clojurescript-mode clojure-ts-clojurec-mode)
                 . ("clojure-lsp")))
  ;; Don't log every LSP JSON-RPC message to a buffer -- it's a measurable drag
  ;; on a chatty server and only useful when debugging eglot itself. The setting
  ;; was renamed across eglot versions, so set whichever this Emacs has.
  (when (boundp 'eglot-events-buffer-config)
    (setq eglot-events-buffer-config '(:size 0 :format full)))
  (when (boundp 'eglot-events-buffer-size)
    (setq eglot-events-buffer-size 0)))

;; --- Formatting: apheleia --------------------------------------------------
;;
;; apheleia reformats on save *asynchronously* (it diffs the formatter's output
;; back in, so point/scroll are preserved and the UI never blocks) -- preferable
;; to `eglot-format-buffer' on save for a terminal workflow. Deferred the same
;; way as corfu: the autoloaded `apheleia-global-mode' is armed on
;; `emacs-startup-hook', so the package loads off the critical path.
;;
;; Astro is formatted by Prettier with `prettier-plugin-astro' (the standard
;; Astro formatter); point apheleia's `astro-ts-mode' entry at its prettier
;; formatter. TS/TSX already map to prettier in apheleia's defaults.
(use-package apheleia
  :defer t
  :init
  (add-hook 'emacs-startup-hook #'apheleia-global-mode)
  :config
  (add-to-list 'apheleia-mode-alist '(astro-ts-mode . prettier)))

;;; --- Clojure tooling -------------------------------------------------------
;;
;; The major mode (`clojure-ts-mode') and its LSP attach (clojure-lsp via eglot)
;; are set up above with the other tree-sitter languages. These two add the
;; editing and REPL layers.

;; evil-cleverparens: paredit-style structural editing (slurp/barf, wrap, etc.)
;; expressed through evil motions, so paren editing doesn't fight evil's keys.
;; Pulls in paredit + smartparens as dependencies. Enabled on the Clojure
;; tree-sitter modes (add emacs-lisp-mode / lisp-mode to the hook for those too).
(use-package evil-cleverparens
  :hook ((clojure-ts-mode               . evil-cleverparens-mode)
         (clojure-ts-clojurescript-mode . evil-cleverparens-mode)
         (clojure-ts-clojurec-mode      . evil-cleverparens-mode))
  :init
  (setq evil-cleverparens-use-additional-bindings t))

;; rainbow-delimiters: depth-colored parens/brackets/braces. Hooked on the
;; Lisp-family modes where nesting depth matters most -- the tree-sitter
;; Clojure modes (alongside `evil-cleverparens' structural editing) plus
;; Emacs Lisp. Deferred via `:hook', so it costs nothing until such a buffer
;; is opened.
(use-package rainbow-delimiters
  :hook ((emacs-lisp-mode               . rainbow-delimiters-mode)
         (lisp-interaction-mode         . rainbow-delimiters-mode)
         (clojure-ts-mode               . rainbow-delimiters-mode)
         (clojure-ts-clojurescript-mode . rainbow-delimiters-mode)
         (clojure-ts-clojurec-mode      . rainbow-delimiters-mode)))

;; cider: nREPL-connected REPL, inline eval, debugger, test runner -- the
;; runtime half of Clojure dev, complementary to clojure-lsp's static analysis
;; (they intentionally run together). `:after clojure-ts-mode' keeps cider
;; deferred until the first Clojure file is visited, so it costs nothing at
;; startup; its `C-c C-...' keymaps are live in Clojure buffers from then on
;; (`C-c C-j' jacks in a REPL -- needs `clojure'/`clj' or `lein' on PATH). evil
;; bindings for cider's own buffers come from `evil-collection-init'.
(use-package cider
  :after clojure-ts-mode
  :custom
  (cider-repl-display-help-banner nil)
  (cider-repl-pop-to-buffer-on-connect 'display-only)
  (cider-save-file-on-load t)
  (cider-font-lock-dynamically '(macro core function var)))

;;; --- Environment: direnv ---------------------------------------------------

;; envrc: per-buffer environment from direnv `.envrc' files. Enable the global
;; mode late (on `after-init') so it layers on top of other global modes, as
;; its README requires. Needs the `direnv' executable on PATH.
(use-package envrc
  :hook (after-init . envrc-global-mode)
  :config
  ;; `envrc--export' (used by both first-time load and `envrc-reload') runs
  ;; direnv via a synchronous `call-process' and advertises "C-g to abort".
  ;; That abort relies on Emacs's low-level quit detection, which only fires
  ;; on the raw C-g byte (ASCII 7) in the terminal input stream. With `kkp'
  ;; active the Kitty Keyboard Protocol re-encodes C-g as an escape sequence
  ;; (ESC [ 103;5 u), so the blocking call never sees a quit and C-g cannot
  ;; abort. Tear kkp down for the duration of the direnv run to restore the
  ;; raw C-g byte, then re-enable it. No-op when kkp isn't active (e.g. GUI).
  (defun neoemacs--envrc-export-restore-quit (orig-fn &rest args)
    "Run ORIG-FN with kkp disabled so C-g aborts the direnv `call-process'."
    (if (and (fboundp 'kkp--this-terminal-has-active-kkp-p)
             (kkp--this-terminal-has-active-kkp-p))
        (let ((terminal (kkp--selected-terminal)))
          (unwind-protect
              (progn
                (kkp--terminal-teardown terminal)
                (apply orig-fn args))
            (kkp-enable-in-terminal terminal)))
      (apply orig-fn args)))
  (advice-add 'envrc--export :around #'neoemacs--envrc-export-restore-quit))

;;; --- Server / EDITOR -------------------------------------------------------

;; Run an Emacs server so `emacsclient' can hand work to *this* running Emacs
;; (git commit messages, anything that shells out to $EDITOR from the ghostel
;; terminal, etc.) instead of spawning a nested Emacs.
;;
;; The server name is made unique per Emacs process by appending the PID, so
;; several concurrent Emacs instances each get their own socket rather than
;; colliding on the default "server" name. EDITOR is then pointed at that
;; socket (`emacsclient -s <name>'; emacsclient resolves the bare name against
;; the same `server-socket-dir' the server uses).
;;
;; Deferred to `emacs-startup-hook' so socket creation and the env tweak stay
;; off the critical startup path -- nothing here runs during init.
(use-package server
  :ensure nil
  :defer t
  :init
  (add-hook 'emacs-startup-hook
            (lambda ()
              (require 'server)
              (setq server-name (format "neoemacs-%d" (emacs-pid)))
              (unless (server-running-p server-name)
                (server-start))
              (setenv "EDITOR" (format "emacsclient -s %s" server-name))))
  :config
  ;; Finish/abort keys, bound *buffer-locally* in each emacsclient buffer (via
  ;; `server-switch-hook') so they never leak into ordinary buffers. In
  ;; particular evil's global ZZ (`evil-save-modified-and-close') and ZQ
  ;; (`evil-quit') stay intact everywhere except the client buffer, where they
  ;; map to the client-aware finish/abort instead.
  ;;   finish: C-c C-c (any evil state) / ZZ (normal)
  ;;   abort:  C-c C-k (any evil state) / ZQ (normal)
  ;; The C-c chords go in the buffer's local map so they fire from insert and
  ;; normal alike (evil leaves the C-c prefix to fall through); ZZ/ZQ are
  ;; normal-state-only to match Vim, bound via `evil-local-set-key'.
  (defun neoemacs--server-buffer-keys ()
    "Bind client finish/abort keys locally in an emacsclient buffer."
    (local-set-key (kbd "C-c C-c") #'server-edit)
    (local-set-key (kbd "C-c C-k") #'server-edit-abort)
    (when (fboundp 'evil-local-set-key)
      (evil-local-set-key 'normal (kbd "ZZ") #'server-edit)
      (evil-local-set-key 'normal (kbd "ZQ") #'server-edit-abort)))
  (add-hook 'server-switch-hook #'neoemacs--server-buffer-keys))

;;; --- Zellij tab name -------------------------------------------------------

;; Keep the focused zellij tab named after the current buffer's location, as
;; "<parent>/<dir>". Precedence:
;;   1. inside a projectile project -> the project root,
;;   2. else a dired buffer        -> the listed directory,
;;   3. else a file-visiting buffer -> the file's directory,
;;   4. otherwise leave the tab name unchanged.
;; Updated on buffer/window switch, only when running inside zellij ($ZELLIJ),
;; and deduped so we shell out only when the computed name actually changes.
(defun neoemacs--parent-and-dir (dir)
  "Return \"<parent>/<dir>\" for absolute DIR (just the dir name if no parent)."
  (let* ((dir (directory-file-name (expand-file-name dir)))
         (name (file-name-nondirectory dir))
         (parent (file-name-nondirectory
                  (directory-file-name (file-name-directory dir)))))
    (if (string-empty-p parent) name (concat parent "/" name))))

(defun neoemacs--zellij-tab-name ()
  "Compute the zellij tab name for the current buffer, or nil to leave it."
  (cond
   ((and (fboundp 'projectile-project-root) (projectile-project-root))
    (neoemacs--parent-and-dir (projectile-project-root)))
   ((derived-mode-p 'dired-mode)
    (neoemacs--parent-and-dir default-directory))
   (buffer-file-name
    (neoemacs--parent-and-dir (file-name-directory buffer-file-name)))
   (t nil)))

(defun neoemacs--zellij-update-tab-name (&rest _)
  "Rename the focused zellij tab to reflect the selected window's buffer.
The last name is remembered per-frame (each Emacs frame maps to a zellij
pane/tab) so separate frames don't clobber each other's dedup state."
  (when (getenv "ZELLIJ")
    (with-current-buffer (window-buffer (selected-window))
      (let ((name (neoemacs--zellij-tab-name))
            (last (frame-parameter nil 'neoemacs--zellij-last-tab-name)))
        (when (and name (not (equal name last)))
          (set-frame-parameter nil 'neoemacs--zellij-last-tab-name name)
          ;; Run async and discard output so buffer switches never block on the
          ;; zellij subprocess.
          (when (executable-find "zellij")
            (start-process "zellij-rename-tab" nil
                           "zellij" "action" "rename-tab" name)))))))

;; Trigger on the full range of context changes: window focus
;; (`window-selection-change-functions'), a window's buffer changing
;; (`window-buffer-change-functions', e.g. `switch-to-buffer'), and dired/
;; dirvish directory navigation -- the latter changes the buffer/directory
;; in place without changing the selected window, so the window hooks miss
;; it. The per-frame dedup makes redundant firings cheap (no zellij call).
(dolist (hook '(window-selection-change-functions
                window-buffer-change-functions
                dired-after-readin-hook
                dirvish-setup-hook))
  (add-hook hook #'neoemacs--zellij-update-tab-name))

(provide 'init)
;;; init.el ends here
