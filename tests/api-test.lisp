(in-package #:ghostty-vt/tests)

(defun octets (string)
  (map '(simple-array (unsigned-byte 8) (*)) #'char-code string))

(defmacro with-terminal ((var cols rows) &body body)
  `(cffi:with-foreign-object (out :pointer)
     (gv:check-result (ffi:terminal-new (cffi:null-pointer) out ,cols ,rows))
     (let ((,var (cffi:mem-ref out :pointer)))
       (unwind-protect (progn ,@body)
         (ffi:terminal-free ,var)))))

(defun screen-text (terminal)
  (cffi:with-foreign-objects ((formatter :pointer) (ptr :pointer) (len :size))
    (gv:check-result (ffi:formatter-terminal-new (cffi:null-pointer) formatter terminal))
    (let ((f (cffi:mem-ref formatter :pointer)))
      (unwind-protect
           (progn
             (gv:check-result (ffi:formatter-format-alloc f (cffi:null-pointer) ptr len))
             (prog1 (gv:foreign-utf8 (cffi:mem-ref ptr :pointer) (cffi:mem-ref len :size))
               (ffi:free (cffi:null-pointer) (cffi:mem-ref ptr :pointer)
                         (cffi:mem-ref len :size))))
        (ffi:formatter-free f)))))

(deftest loads-version-1
  (ok (gv:ghostty-vt-available-p))
  (ok (eql 0 (search "1." (gv:ghostty-vt-version)))))

(deftest layouts-match-loaded-library
  (ok (gv:check-layouts))
  (ok (= 16 (cffi:foreign-type-size '(:struct ffi:style))))
  (ok (= 792 (cffi:foreign-type-size '(:struct ffi:render-state-colors)))))

(deftest hello-world-round-trip
  (with-terminal (term 80 24)
    (gv:with-octets-pointer (p n (octets (format nil "Hello, ~C[1;32mworld~C[0m!" #\Esc #\Esc)))
      (gv:without-float-traps (ffi:terminal-vt-write term p n)))
    (ok (equal (string-right-trim '(#\Space #\Newline) (screen-text term))
               "Hello, world!"))))

(deftest octets-pointer-handles-non-simple-vectors
  (with-terminal (term 20 2)
    (let ((v (make-array 3 :element-type '(unsigned-byte 8) :adjustable t
                           :initial-contents (octets "abc"))))
      (gv:with-octets-pointer (p n v :start 1)
        (ok (= n 2))
        (ffi:terminal-vt-write term p n)))
    (ok (eql 0 (search "bc" (screen-text term))))))

(deftest terminal-get-cursor
  (with-terminal (term 80 24)
    (gv:with-octets-pointer (p n (octets "abc"))
      (ffi:terminal-vt-write term p n))
    (cffi:with-foreign-object (x :uint16)
      (gv:check-result (ffi:terminal-get term :cursor-x x))
      (ok (= 3 (cffi:mem-ref x :uint16))))))

(deftest errors-are-conditions
  (ok (signals (gv:check-result :invalid-value 'demo) 'gv:ghostty-vt-error))
  (ok (eq :invalid-value
          (handler-case (gv:check-result :invalid-value)
            (gv:ghostty-vt-error (c) (gv:ghostty-vt-error-result c))))))

(deftest focus-encode-uses-output-buffer
  (ok (equalp (gv:call-with-output-buffer
               (lambda (buf len written) (ffi:focus-encode :gained buf len written))
               'focus-encode :initial-size 1)
              (octets (format nil "~C[I" #\Esc)))))

(deftest mode-packing
  (ok (= 2004 (gv:make-mode 2004 nil)))
  (ok (= (logior 4 #x8000) (gv:make-mode 4 t))))

(deftest shim-scroll-viewport
  (with-terminal (term 10 2)
    (ok (eq :success (gv:terminal-scroll-viewport term :bottom)))
    (ok (eq :success (gv:terminal-scroll-viewport term :delta -1)))))

(deftest shim-key-event-utf8
  (cffi:with-foreign-object (out :pointer)
    (gv:check-result (ffi:key-event-new (cffi:null-pointer) out))
    (let ((event (cffi:mem-ref out :pointer)))
      (unwind-protect
           (cffi:with-foreign-string ((s n) "é" :encoding :utf-8 :null-terminated-p nil)
             (gv:key-event-set-utf8 event s n)
             (ok (equal (gv:key-event-get-utf8 event) "é")))
        (ffi:key-event-free event)))))
