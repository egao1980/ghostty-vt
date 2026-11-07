(in-package #:ghostty-vt)

;;; native/ghostty-vt-cl.c: the struct-by-value calls, flattened.

(defconstant +shim-abi+ 2)

(cffi:defcfun ("ghostty_vt_cl_abi" %shim-abi) :int)

(cffi:defcfun ("ghostty_vt_cl_key_event_set_utf8" %key-event-set-utf8) ffi:result
  (event :pointer) (ptr :pointer) (len :size))

(cffi:defcfun ("ghostty_vt_cl_key_event_get_utf8" %key-event-get-utf8) :void
  (event :pointer) (out-ptr :pointer) (out-len :pointer))

(cffi:defcfun ("ghostty_vt_cl_mouse_event_set_position" %mouse-event-set-position)
    ffi:result
  (event :pointer) (x :float) (y :float))

(cffi:defcfun ("ghostty_vt_cl_terminal_scroll_viewport" %terminal-scroll-viewport)
    ffi:result
  (terminal :pointer) (tag :int) (value :intptr))

(cffi:defcfun ("ghostty_vt_cl_terminal_grid_ref" %terminal-grid-ref) ffi:result
  (terminal :pointer) (tag :int) (x :uint16) (y :uint32) (out :pointer))

(defun terminal-grid-ref (terminal tag x y out)
  "Fill the GhosttyGridRef at OUT for cell X, Y. TAG is a keyword of
FFI:POINT-TAG (:ACTIVE :VIEWPORT :SCREEN :HISTORY). → the result keyword;
the ref is only valid until the terminal next changes."
  (%terminal-grid-ref terminal (cffi:foreign-enum-value 'ffi:point-tag tag) x y out))

(defun key-event-set-utf8 (event pointer length)
  "Set EVENT's text to LENGTH UTF-8 bytes at POINTER. libghostty-vt keeps the
pointer, so the bytes must outlive every encode call using EVENT."
  (check-result (%key-event-set-utf8 event pointer length) 'key-event-set-utf8))

(defun key-event-get-utf8 (event)
  (cffi:with-foreign-objects ((ptr :pointer) (len :size))
    (%key-event-get-utf8 event ptr len)
    (foreign-utf8 (cffi:mem-ref ptr :pointer) (cffi:mem-ref len :size))))

(defun mouse-event-set-position (event x y)
  (check-result (%mouse-event-set-position event (float x 1f0) (float y 1f0))
                'mouse-event-set-position))

(defun terminal-scroll-viewport (terminal tag &optional (value 0))
  "TAG is a keyword of FFI:TERMINAL-SCROLL-VIEWPORT-TAG (:TOP :BOTTOM :DELTA …)."
  (check-result (%terminal-scroll-viewport
                 terminal
                 (cffi:foreign-enum-value 'ffi:terminal-scroll-viewport-tag tag)
                 value)
                'terminal-scroll-viewport))
