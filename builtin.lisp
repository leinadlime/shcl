(defpackage :shcl/builtin
  (:use :common-lisp :shcl/utility)
  (:import-from :fset)
  (:export #:define-builtin #:lookup-builtin))
(in-package :shcl/builtin)

(optimization-settings)

(defparameter *builtin-table* (fset:empty-map)
  "A map from builtin name (string) to handler functions.")

(defmacro define-builtin (name (args) &body body)
  "Define a new shell builtin.

`name' should either be a symbol or a list of the
form (`function-name' `builtin-name') where `function-name' is a
symbol and `builtin-name' is a string.  If `name' is simply a symbol,
then the builtin name is the downcased symbol name."
  (when (symbolp name)
    (setf name (list name (string-downcase (symbol-name name)))))
  (destructuring-bind (function-sym string-form) name
    `(progn
       (defun ,function-sym (,args)
         ,@body)
       (setf *builtin-table* (fset:with *builtin-table* ,string-form ',function-sym)))))

(defun lookup-builtin (name)
  "Attempt to find the function which corresponds to the builtin with
the provided string name.

Returns nil if there is no builtin by the given name."
  (fset:lookup *builtin-table* name))
