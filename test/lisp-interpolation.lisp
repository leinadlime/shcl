(defpackage :shcl-test/lisp-interpolation
  (:use :common-lisp :prove :shcl/core/utility :shcl/core/lisp-interpolation :shcl/core/exit-info :shcl/core/command)
  (:shadow #:run))
(in-package :shcl-test/lisp-interpolation)

(optimization-settings)

(plan 10)

(defun shell (str)
  (evaluate-shell-string str))

(defun exit-ok (thing &optional description)
  (unless (typep thing 'exit-info)
    (fail description)
    (return-from exit-ok))
  (ok (exit-info-true-p thing)
      (or description "Expecting truthy status")))

(defun exit-fail (thing &optional description)
  (unless (typep thing 'exit-info)
    (fail description)
    (return-from exit-fail))
  (ok (exit-info-false-p thing)
      (or description "Expecting falsey status")))

(define-builtin -shcl-assert-equal (&rest args)
  "Exit 0 iff all arguments are the same."
  (let ((set (fset:convert 'fset:set args)))
    (if (equal 1 (fset:size set))
        (progn
          (pass "Strings matched")
          0)
        (progn
          (fail (format nil "Strings didn't match ~A" set))
          1))))

(define-builtin -shcl-assert-unequal (&rest args)
  "Exit 0 iff all arguments are different."
  (let ((set (fset:convert 'fset:set args)))
    (if (equal (length args) (fset:size set))
        (progn
          (pass "Strings didn't match")
          0)
        (progn
          (fail (format nil "Strings match ~A" args))
          1))))

(defun run (s &optional description)
  (ok (exit-info-true-p
       (evaluate-shell-string s))
      (or description (format nil "Command exited with code 0: ~A" s))))

(deftest check-result
  (exit-ok
   (shell "true")
   "True is true")
  (exit-fail
   (shell "false")
   "False is false")
  (exit-ok
   (check-result (shell "true"))
   "check-result doesn't interfere with true")
  (exit-fail
   (let (signaled)
     (handler-bind
         ((exit-failure
           (lambda (c)
             (setf signaled t)
             (pass "exit-failure signal is expected")
             (continue c))))
       (let ((result (check-result (shell "false"))))
         (unless signaled
           (fail "exit-failure signal is expected"))
         result)))))

(deftest capture
  (is (capture (:streams '(:stdout)) (shell "echo   \f'o'\"o\"   "))
      (format nil "foo~%")
      :test #'equal
      "Capturing works for basic strings")
  (is (capture (:streams '(:stdout :stderr 3)) (shell "echo foo && echo bar >&2 ; echo baz >&3"))
      (format nil "foo~%bar~%baz~%")
      :test #'equal
      "Capturing works for slightly more complex strings"))

(deftest splice
  (let ((lexical-variable "ABC"))
    (is (capture (:streams '(:stdout)) (evaluate-constant-shell-string "echo ,lexical-variable" :readtable *splice-table*))
        (format nil "ABC~%")
        :test #'equal
        "Splicing a lexical string works"))

  (let ((lexical-vector #("A " "b")))
    (is (capture (:streams '(:stdout)) (evaluate-constant-shell-string "echo ,@lexical-vector" :readtable *splice-table*))
        (format nil "A  b~%")
        :test #'equal
        "Splicing a lexical vector works"))

  (let ((lexical-seq (fset:seq "A " "b")))
    (is (capture (:streams '(:stdout)) (evaluate-constant-shell-string "echo ,@lexical-seq" :readtable *splice-table*))
        (format nil "A  b~%")
        :test #'equal
        "Splicing a lexical seq works")))

(deftest test-infrastructure
  (run "-shcl-assert-equal 0 0"
       "Equality comparison works")
  (run "-shcl-assert-unequal 1 0"
       "Inequality comparison works"))

(deftest variables
  (run "FOO=123 ; -shcl-assert-equal \"$FOO\" 123"
       "$variable expansion works")
  (run "FOO=123 ; -shcl-assert-equal \"${FOO}\" 123"
       "${variable} expansion works")
  (run "FOO=123 ; -shcl-assert-equal ${#FOO} 3"
       "${#variable} expansion works"))

(deftest for-loops
  (run "-shcl-assert-equal '' \"$(for VAR in ; do
echo $VAR
done)\""
       "For loops over empty lists work")
  (run "-shcl-assert-equal '1
2
3
' \"$(for VAR in 1 2 3
do
echo $VAR
done)\""
       "For loops over non-empty lists work")
  (run "-shcl-assert-unequal $(for VAR in 1 2 3
do
echo $VAR
done)"
       "For loops over non-empty lists work"))

(deftest if
  (exit-fail
   (shell "if true ; then true ; false ; fi")
   "Last exit code of then block is exit code of if")

  (exit-ok
   (shell "if true ; then true ; true ; fi")
   "Last exit code of then block is exit code of if")

  (is (capture (:streams '(:stdout)) (shell "if echo condition ; then echo truthy ; else echo falsey ; fi"))
      (format nil "condition~%truthy~%")
      :test #'equal
      "Only the true branch runs")

  (is (capture (:streams '(:stdout)) (shell "if echo condition && false ; then echo truthy ; else echo falsey ; fi"))
      (format nil "condition~%falsey~%")
      :test #'equal
      "Only the else branch runs")

  (is (capture (:streams '(:stdout)) (shell "if echo condition && false ; then echo truthy ; elif echo condition2 ; then echo elif-branch ; fi"))
      (format nil "condition~%condition2~%elif-branch~%")
      :test #'equal
      "Only the elif branch runs"))

(deftest bang
  (exit-fail
   (shell "! true"))
  (exit-ok
   (shell "! false")))

(deftest while
    (let ((count 0))
      (is (capture (:streams '(:stdout)) (evaluate-constant-shell-string "while [ ,count -ne 3 ]; do echo ,(incf count) ; done" :readtable *splice-table*))
          (format nil "1~%2~%3~%")
          :test #'equal
          "Basic while loop test")))

(deftest empty
  (exit-ok
   (shell "")
   "Empty string is truthy")
  (exit-ok
   (shell (format nil "~C" #\newline))
   "Single newline is truthy")
  (exit-ok
   (shell (format nil " ~C ~C " #\newline #\tab))
   "Miscellaneous whitespace is truthy"))
