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
      (should (eq (plist-get seen-opts :category) 'multi-category))
      (should (equal acted "https://a.example"))
      (should (= (point) 1)))))

;;; Preview highlight ranges: one per row the link occupies.

(ert-deftest links-fragments-single-row ()
  (with-temp-buffer
    (insert "see https://a.example. next\n")
    (should (equal (neoemacs--link-fragments 5 "https://a.example")
                   '((5 . 22))))))

(ert-deftest links-fragments-soft-wrap ()
  (with-temp-buffer
    (insert "x https://example." (propertize "\n" 'ghostel-wrap t)
            "com/aaaa/bbbb tail\n")
    (should (equal (neoemacs--link-fragments 3 "https://example.com/aaaa/bbbb")
                   '((3 . 19) (20 . 33))))))

(ert-deftest links-fragments-hard-wrap-border ()
  (with-temp-buffer
    (insert "  https://example.com/abcdefgh\n"
            "  │ ijkl/mnop and more words\n")
    (should (equal (neoemacs--link-fragments 3 "https://example.com/abcdefghijkl/mnop")
                   '((3 . 31) (36 . 45))))))

(ert-deftest links-fragments-hard-wrap-trailing-border ()
  (with-temp-buffer
    (insert "│ https://example.com/abcdefgh │\n"
            "│ ijkl/mnop.                   │\n")
    (should (equal (neoemacs--link-fragments 3 "https://example.com/abcdefghijkl/mnop")
                   '((3 . 31) (36 . 45))))))

(ert-deftest links-fragments-osc8-two-rows ()
  (with-temp-buffer
    (insert "click " (links-test--ghostel-span "here" "https://real.example/t" "osc-2")
            "\n" (links-test--ghostel-span "too" "https://real.example/t" "osc-2")
            " end\n")
    (should (equal (neoemacs--link-fragments 7 "https://real.example/t")
                   '((7 . 11) (12 . 15))))))

(ert-deftest links-preview-highlights-every-row ()
  ;; The command's preview puts one match overlay on each row of a
  ;; hard-wrapped link.
  (links-test--with 30
    (insert "  https://example.com/abcdefgh\n"
            "  │ ijkl/mnop and more words\n")
    (goto-char (point-max))
    (let (ranges)
      (cl-letf (((symbol-function 'consult--read)
                 (lambda (_cands &rest opts)
                   (let ((state (plist-get opts :state)))
                     (funcall state 'setup nil)
                     (funcall state 'preview "https://example.com/abcdefghijkl/mnop")
                     (setq ranges
                           (sort (mapcar (lambda (ov)
                                           (cons (overlay-start ov) (overlay-end ov)))
                                         (seq-filter
                                          (lambda (ov)
                                            (eq (overlay-get ov 'category)
                                                'consult-preview-match-overlay))
                                          (overlays-in (point-min) (point-max))))
                                 (lambda (a b) (< (car a) (car b)))))
                     (funcall state 'preview nil)
                     (funcall state 'exit nil))
                   "https://example.com/abcdefghijkl/mnop"))
                ((symbol-function 'neoemacs--link-act) #'ignore))
        (neoemacs/consult-buffer-links))
      (should (equal ranges '((3 . 31) (36 . 45)))))))

;;; Local file paths.

(defmacro links-test--with-files (files &rest body)
  "Run BODY in a temp buffer whose `default-directory' holds FILES.
Binds `dir' to that directory (with a trailing slash)."
  (declare (indent 1))
  `(let* ((dir (file-name-as-directory (make-temp-file "links-test" t))))
     (unwind-protect
         (progn
           (dolist (f ,files)
             (make-directory (file-name-directory (expand-file-name f dir)) t)
             (with-temp-file (expand-file-name f dir) (insert "l1\nl2\nline three\n")))
           (with-temp-buffer
             (setq default-directory dir)
             (let ((neoemacs--link-wrap-width-function (lambda () nil)))
               ,@body)))
       (delete-directory dir t))))

(defun links-test--refs ()
  (mapcar (lambda (r) (list (file-relative-name (nth 0 r) default-directory) (nth 1 r)))
          (neoemacs--buffer-file-refs)))

(ert-deftest files-relative-absolute-and-tails ()
  (links-test--with-files '("src/a.el" "src/b.el")
    (insert "error at src/a.el:12:3 here\n"
            "see " dir "src/b.el.\n")
    (should (equal (links-test--refs) '(("src/b.el" "") ("src/a.el" ":12:3"))))))

(ert-deftest files-home-relative ()
  (links-test--with-files '("notes/x.md")
    (let ((process-environment (cons (concat "HOME=" dir) process-environment)))
      (insert "open ~/notes/x.md now\n")
      (should (equal (links-test--refs) '(("notes/x.md" "")))))))

(ert-deftest files-bare-name-needs-line ()
  (links-test--with-files '("init.el")
    (insert "init.el alone, then init.el:7 with a line\n")
    (should (equal (links-test--refs) '(("init.el" ":7"))))))

(ert-deftest files-missing-skipped ()
  (links-test--with-files '("real/a.txt")
    (insert "real/a.txt and fake/b.txt and nope.el:3\n")
    (should (equal (links-test--refs) '(("real/a.txt" ""))))))

(ert-deftest files-not-inside-urls ()
  (links-test--with-files '()
    ;; /tmp exists, but here it's a URL's path.
    (insert "https://localhost/tmp and http://x.example:8080/tmp\n")
    (should-not (neoemacs--buffer-file-refs))))

(ert-deftest files-directory-candidate ()
  (links-test--with-files '("sub/f.txt")
    ;; The sweep skips directories (shell prompts show one on every line)...
    (insert "look in ./sub please\n")
    (should-not (neoemacs--buffer-file-refs))
    ;; ...but a ghostel-marked one is displayed with a trailing slash.
    (let ((abs (expand-file-name "sub" dir)))
      (should (equal (neoemacs--file-ref-candidate abs "")
                     (concat (abbreviate-file-name abs) "/")))
      (should (equal (get-text-property 0 'multi-category
                                        (neoemacs--file-ref-candidate abs ""))
                     (cons 'file abs))))))

(ert-deftest files-ghostel-fileref-span ()
  (links-test--with-files '("deep/target.el")
    (let ((abs (expand-file-name "deep/target.el" dir)))
      (insert "at " (links-test--ghostel-span "target.el:4" (concat "fileref:" abs ":4")
                                           '(ghostel-detected . 9))
              " ok\n")
      ;; The regex alone would miss it (resolves against the wrong dir).
      (should (equal (neoemacs--buffer-file-refs) `((,abs ":4" 4 "target.el:4")))))))

(ert-deftest files-hard-wrap-rejoined-when-exists ()
  (links-test--with-files '("abcdefgh/ijklmnop.el")
    (let ((neoemacs--link-wrap-width-function (lambda () 12)))
      (insert "abcdefgh/ijk\n"
              "  lmnop.el is the file\n")
      (should (equal (links-test--refs) '(("abcdefgh/ijklmnop.el" "")))))))

(ert-deftest files-hard-wrap-not-joined-when-missing ()
  (links-test--with-files '("abcdefgh/ijk")
    (let ((neoemacs--link-wrap-width-function (lambda () 12)))
      (insert "abcdefgh/ijk\n"
              "  zzz words\n")
      (should (equal (links-test--refs) '(("abcdefgh/ijk" "")))))))

(ert-deftest files-dedupe-newest-first ()
  (links-test--with-files '("a/x.el" "a/y.el")
    (insert "a/x.el\na/y.el\na/x.el\na/x.el:2\n")
    (should (equal (mapcar (lambda (r) (list (file-relative-name (car r) dir) (nth 1 r) (nth 2 r)))
                           (neoemacs--buffer-file-refs))
                   '(("a/x.el" ":2" 22) ("a/x.el" "" 15) ("a/y.el" "" 8))))))

(ert-deftest files-and-urls-mixed-order ()
  (links-test--with-files '("a/x.el")
    (insert "https://one.example\na/x.el:3\nhttps://two.example\n")
    (should (equal (mapcar (lambda (e) (substring-no-properties (car e)))
                           (neoemacs--buffer-link-entries))
                   (list "https://two.example"
                         (concat (abbreviate-file-name (expand-file-name "a/x.el" dir)) ":3")
                         "https://one.example")))
    (should (equal (get-text-property 0 'multi-category
                                      (car (car (neoemacs--buffer-link-entries))))
                   '(url . "https://two.example")))))

(ert-deftest files-act-opens-at-line-and-column ()
  (links-test--with-files '("a/x.el")
    (let ((abs (expand-file-name "a/x.el" dir)) other)
      (cl-letf (((symbol-function 'find-file-other-window)
                 (lambda (f) (setq other t) (set-buffer (find-file-noselect f)))))
        (save-window-excursion
          (neoemacs--file-ref-act abs ":3:6")
          (should (equal buffer-file-name abs))
          (should (= (line-number-at-pos) 3))
          (should (= (current-column) 5))
          (kill-buffer))
        (should-not other)))))

(ert-deftest files-act-other-window-from-terminal ()
  (links-test--with-files '("a/x.el")
    (let ((abs (expand-file-name "a/x.el" dir)) opened)
      (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t))
                ((symbol-function 'find-file-other-window) (lambda (f) (setq opened f)))
                ((symbol-function 'find-file) (lambda (_) (error "Same window"))))
        (neoemacs--file-ref-act abs "")
        (should (equal opened abs))))))

(ert-deftest files-command-end-to-end ()
  (links-test--with-files '("a/x.el")
    (insert "https://u.example then a/x.el:2 here\n")
    (goto-char (point-min))
    (let ((file (concat (abbreviate-file-name (expand-file-name "a/x.el" dir)) ":2"))
          acted)
      (cl-letf (((symbol-function 'consult--read)
                 (lambda (cands &rest opts)
                   (let ((state (plist-get opts :state)))
                     (funcall state 'setup nil)
                     (funcall state 'preview file)
                     (should (= (point) 24))
                     (funcall state 'preview nil)
                     (funcall state 'exit nil))
                   (should (member file cands))
                   file))
                ((symbol-function 'neoemacs--file-ref-act)
                 (lambda (abs tail) (setq acted (list abs tail)))))
        (neoemacs/consult-buffer-links))
      (should (equal acted (list (expand-file-name "a/x.el" dir) ":2"))))))
