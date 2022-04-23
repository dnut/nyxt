;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(uiop:define-package :nyxt/reduce-tracking-mode
  (:use :common-lisp :nyxt)
  (:documentation "Mode to mitigate fingerprinting."))
(in-package :nyxt/reduce-tracking-mode)

(define-mode reduce-tracking-mode ()
  "Set specific settings in the web view in order to mitigate fingerprinting,
(how third-party trackers attempt to indentify you).

Fingerprinting can be tested with https://panopticlick.eff.org/."
  ((preferred-languages
    '("en_US")
    :type list-of-strings
    :documentation "The list of languages that will be sent as part of the
Accept-Language HTTP header.")
   (preferred-user-agent
    ;; Check https://techblog.willshouse.com/2012/01/03/most-common-user-agents
    ;; occasionally and refresh when necessary.
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.75 Safari/537.36"
    :type string
    :documentation "The user agent to set when enabling `reduce-tracking-mode'.
It's Safari on macOS by default, because this way we break fewer websites while
still being less noticeable in the crowd.")
   (old-user-agent
    nil
    :type (or null string)
    :export nil
    :documentation "The User Agent the browser had before enabling this mode.")
   (destructor
    (lambda (mode)
      (ffi-buffer-user-agent (buffer mode) (old-user-agent mode))
      (ffi-set-preferred-languages (buffer mode)
                                   (list (first
                                          (str:split
                                           "."
                                           (or (uiop:getenv "LANG") "")))))
      (ffi-set-tracking-prevention (buffer mode) nil)))
   (constructor
    (lambda (mode)
      (setf (old-user-agent mode) (ffi-buffer-user-agent (buffer mode)))
      (ffi-buffer-user-agent (buffer mode) (preferred-user-agent mode))
      (ffi-set-preferred-languages (buffer mode)
                                   (preferred-languages mode))
      (ffi-set-tracking-prevention (buffer mode) t)))))
