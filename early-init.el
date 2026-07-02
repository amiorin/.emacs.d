;;; early-init.el --- Early initialization -*- lexical-binding: t; -*-

;;; Commentary:
;; Loaded before init.el and before the package system and UI are
;; initialized.  Used for startup performance tuning and disabling the
;; built-in package manager and default UI elements.

;;; Code:

;; Defer garbage collection during startup for faster init, then restore
;; a sane threshold afterwards.  Depth 99 so the restore runs *last* on
;; `emacs-startup-hook': init.el defers several package loads to this same
;; hook (corfu, diff-hl, evil-collection, ...), and those loads should still
;; happen with GC off.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024)
                  gc-cons-percentage 0.1))
          99)

;; Don't let `package.el' load packages before init.el runs; defer to a
;; manual `package-initialize' or another package manager (e.g. straight,
;; elpaca).
(setq package-enable-at-startup nil)

;; Resizing the frame to match font dimensions during startup is costly.
(setq frame-inhibit-implied-resize t)

;; Avoid expensive file-handler regexp matching while loading the init files.
;; Depth 99 for the same reason as the GC restore above: the package loads
;; init.el defers to this hook still benefit from the empty alist.
(defvar neoemacs--file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil)

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist neoemacs--file-name-handler-alist))
          99)

;; Hide the UI until the doom-one theme is in place.  Emacs paints the
;; default (unthemed) faces first, then repaints once `load-theme' runs
;; partway through init.el -- the user perceives this as the theme
;; "appearing" with a delay.  Suppress all redisplay (and stray startup
;; messages) for the whole init sequence and paint exactly once at the
;; end, so the first frame the user ever sees is already themed.  This is
;; set first, before any of the chrome tweaks below, so nothing they do
;; can paint either.
;;
;; `emacs-startup-hook' runs even when init.el signals an error (Emacs
;; catches it), so redisplay is always restored -- the screen can't get
;; stuck blank.
;;
;; Depth -99 so this runs *first* on `emacs-startup-hook'.  Without it,
;; the package loads init.el defers to this hook (corfu, diff-hl,
;; evil-collection, ...) would run before the paint -- `add-hook' prepends,
;; so hooks added later in init.el land ahead of this one -- and the user
;; would stare at a blank screen while they load.  Painting first makes the
;; deferred loads invisible: the themed frame is already up.
(setq inhibit-redisplay t
      inhibit-message t)
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq inhibit-redisplay nil
                  inhibit-message nil)
            (redisplay))
          -99)

;; Disable UI chrome.  In `-nw' the terminal frame is created in C before
;; early-init.el is loaded, so it already exists with a menu-bar line --
;; setting `default-frame-alist' (consulted only at frame creation) can't
;; fix it.  Calling the mode functions does: each runs
;; `modify-all-frames-parameters', which drops the bar on the live frame
;; *and* updates `default-frame-alist' for future frames.
;; (`inhibit-redisplay' above keeps this from flashing.)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

;; Suppress the GUI startup screen and reduce early redisplay work.
(setq inhibit-startup-screen t
      inhibit-splash-screen t
      use-file-dialog nil
      use-dialog-box nil)

;; Quiet the byte-compiler / native-comp during startup.
(setq native-comp-async-report-warnings-errors 'silent
      load-prefer-newer t)

(provide 'early-init)
;;; early-init.el ends here
