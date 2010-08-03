;;; clojure-refactoring-mode.el --- Minor mode for basic clojure
;;; refactoring

;; Copyright (C) 2009, Tom Crayford
;; Author: Tom Crayford <tcrayford@googlemail.com>
;; Version: 0.1
;; Keywords: languages, lisp

;; This file is not part of GNU Emacs

;; Commentary
;; Note this mode simply does simple text substitution at the moment.

;;; License:

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Code:

(require 'thingatpt)
(defvar clojure-refactoring-mode-hook '()
  "Hooks to be run when loading clojure refactoring mode")

(defun clojure-refactoring-eval-sync (string)
  (slime-eval `(swank:eval-and-grab-output ,string)))

(defun escape-string-literals (string)
  (substring-no-properties
   (with-temp-buffer
     (insert (substring-no-properties string))
     (beginning-of-buffer)
     (buffer-string)
     (while (search-forward-regexp  "\\\\*\042" nil t)
       (replace-match "\"")
       (backward-char)
       (insert "\\")
       (forward-char))
     (buffer-string))))

(setq clojure-refactoring-refactorings-list
      (list "extract-fn" "thread-last" "extract-global" "thread-first" "unthread" "extract-local" "destructure-map" "rename"))

(defun clojure-refactoring-ido ()
  (interactive)
  (let ((refactoring (ido-completing-read "Refactoring: " clojure-refactoring-refactorings-list nil t)))
    (funcall (intern (concat "clojure-refactoring-" refactoring)))))


(defun get-sexp ()
  (if mark-active
      (escape-string-literals (delete-and-extract-region (mark) (point)))
    (let (out (escape-string-literals
               (format "%s" (sexp-at-point))))
      (forward-kill-sexp)
      out)))

(defun set-clojure-refactoring-temp (str)
  (setq clojure-refactoring-temp
        (car (cdr (clojure-refactoring-eval-sync str)))))

(defun forward-kill-sexp ()
  (interactive)
  (forward-sexp)
  (backward-kill-sexp))

;; FIXME: this will break if there's an escaped \" in any of the code
;; it reads.
;; FIXME: breaks if a newline is in a string
(defun clojure-refactoring-extract-fn ()
  "Extracts a function."
  (interactive)
  (let ((fn-name  (read-from-minibuffer "Function name: "))
        (defn (escape-string-literals (slime-defun-at-point)))
        (body (get-sexp)))
    (save-excursion
      (set-clojure-refactoring-temp
       (concat "(require 'clojure-refactoring.extract-method) (ns clojure-refactoring.extract-method) (extract-method \""
               defn "\"  \"" body "\"  \"" fn-name "\")"))
      (beginning-of-defun)
      (forward-kill-sexp)
      (insert (read clojure-refactoring-temp)))))

(defun clojure-refactoring-thread-expr (str)
  (let ((body (get-sexp)))
    (save-excursion
      (set-clojure-refactoring-temp
       (concat "(require 'clojure-refactoring.thread-expression) (ns clojure-refactoring.thread-expression) (thread-" str " \"" body"\")"))
      (cleanup-buffer)
      (insert (read clojure-refactoring-temp)))))

(defun clojure-refactoring-thread-last ()
  (interactive)
  (clojure-refactoring-thread-expr "last"))

(defun clojure-refactoring-thread-first ()
  (interactive)
  (clojure-refactoring-thread-expr "first"))

(defun clojure-refactoring-unthread ()
  (interactive)
  (clojure-refactoring-thread-expr "unthread"))

(defun clojure-refactoring-rename ()
  (interactive)
  (let ((old-name (symbol-at-point))
        (new-name (read-from-minibuffer "New name: ")))
    (beginning-of-defun)
    (mark-sexp)
    (let ((body (get-sexp)))
      (message (format "new %s" new-name))
      (message (format "old %s" old-name))
      (message (format "body %s" body))
      (set-clojure-refactoring-temp
       (format "(require 'clojure-refactoring.rename) (clojure-refactoring.rename/rename \"%s\" \"%s\" \"%s\")"
               body old-name new-name))
       (insert (read clojure-refactoring-temp)))))

(defun clojure-refactoring-extract-global ()
  (let ((var-name (read-from-minibuffer "Variable name: "))
        (body (delete-and-extract-region (mark t) (point))))
    (save-excursion
      (beginning-of-buffer)
      (forward-sexp)
      (paredit-mode 0)
      (insert "(def " var-name body ")")
      (reindent-then-newline-and-indent))
    (insert var-name)))


(defun clojure-refactoring-extract-local ()
  (let ((var-name (read-from-minibuffer "Variable name: "))
        (defn (escape-string-literals (slime-defun-at-point)))
        (body (get-sexp)))
    (save-excursion
      (set-clojure-refactoring-temp
       (concat "(require 'clojure-refactoring.local-binding) (ns clojure-refactoring.local-binding) (local-wrap \"" defn "\" \"" body "\" \"" var-name "\")"))
      (beginning-of-defun)
      (forward-kill-sexp)
      (insert (read clojure-refactoring-temp)))))

(defun clojure-refactoring-destructure-map ()
  (let ((var-name (read-from-minibuffer "Map name: "))
        (defn (escape-string-literals (slime-defun-at-point))))
    (save-excursion
      (set-clojure-refactoring-temp
       (concat "(require 'clojure-refactoring.destructuring) (ns clojure-refactoring.destructuring) (destructure-map \"" defn "\" \"" var-name "\")"))
      (insert (read clojure-refactoring-temp)))))

(defvar clojure-refactoring-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-r") 'clojure-refactoring-ido)
    map)
  "Keymap for Clojure refactoring mode.")

;;;###autoload
(define-minor-mode clojure-refactoring-mode
  "A minor mode for a clojure refactoring tool"
  (when (slime-connected-p)
    (run-hooks 'slime-connected-hook)))

(progn (defun clojure-refactoring-enable ()
         (clojure-refactoring-mode t))
       (add-hook 'clojure-mode-hook 'clojure-refactoring-enable))

(provide 'clojure-refactoring-mode)
;;; clojure-refactoring-mode.el ends here
