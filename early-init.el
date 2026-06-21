;;; early-init.el --- Early initialization -*- lexical-binding: t; -*-

;;; Commentary:
;; Loaded before init.el and before the package system and UI are
;; initialized.  Used for startup performance tuning and disabling the
;; built-in package manager and default UI elements.

;;; Code:

;; Defer garbage collection during startup for faster init, then restore
;; a sane threshold afterwards.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024)
                  gc-cons-percentage 0.1)))

;; Don't let `package.el' load packages before init.el runs; defer to a
;; manual `package-initialize' or another package manager (e.g. straight,
;; elpaca).
(setq package-enable-at-startup nil)

;; Resizing the frame to match font dimensions during startup is costly.
(setq frame-inhibit-implied-resize t)

;; Avoid expensive file-handler regexp matching while loading the init files.
(defvar neoemacs--file-name-handler-alist file-name-handler-alist)
(setq file-name-handler-alist nil)

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist neoemacs--file-name-handler-alist)))

;; Disable UI chrome as early as possible to prevent a momentary flash and
;; the cost of initializing then removing these elements.
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
(setq menu-bar-mode nil
      tool-bar-mode nil
      scroll-bar-mode nil)

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
