;;; init.el --- Main initialization -*- lexical-binding: t; -*-

;;; Commentary:
;; Main configuration entry point.  Bootstraps the package system, then
;; configures each package with one `use-package' form.  See CLAUDE.md for
;; the architecture overview (keybinding layers, completion stack, terminal
;; integration).

;;; Code:

;;; --- Package system --------------------------------------------------------

;; `package-enable-at-startup' is disabled in early-init.el, so initialize
;; explicitly here.
(require 'package)
(setq package-archives
      '(("gnu"   . "https://elpa.gnu.org/packages/")
        ("melpa" . "https://melpa.org/packages/")))
(package-initialize)

;; Ensure use-package is available.
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t)

;;; --- Core editor settings --------------------------------------------------

;; Disable backup files (the `filename~' clutter).
(setq make-backup-files nil)

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
      scroll-conservatively 101
      scroll-step 1
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
  (advice-add 'recentf-save-list :before #'neoemacs--recentf-merge-on-save))

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

;;; --- Window management helpers ---------------------------------------------

(defun neoemacs/vsplit-window-follow ()
  "Split the window horizontally and move focus into the new split."
  (interactive)
  (evil-window-vsplit)
  (evil-window-right 1))

(defun neoemacs/vsplit-ghostel ()
  "Open a vertical split, move focus into it, and launch ghostel there."
  (interactive)
  (neoemacs/vsplit-window-follow)
  (evil-buffer-new)
  ;; `evil-buffer-new' shows the empty "*new*" buffer in the window via
  ;; `set-window-buffer' without making it current, so grab it from the window.
  (let ((placeholder (window-buffer))
        ;; Non-numeric prefix arg => always create a fresh ghostel buffer in the
        ;; new split, rather than switching to an existing terminal.
        (ghostel-buffer (ghostel '(4))))
    ;; ghostel swaps in its own buffer; drop the empty placeholder.
    (when (and (buffer-live-p placeholder)
               (not (eq placeholder ghostel-buffer)))
      (kill-buffer placeholder))))

(defun neoemacs/describe-symbol-at-point ()
  "Describe the symbol under point without prompting in the minibuffer."
  (interactive)
  (let ((sym (symbol-at-point)))
    (if sym
        (progn
          (describe-symbol sym)
          (select-window (get-buffer-window "*Help*")))
      (user-error "No symbol at point"))))

;;; --- Keybindings -----------------------------------------------------------

;; General: convenient keybinding definitions, used here for a SPC leader.
(use-package general
  :after evil
  :config
  (general-create-definer neoemacs/leader
    :states '(normal visual motion)
    :keymaps 'override
    :prefix "SPC"
    :global-prefix "C-SPC")
  (neoemacs/leader
    "SPC" '(projectile-find-file :which-key "find file in project")
    ","  '(consult-buffer :which-key "switch buffer")
    "f"  '(:ignore t :which-key "files")
    "ff" '(find-file :which-key "find file")
    "fr" '(consult-recent-file :which-key "recent file")
    "b"  '(:ignore t :which-key "buffers")
    "bb" '(consult-buffer :which-key "switch buffer")
    "bd" '(kill-current-buffer :which-key "kill buffer")
    "bn" '(next-buffer :which-key "next buffer")
    "bp" '(previous-buffer :which-key "previous buffer")
    "p"  '(:ignore t :which-key "project")
    "pp" '(consult-projectile :which-key "switch project")
    "pf" '(projectile-find-file :which-key "find file in project")
    "pb" '(projectile-switch-to-buffer :which-key "project buffer")
    "g"  '(:ignore t :which-key "git")
    "gg" '(magit-status :which-key "status")
    "gb" '(magit-blame :which-key "blame")
    "gl" '(magit-log-buffer-file :which-key "log (this file)")
    "h"  '(help-command :which-key "help"))
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
   "K" 'neoemacs/describe-symbol-at-point))

;; expand-region: grow/shrink the selection by semantic units. In visual
;; state `v' expands the region and `V' contracts it.
(use-package expand-region
  :after (evil general)
  :config
  (general-define-key
   :states 'visual
   "v" 'er/expand-region
   "V" 'er/contract-region))

;; which-key: popup showing available keybindings.
(use-package which-key
  :ensure nil
  :config
  (setq which-key-idle-delay 0.5)
  (which-key-mode 1))

;;; --- Completion stack ------------------------------------------------------

;; Vertico: vertical completion UI in the minibuffer.
(use-package vertico
  :init
  (vertico-mode 1))

;; Orderless: space-separated, order-independent completion matching.
(use-package orderless
  :init
  (setq completion-styles '(orderless basic)
        completion-category-overrides '((file (styles partial-completion)))))

;; Marginalia: rich annotations in the minibuffer margin.
(use-package marginalia
  :init
  (marginalia-mode 1))

;; Consult: enhanced search and navigation commands.
(use-package consult
  :bind (("C-s"   . consult-line)
         ("C-x b" . consult-buffer)
         ("M-y"   . consult-yank-pop)
         ("M-g g" . consult-goto-line)
         ("M-g i" . consult-imenu)))

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

;; Ediff: skip the "Quit this Ediff session? (y or n)" confirmation. `ediff-quit'
;; hard-codes a `y-or-n-p' before tearing down; locally stub it to always answer
;; yes for the duration of the call so `q' quits immediately.
(use-package ediff
  :ensure nil
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

;;; --- Dired / file management -----------------------------------------------

;; Dirvish: a polished dired replacement with previews and icons.
(use-package dirvish
  :after (nerd-icons general)
  :init
  (dirvish-override-dired-mode 1)
  :custom
  (dirvish-attributes '(nerd-icons file-size git-msg subtree-state vc-state))
  ;; `-A' ("almost all") lists dotfiles but omits the `.' and `..' entries;
  ;; `-l' keeps the long format. (Plain `-a' is what shows `.' and `..'.)
  (dired-listing-switches "-Al")
  ;; Show a real block cursor in dired/dirvish buffers. By default dirvish
  ;; hides it (`cursor-type' nil + a zero-width `evil-normal-state-cursor')
  ;; and relies on the hl-line highlight; keeping it visible makes dirvish
  ;; use a `(box . 4)' block, which etcc renders as a terminal block cursor.
  (dirvish-hide-cursor nil)
  :bind ("C-c f" . dirvish)
  :config
  ;; Vim-style navigation: h goes up a directory, l enters the file/dir.
  (general-define-key
   :states 'normal
   :keymaps 'dired-mode-map
   "h" 'dired-up-directory
   "l" 'dired-find-file
   "TAB" 'dirvish-subtree-toggle))

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
  :bind ("s-t" . neoemacs/vsplit-ghostel))

;; evil-ghostel: keeps the terminal cursor in sync with Emacs point across
;; evil state transitions, so normal-state hjkl navigation works.
(use-package evil-ghostel
  :after (ghostel evil)
  :hook (ghostel-mode . evil-ghostel-mode))

;;; --- Project navigation ----------------------------------------------------

;; Projectile: project interaction and navigation.
(use-package projectile
  :init
  (projectile-mode 1)
  :bind-keymap ("C-c p" . projectile-command-map))

;; consult-projectile: consult-powered project navigation.
;; Reached via the leader at `SPC p p' (see the general config above).
(use-package consult-projectile
  :after (consult projectile))

;;; --- Languages -------------------------------------------------------------

;; markdown-mode: major mode for editing Markdown. `gfm-mode' is used for
;; README.md and other GitHub-Flavored Markdown files.
(use-package markdown-mode
  :mode (("README\\.md\\'" . gfm-mode)
         ("\\.md\\'"       . markdown-mode)
         ("\\.markdown\\'" . markdown-mode)))

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
          ;; Destination 0: run async and discard output so buffer switches
          ;; never block on the zellij subprocess.
          (call-process "zellij" nil 0 nil "action" "rename-tab" name))))))

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
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages nil)
 '(safe-local-variable-values
   '((cider-clojure-cli-aliases . ":dev")
     (cider-preferred-build-tool . clojure-cli))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
