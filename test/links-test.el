;;; links-test.el --- tests for neoemacs/consult-buffer-links -*- lexical-binding: t; -*-
;; Run: emacs --batch --init-directory=$HOME/.config/neoemacs -l early-init.el \
;;        -l init.el -l test/links-test.el -f ert-run-tests-batch-and-exit </dev/null
(require 'ert)
(require 'cl-lib)
(require 'ghostel-links)
;; Load consult before stubbing its internals (the command `require's it).
(require 'consult)
;; early-init.el silences messages until `emacs-startup-hook', which batch skips.
(setq inhibit-message nil inhibit-redisplay nil)

(defmacro links-test--with (width &rest body)
  (declare (indent 1))
  `(with-temp-buffer
     (let ((neoemacs--link-wrap-width-function (lambda () ,width)))
       ,@body)))

(defun links-test--ghostel-span (text uri id)
  (propertize text 'help-echo uri 'keymap ghostel-link-map 'ghostel-link-id id))

(ert-deftest links-soft-wrap ()
  (links-test--with 20
    (let ((url "https://example.com/aaaa/bbbb"))
      (insert "x " (links-test--ghostel-span "https://example." url '(ghostel-detected . 1))
              (propertize "\n" 'ghostel-wrap t)
              (links-test--ghostel-span "com/aaaa/bbbb" url '(ghostel-detected . 1))
              " tail\n")
      (should (equal (neoemacs--buffer-links) `((,url . 3)))))))

