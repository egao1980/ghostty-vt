(in-package #:ghostty-vt)

;;; Small helpers over the raw GHOSTTY-VT.FFI layer. Terminal semantics live
;;; in terminal-backend-ghostty, not here.

(defun check-result (result &optional function)
  "Return RESULT if it is :SUCCESS, else signal GHOSTTY-VT-ERROR."
  (unless (eq result :success)
    (error 'ghostty-vt-error :result result :function function))
  result)

(defmacro without-float-traps (&body body)
  "Run BODY with float traps masked. libghostty-vt's SIMD paths can raise
inexact/invalid flags that SBCL would otherwise turn into conditions."
  #+sbcl `(sb-int:with-float-traps-masked (:inexact :invalid :divide-by-zero
                                           :overflow :underflow)
            ,@body)
  #-sbcl `(progn ,@body))

(defmacro with-octets-pointer ((pointer length octets &key (start 0) end) &body body)
  "Bind POINTER to the bytes OCTETS[START, END) and LENGTH to their count.
A simple (unsigned-byte 8) vector is pinned in place; anything else is
copied into foreign memory for the extent of BODY."
  (let ((v (gensym "OCTETS")) (s (gensym "START")) (e (gensym "END"))
        (base (gensym "BASE")) (fn (gensym "BODY")))
    `(let* ((,v ,octets)
            (,s ,start)
            (,e (or ,end (length ,v))))
       (flet ((,fn (,pointer ,length) ,@body))
         (if (typep ,v '(simple-array (unsigned-byte 8) (*)))
             (cffi:with-pointer-to-vector-data (,base ,v)
               (,fn (cffi:inc-pointer ,base ,s) (- ,e ,s)))
             (let ((,length (- ,e ,s)))
               (cffi:with-foreign-object (,base :uint8 (max 1 ,length))
                 (loop for i from 0 below ,length
                       do (setf (cffi:mem-aref ,base :uint8 i) (aref ,v (+ ,s i))))
                 (,fn ,base ,length))))))))

(defun foreign-utf8 (pointer length)
  "LENGTH UTF-8 bytes at POINTER → a Lisp string."
  (if (or (cffi:null-pointer-p pointer) (zerop length))
      ""
      (cffi:foreign-string-to-lisp pointer :count length :encoding :utf-8)))

(defun call-with-output-buffer (function name &key (initial-size 64))
  "Call FUNCTION with (buffer-pointer buffer-length out-written-pointer), the
shape of every libghostty-vt encode call, and return the bytes it wrote as
an octet vector. Grows and retries on :OUT-OF-SPACE."
  (let ((size initial-size))
    (loop
      (cffi:with-foreign-objects ((buffer :uint8 size) (written :size))
        (let ((result (funcall function buffer size written)))
          (case result
            (:success
             (let* ((n (cffi:mem-ref written :size))
                    (out (make-array n :element-type '(unsigned-byte 8))))
               (dotimes (i n out)
                 (setf (aref out i) (cffi:mem-aref buffer :uint8 i)))
               (return out)))
            (:out-of-space
             (setf size (max (* 2 size) (cffi:mem-ref written :size))))
            (t (check-result result name))))))))

(defmacro with-sized ((var type) &body body)
  "Bind VAR to a zeroed foreign struct of TYPE (a CFFI (:struct …) type) whose
leading `size` field is set with ghostty_sized_init, as the size-prefixed
libghostty-vt structs require."
  (let ((size (gensym "SIZE")))
    `(let ((,size (cffi:foreign-type-size ',type)))
       (cffi:with-foreign-pointer (,var ,size)
         (ffi:sized-init ,var ,size)
         ,@body))))

(defun make-mode (number ansi-p)
  "GhosttyMode for mode NUMBER (ghostty_mode_new, a static inline in C)."
  (check-type number (integer 0 #x7fff))
  (logior number (if ansi-p #x8000 0)))

(defun ghostty-vt-version ()
  "→ the loaded library's version string, e.g. \"1.0.0\"."
  (cffi:foreign-string-to-lisp (ffi:version)))

(defun %major (version)
  (parse-integer version :end (position #\. version) :junk-allowed t))

(defun check-layouts ()
  "Compare every struct/union size the bindings were generated with against
the loaded library's own ghostty_type_json. Signals
GHOSTTY-VT-LAYOUT-MISMATCH on the first difference."
  (let ((json (cffi:foreign-string-to-lisp (ffi:type-json))))
    (loop for (name . size) in ffi:+layouts+
          for needle = (format nil "\"~A\":{\"kind\":" name)
          for at = (search needle json)
          do (unless at
               (error 'ghostty-vt-layout-mismatch
                      :reason (format nil "~A is missing from the loaded library" name)))
             (let* ((key "\"size\":")
                    (from (+ (search key json :start2 at) (length key)))
                    (actual (parse-integer json :start from :junk-allowed t)))
               (unless (eql actual size)
                 (error 'ghostty-vt-layout-mismatch
                        :reason (format nil "~A is ~A bytes, bindings expect ~A"
                                        name actual size))))))
  t)
