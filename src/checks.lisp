;;;; Load-time guards: refuse a library whose major version, shim ABI or
;;;; struct layouts differ from what the bindings were generated for.

(in-package #:ghostty-vt)

(defun %check-versions ()
  (let ((version (ghostty-vt-version)))
    (unless (eql (%major version) *supported-major-version*)
      (error 'ghostty-vt-unavailable
             :reason (format nil "loaded libghostty-vt ~A, bindings are for ~A.x"
                             version *supported-major-version*))))
  (let ((abi (%shim-abi)))
    (unless (= abi +shim-abi+)
      (error 'ghostty-vt-unavailable
             :reason (format nil "ghostty-vt-cl shim ABI ~A, expected ~A" abi +shim-abi+)))))


(%check-versions)
(check-layouts)
