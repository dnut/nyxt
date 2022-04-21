;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(in-package :nyxt)

(defvar *command-list* '()
  "The list of known commands, for internal use only.")

(define-class command ()
  ((name (error "Command name required.")
         :export t
         :type symbol
         :documentation "Name of the command.
This is useful to build commands out of anonymous functions.")
   (docstring ""
              :type string
              :documentation "Documentation of the command.")
   (fn (error "Function required.")
     :type function
     :documentation "Function wrapped by the command.")
   (before-hook (make-instance 'hooks:hook-void)
                :type hooks:hook-void
                :documentation "Hook run before executing the command.")
   (after-hook (make-instance 'hooks:hook-void)
               :type hooks:hook-void
               :documentation "Hook run after executing the command.")
   (sexp nil ; TODO: Set with `function-lambda-expression' or use `swank' instead?
         :type t
         :documentation "S-expression of the definition of top-level commands or
commands wrapping over lambdas.
This is nil for local commands that wrap over named functions.")
   (visibility :mode
               :type (member :global :mode :anonymous)
               :documentation "
- `:global'  means it will be listed in `command-source' when the global option is on.
This is mostly useful for third-party packages to define globally-accessible
commands without polluting Nyxt packages.

- `:mode' means the command is only listed in `command-source' when the corresponding mode is active.

- `:anonymous' means the command is never listed in `command-source'.")
   (deprecated-p nil
                 :type boolean
                 :documentation "If non-nil, report a warning before executing
the command.")
   (last-access (local-time:now)
                :type local-time:timestamp
                :documentation "Last time this command was called from prompt buffer.
This can be used to order the commands."))
  (:metaclass closer-mop:funcallable-standard-class)
  (:accessor-name-transformer (class*:make-name-transformer name))
  (:export-class-name-p t)
  (:documentation "Commands are interactive functions.
(As in Emacs.)

Commands are funcallable.

We need a `command' class for multiple reasons:
- Identify commands uniquely.

- Customize prompt buffer display value with properties.

- Last access: This is useful to sort command by the time they were last
  called.  The only way to do this is to persist the command instances."))

(sera:eval-always
  (defun before-hook-name (command-name)
    (intern (format nil "~a-BEFORE-HOOK" command-name)
            (symbol-package command-name)))
  (defun after-hook-name (command-name)
    (intern (format nil "~a-AFTER-HOOK" command-name)
            (symbol-package command-name))))

(defmethod initialize-instance :after ((command command) &key)
  (setf (fn command)
        (lambda (&rest args)
          (when (deprecated-p command)
            ;; TODO: Should `define-deprecated-command' report the version
            ;; number of deprecation?  Maybe OK to just remove all deprecated
            ;; commands on major releases.
            (echo-warning "~a is deprecated." (name command)))
          (handler-case
              (progn
                (hooks:run-hook (before-hook command))
                ;; (log:debug "Calling command ~a." ',name)
                ;; TODO: How can we print the arglist as well?
                ;; (log:debug "Calling command (~a ~a)." ',name (list ,@arglist))
                (prog1 (apply (fn command)
                              (or args
                                  ;; The following is not defined yet.
                                  (mapcar 'prompt-argument
                                          (funcall 'parse-function-lambda-list-types (fn command)))))
                  (hooks:run-hook (after-hook command))))
            (nyxt-condition (c)
              (log:warn "~a" c)))))
  (unless (eq :anonymous (visibility command))
    (setf (fdefinition (name command)) (fn command))
    (setf (documentation (name command) 'function) (docstring command))
    (export-always (name command) (symbol-package (name command)))
    ;; From `defparameter' CLHS documentation:
    (eval-when (:compile-toplevel :load-toplevel :execute)
      (let ((before-hook-sym (before-hook-name (name command)))
            (after-hook-sym (after-hook-name (name command))))
        (setf (symbol-value before-hook-sym) (before-hook command)
              (symbol-value after-hook-sym) (after-hook command))
        (export (list before-hook-sym after-hook-sym) (symbol-package (name command)))))
    (unless (deprecated-p command)
      ;; Overwrite previous command:
      (setf *command-list* (delete (name command) *command-list* :key #'name))
      (push command *command-list*)))
  ;; (funcall <COMMAND ...>) should work:
  (closer-mop:set-funcallable-instance-function
   command
   (lambda (&rest args)
     (apply (fn command) args))))

(defmethod print-object ((command command) stream)
  (print-unreadable-object (command stream :type t :identity t)
    (format stream "~a" (name command))))

(define-condition documentation-style-warning (style-warning)
  ((name :initarg :name :reader name)
   (subject-type :initarg :subject-type :reader subject-type))
  (:report
   (lambda (condition stream)
     (format stream
             "~:(~A~) ~A doesn't have a documentation string"
             (subject-type condition)
             (name condition)))))

(define-condition command-documentation-style-warning  ; TODO: Remove and force docstring instead.
    (documentation-style-warning)
  ((subject-type :initform 'command)))

(defun find-command (name)
  (find name *command-list* :key #'name))

(export-always 'make-command)
(defmacro make-command (name arglist &body body)
  "Return a new local `command' named NAME.

With BODY, the command binds ARGLIST and executes the body.
The first string in the body is used to fill the `help' slot.

Without BODY, NAME must be a function symbol and the command wraps over it
against ARGLIST, if specified.

This is a convenience wrapper.  If you want full control over a command
instantiation, use `make-instance command' instead."
  (check-type name symbol)
  (let ((documentation (or (nth-value 2 (alex:parse-body body :documentation t))
                           ""))
        (args (multiple-value-match (alex:parse-ordinary-lambda-list arglist)
                ((required-arguments optional-arguments rest keyword-arguments)
                 (append required-arguments
                         optional-arguments
                         (alex:mappend #'first keyword-arguments)
                         (when rest
                           (list rest)))))))
    (alex:with-gensyms (fn sexp)
      `(let ((,fn nil)
             (,sexp nil))
         (cond
           (',body
            (setf ,fn (lambda (,@arglist) ,@body)
                  ,sexp '(lambda (,@arglist) ,@body)))
           ((and ',arglist (typep ',name 'function-symbol))
            (setf ,fn (lambda (,@arglist) (funcall ',name ,@args))
                  ,sexp '(lambda (,@arglist) (funcall ,name ,@args))))
           ((and (null ',arglist) (typep ',name 'function-symbol))
            (setf ,fn (symbol-function ',name)))
           (t (error "Either NAME must be a function symbol, or ARGLIST and BODY must be set properly.")))
         (make-instance 'command
                        :name ',name
                        :visibility :anonymous
                        :docstring ,documentation
                        :fn ,fn
                        :sexp ,sexp)))))

(export-always 'make-mapped-command)
(defmacro make-mapped-command (function-symbol)
  "Define a command which `mapcar's FUNCTION-SYMBOL over a list of arguments."
  (let ((name (intern (str:concat (string function-symbol) "-*"))))
    `(make-command ,name (arg-list)
       ,(documentation function-symbol 'function)
       (mapcar ',function-symbol arg-list))))

(export-always 'make-unmapped-command)
(defmacro make-unmapped-command (function-symbol)
  "Define a command which calls FUNCTION-SYMBOL over the first element of a list
of arguments."
  (let ((name (intern (str:concat (string function-symbol) "-1"))))
    `(make-command ,name (arg-list)
       ,(documentation function-symbol 'function)
       (,function-symbol (first arg-list)))))

(sera:eval-always
  (defun define-command-preamble (name arglist body setup)
    `(progn (sera:eval-always
              (export ',name (symbol-package ',name))
              ;; HACK: This seemingly redundant `defun' is used to avoid style
              ;; warnings when calling (FOO ...) in the rest of the file where
              ;; it's defined.  Same with `defparameter' for the hooks.
              (defun ,name (,@arglist) ,@body)
              (defparameter ,(before-hook-name name) nil)
              (defparameter ,(after-hook-name name) nil))
            ,setup)))

(export-always 'define-command)
(defmacro define-command (name (&rest arglist) &body body)
  "Define new command NAME.
`define-command' has a syntax similar to `defun'.
ARGLIST must be a list of optional arguments or key arguments.
This macro also defines two hooks, NAME-before-hook and NAME-after-hook.
When run, the command always returns the last expression of BODY.

Example:

\(define-command play-video-in-current-page (&optional (buffer (current-buffer)))
  \"Play video in the currently open buffer.\"
  (uiop:run-program (list \"mpv\" (render-url (url buffer)))))"
  (define-command-preamble name arglist body
      `(make-instance 'command :name ',name :visibility :mode :fn (lambda (,@arglist) ,@body))))

(export-always 'define-command-global)
(defmacro define-command-global (name (&rest arglist) &body body)
  "Like `define-command' but mark the command as global.
This means it will be listed in `command-source' when the global option is on.
This is mostly useful for third-party packages to define globally-accessible
commands without polluting Nyxt packages."
  (define-command-preamble name arglist body
    `(make-instance 'command :name ',name :visibility :global :fn (lambda (,@arglist) ,@body))))

(export-always 'delete-command)
(defun delete-command (name)
  "Remove command NAME, if any.
Any function or macro definition of NAME is also removed,
regardless of whether NAME is defined as a command."
  (setf *command-list* (delete name *command-list* :key #'name))
  (fmakunbound name))

(defmacro define-deprecated-command (name (&rest arglist) &body body)
  "Define NAME, a deprecated command.
This is just like a command.  It's recommended to explain why the function is
deprecated and by what in the docstring."
  (define-command-preamble name arglist body
    `(make-instance 'command :name ',name :deprecated t :visibility :mode
                             :fn (lambda (,@arglist) ,@body))))

(defun nyxt-packages ()                 ; TODO: Export a customizable *nyxt-packages* instead?
  "Return all package designators that start with 'nyxt' plus Nyxt own libraries."
  (mapcar #'package-name
          (append (delete-if
                   (lambda (p)
                     (not (str:starts-with-p "NYXT" (package-name p))))
                   (list-all-packages))
                  (mapcar #'find-package
                          '(class-star
                            download-manager
                            history-tree
                            keymap
                            scheme
                            password
                            analysis
                            text-buffer)))))

(defun package-defined-symbols (&optional (external-package-designators (nyxt-packages))
                                  (user-package-designators '(:nyxt-user)))
  "Return the list of all external symbols interned in EXTERNAL-PACKAGE-DESIGNATORS
and all (possibly unexported) symbols in USER-PACKAGE-DESIGNATORS."
  (let ((external-package-designators
          ;; This is for the case external-package-designators are passed nil.
          (or external-package-designators (nyxt-packages)))
        (symbols))
    (dolist (package (mapcar #'find-package external-package-designators))
      (do-external-symbols (s package symbols)
        (pushnew s symbols)))
    (dolist (package (mapcar #'find-package user-package-designators))
      (do-symbols (s package symbols)
        (when (eq (symbol-package s) package)
          (pushnew s symbols))))
    symbols))

(defun package-variables (&optional packages)
  "Return the list of variable symbols in Nyxt-related-packages."
  (delete-if (complement #'boundp) (package-defined-symbols packages)))

(defun package-functions (&optional packages)
  "Return the list of function symbols in Nyxt-related packages."
  (delete-if (complement #'fboundp) (package-defined-symbols packages)))

(defun package-classes (&optional packages)
  "Return the list of class symbols in Nyxt-related-packages."
  (delete-if (lambda (sym)
               (not (and (find-class sym nil)
                         ;; Discard non-standard objects such as structures or
                         ;; conditions because they don't have public slots.
                         (mopu:subclassp (find-class sym) (find-class 'standard-object)))))
             (package-defined-symbols packages)))

(define-class slot ()
  ((name nil
         :type (or symbol null))
   (class-sym nil
              :type (or symbol null)))
  (:accessor-name-transformer (class*:make-name-transformer name)))

(defmethod prompter:object-attributes ((slot slot))
  `(("Name" ,(string (name slot)))
    ("Class" ,(string (class-sym slot)))))

(defun exported-p (sym)
  (eq :external
      (nth-value 1 (find-symbol (string sym)
                                (symbol-package sym)))))

(defun class-public-slots (class-sym)
  "Return the list of exported slots."
  (delete-if
   (complement #'exported-p)
   (mopu:slot-names class-sym)))

(defun package-slots (&optional packages)
  "Return the list of all slot symbols in `:nyxt' and `:nyxt-user' or other PACKAGES."
  (alex:mappend (lambda (class-sym)
                  (mapcar (lambda (slot) (make-instance 'slot
                                                        :name slot
                                                        :class-sym class-sym))
                          (class-public-slots class-sym)))
                (package-classes packages)))

(defun package-methods (&optional packages) ; TODO: Unused.  Remove?
  (loop for sym in (package-defined-symbols packages)
        append (ignore-errors
                (closer-mop:generic-function-methods (symbol-function sym)))))

(defmethod mode-toggler-p ((command command))
  "Return non-nil if COMMAND is a mode toggler.
A mode toggler is a command of the same name as its associated mode."
  (ignore-errors
   (closer-mop:subclassp (find-class (name command) nil)
                         (find-class 'mode))))

(defun list-commands (&key global-p mode-symbols)
  "List commands.
Commands are instances of the `command' class.
When MODE-SYMBOLS are provided, list only the commands that belong to the
corresponding mode packages or of a parent mode packages.
Otherwise list all commands.
With MODE-SYMBOLS and GLOBAL-P, include global commands."
  ;; TODO: Make sure we list commands of inherited modes.
  (if mode-symbols
      (lpara:premove-if
       (lambda (command)
         (and (or (not global-p)
                  (not (eq :global (visibility command))))
              (notany
               (lambda (mode-symbol)
                 (eq (symbol-package (name command))
                     (symbol-package (mode-symbol mode-symbol))))
               mode-symbols)))
       *command-list*)
      *command-list*))

(-> function-command (function) (or null command))
(defun function-command (function)
  "Return the command associated to FUNCTION, if any."
  (find-if (sera:eqs function) (list-commands) :key #'fn))

(defun run (command &rest args)
  "Run COMMAND over ARGS and return its result.
This is blocking, see `run-async' for an asynchronous way to run commands."
  (let ((channel (make-channel 1)))
    (run-thread "run command"
      (calispel:! channel
               ;; Bind current buffer for the duration of the command.  This
               ;; way, if the user switches buffer after running a command
               ;; but before command termination, `current-buffer' will
               ;; return the buffer from which the command was invoked.
               (with-current-buffer (current-buffer)
                 (handler-case (apply #'funcall command args)
                   (nyxt-prompt-buffer-canceled ()
                     (log:debug "Prompt buffer interrupted")
                     nil)))))
    (calispel:? channel)))

(defun run-async (command &rest args)
  "Run COMMAND over ARGS asynchronously.
See `run' for a way to run commands in a synchronous fashion and return the
result."
  (run-thread "run-async command"
    ;; It's important to rebind `args' since it may otherwise be shared with the
    ;; caller.
    (let ((command command)
          (args args))
      (with-current-buffer (current-buffer) ; See `run' for why we bind current buffer.
        (handler-case (apply #'funcall command args)
          (nyxt-prompt-buffer-canceled ()
            (log:debug "Prompt buffer interrupted")
            nil))))))

(define-command forward-to-renderer (&key (window (current-window))
                                     (buffer (current-buffer)))
  "A command that forwards the last key press to the renderer.
This is useful to override bindings to be forwarded to the renderer."
  (ffi-generate-input-event window (last-event buffer)))

(define-command nothing ()                 ; TODO: Replace with ESCAPE special command that allows dispatched to cancel current key stack.
  "A command that does nothing.
This is useful to override bindings to do nothing."
  (values))