(ert-deftest links-soft-wrap-regex-only ()
  (links-test--with nil
    (insert "https://example." (propertize "\n" 'ghostel-wrap t) "com/x more\n")
    (should (equal (mapcar #'car (neoemacs--buffer-links)) '("https://example.com/x")))))

(ert-deftest links-hard-wrap-border ()
  ;; Width 30: first row is full (URL ends at col 30), next row "  │ " prefix.
  (links-test--with 30
    (insert "  https://example.com/abcdefgh\n"
            "  │ ijkl/mnop and more words\n")
    (should (equal (mapcar #'car (neoemacs--buffer-links))
                   '("https://example.com/abcdefghijkl/mnop")))))

(ert-deftest links-hard-wrap-trailing-border ()
  ;; No width known; the right border marks the edge.
  (links-test--with nil
    (insert "│ https://example.com/abcdefgh │\n"
            "│ ijkl/mnop.                   │\n")
    (should (equal (mapcar #'car (neoemacs--buffer-links))
                   '("https://example.com/abcdefghijkl/mnop")))))

(ert-deftest links-hard-wrap-three-lines ()
  (links-test--with 20
    (insert "https://example.com/\n"
            "    aaaaaaaaaaaaaaaa\n"
            "    bbbb?q=1\n"
            "next\n")
    (should (equal (mapcar #'car (neoemacs--buffer-links))
                   '("https://example.com/aaaaaaaaaaaaaaaabbbb?q=1")))))

(ert-deftest links-hard-wrap-ghostel-detected ()
  (links-test--with 30
    (insert "  " (links-test--ghostel-span "https://example.com/abcdefgh"
                                         "https://example.com/abcdefgh"
                                         '(ghostel-detected . 7))
            "\n  ijkl\n")
    (should (equal (mapcar #'car (neoemacs--buffer-links))
                   '("https://example.com/abcdefghijkl")))))

(ert-deftest links-short-line-not-joined ()
  (links-test--with 80
    (insert "see https://example.com/x\nwords here\n")
    (should (equal (mapcar #'car (neoemacs--buffer-links))
                   '("https://example.com/x")))))

(ert-deftest links-osc8-real-target ()
  (links-test--with 10
    (insert "click " (links-test--ghostel-span "here" "https://real.example/target" "osc-1")
            "\n")
    (should (equal (neoemacs--buffer-links) '(("https://real.example/target" . 7))))))

(ert-deftest links-osc8-wins-and-not-joined ()
  (links-test--with 30
    (insert (links-test--ghostel-span "https://short.example/abcdefgh"
                                      "https://long.example/real" 42)
            "\nzzzz\n")
    (should (equal (mapcar #'car (neoemacs--buffer-links))
                   '("https://long.example/real")))))

(ert-deftest links-fileref-and-other-schemes-skipped ()
  (links-test--with nil
    (insert (links-test--ghostel-span "foo.el:3" "fileref:foo.el:3" "a") " "
            (links-test--ghostel-span "mail" "mailto:x@y" "b") "\n")
    (should-not (neoemacs--buffer-links))))

(ert-deftest links-trim-and-parens ()
  (links-test--with nil
    (insert "See https://a.example/x.\n"
            "(https://b.example/y), and https://en.wikipedia.org/wiki/Foo_(bar)!\n"
            "[t](https://c.example/z) \"https://d.example/q\" `https://e.example/r`\n")
    (should (equal (sort (mapcar #'car (neoemacs--buffer-links)) #'string<)
                   '("https://a.example/x" "https://b.example/y" "https://c.example/z"
                     "https://d.example/q" "https://e.example/r"
                     "https://en.wikipedia.org/wiki/Foo_(bar)")))))

(ert-deftest links-dedupe-newest-first ()
  (links-test--with nil
    (insert "https://a.example\nhttps://b.example\nhttps://a.example\n")
    (should (equal (neoemacs--buffer-links)
                   '(("https://a.example" . 37) ("https://b.example" . 19))))))

(ert-deftest links-no-links-user-error ()
  (with-temp-buffer
    (insert "nothing here\n")
    (should-error (neoemacs/consult-buffer-links) :type 'user-error)))

(ert-deftest links-act-ssh ()
  (let ((kill-ring nil) called)
    (cl-letf (((symbol-function 'neoemacs--remote-session-p) (lambda () t))
              ((symbol-function 'neoemacs--start-gui-process)
               (lambda (&rest args) (setq called args))))
      (neoemacs--link-act "https://x.example")
      (should (equal (car kill-ring) "https://x.example"))
      (should-not called))))

(ert-deftest links-act-ssh-env ()
  (let ((process-environment (cons "SSH_TTY=/dev/pts/1" process-environment)))
    (should (neoemacs--remote-session-p)))
  (let ((process-environment
         (seq-remove (lambda (e) (string-match-p "\\`SSH_\\(TTY\\|CONNECTION\\)=" e))
                     process-environment)))
    (should-not (neoemacs--remote-session-p))))

(ert-deftest links-act-local ()
  (let ((kill-ring nil) called)
    (cl-letf (((symbol-function 'neoemacs--remote-session-p) (lambda () nil))
              ((symbol-function 'neoemacs--start-gui-process)
               (lambda (&rest args) (setq called args))))
      (neoemacs--link-act "https://x.example")
      (should (equal called '("open-url" "open" "https://x.example")))
      (should-not kill-ring))))

(ert-deftest links-command-end-to-end ()
  ;; Drive the command with consult--read stubbed: check candidates, options,
  ;; and that the state preview moves point and restores it.
  (with-temp-buffer
    (insert "one https://a.example\ntwo https://b.example\n")
    (goto-char (point-min))
    (let (seen-cands seen-opts acted)
      (cl-letf (((symbol-function 'consult--read)
                 (lambda (cands &rest opts)
                   (setq seen-cands cands seen-opts opts)
                   (let ((state (plist-get opts :state)))
                     (funcall state 'setup nil)
                     (funcall state 'preview "https://a.example")
                     (should (= (point) 5))
                     (funcall state 'preview nil)
                     (should (= (point) 1))
                     (funcall state 'exit nil))
                   "https://a.example"))
                ((symbol-function 'neoemacs--link-act) (lambda (u) (setq acted u))))
        (neoemacs/consult-buffer-links))
      (should (equal seen-cands '("https://b.example" "https://a.example")))
      (should (eq (plist-get seen-opts :category) 'url))
      (should (equal acted "https://a.example"))
      (should (= (point) 1)))))
