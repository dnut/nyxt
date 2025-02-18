;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(uiop:define-package :nyxt/emacs-mode
  (:use :common-lisp :nyxt)
  (:import-from #:keymap #:define-key #:define-scheme)
  (:documentation "Emacs-style bindings."))
(in-package :nyxt/emacs-mode)

(define-mode emacs-mode ()
  "Enable Emacs-style bindings.
To enable these bindings by default, add the mode to the list of default modes
in your configuration file.

Example:

\(defmethod customize-instance ((buffer buffer) &key)
  (nyxt/emacs-mode:emacs-mode :buffer buffer))"
  ((glyph "ε")
   (rememberable-p nil)
   (previous-keymap-scheme-name nil
    :type (or keymap:scheme-name null)
    :documentation "The previous keymap scheme that will be used when ending
this mode.")
   (destructor
    (lambda (mode)
      (setf (keymap-scheme-name (buffer mode))
            (previous-keymap-scheme-name mode))))
   (constructor
    (lambda (mode)
      (with-accessors ((buffer buffer)) mode
        (setf (previous-keymap-scheme-name mode) (keymap-scheme-name buffer))
        (setf (keymap-scheme-name buffer) scheme:emacs))))))
