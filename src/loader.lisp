(in-package #:ghostty-vt)

;;; Load order: this file runs at ASDF load, before the generated DEFCFUNs, so
;;; every foreign symbol resolves against the overlay. Absolute paths only — no
;;; LD_LIBRARY_PATH / DYLD_LIBRARY_PATH.

(defparameter *supported-major-version* 1
  "libghostty-vt major version the generated bindings were made for.")

(defun %host-pair ()
  (format nil "~A-~A"
          #+windows "windows" #+darwin "darwin" #+linux "linux"
          #-(or windows darwin linux) "unknown"
          #+(or x86-64 x64) "amd64" #+(or arm64 aarch64) "arm64"
          #-(or x86-64 x64 arm64 aarch64) "unknown"))

(defun %library-names ()
  "→ (values core-name shim-name) for this OS."
  #+darwin (values "libghostty-vt.1.dylib" "libghostty-vt-cl.dylib")
  #+windows (values "ghostty-vt.dll" "ghostty-vt-cl.dll")
  #-(or darwin windows) (values "libghostty-vt.so.1" "libghostty-vt-cl.so"))

(defun %search-dirs ()
  "GHOSTTY_VT_NATIVE, then the overlay's native/, then lib/<os>-<arch>/."
  (let ((dirs '())
        (env (uiop:getenv "GHOSTTY_VT_NATIVE")))
    (when (and env (plusp (length env)))
      (push (uiop:ensure-directory-pathname env) dirs))
    (let ((system (asdf:find-system "ghostty-vt" nil)))
      (when system
        (let ((root (asdf:system-source-directory system)))
          (push (merge-pathnames "native/" root) dirs)
          (push (merge-pathnames (format nil "lib/~A/" (%host-pair)) root) dirs))))
    (nreverse dirs)))

(defvar *loaded* nil)

(defun %shared-object-loaded-p (path)
  "SBCL dlcloses and reopens a pathname it already has; skip those."
  #+sbcl (find (pathname path) sb-alien::*shared-objects*
               :key #'sb-alien::shared-object-pathname :test #'equal)
  #-sbcl (declare (ignore path))
  #-sbcl nil)

(defun %load (path)
  (unless (%shared-object-loaded-p path)
    (cffi:load-foreign-library path)))

(defun load-ghostty-vt ()
  "Load libghostty-vt and the ghostty-vt-cl shim from the first search
directory that has both. Idempotent. Signals GHOSTTY-VT-UNAVAILABLE."
  (unless *loaded*
    (multiple-value-bind (core shim) (%library-names)
      (let ((dir (find-if (lambda (d)
                            (and (probe-file (merge-pathnames core d))
                                 (probe-file (merge-pathnames shim d))))
                          (%search-dirs))))
        (unless dir
          (error 'ghostty-vt-unavailable
                 :reason (format nil "no ~A + ~A in ~{~A~^, ~}" core shim
                                 (mapcar #'namestring (%search-dirs)))))
        (handler-case
            (progn
              ;; Core first: the shim's dependency then resolves to it.
              (%load (namestring (truename (merge-pathnames core dir))))
              (%load (namestring (truename (merge-pathnames shim dir)))))
          (cffi:load-foreign-library-error (e)
            (error 'ghostty-vt-unavailable :reason (princ-to-string e))))))
    (setf *loaded* t))
  t)

(defun ghostty-vt-available-p ()
  (handler-case (load-ghostty-vt)
    (ghostty-vt-unavailable () nil)))

;; Load now, so the DEFCFUNs that follow link against the overlay.
(load-ghostty-vt)
