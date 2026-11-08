;;;; Load-time guards: refuse a library whose major version, shim ABI or
;;;; struct layouts differ from what the bindings were generated for.

(in-package #:ghostty-vt)

(defparameter *supported-major-version* 1
  "libghostty-vt major version the generated bindings were made for.")

(defun ghostty-vt-available-p ()
  "True when ASDF loaded libghostty-vt and the ghostty-vt-cl shim."
  (let ((system (asdf:find-system "ghostty-vt" nil)))
    (and system
         (every (lambda (name)
                  (let ((c (asdf:find-component system name)))
                    (and c (asdf-native:native-library-loaded-path c) t)))
                '("ghostty-vt" "ghostty-vt-cl")))))

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
