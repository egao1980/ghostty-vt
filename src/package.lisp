(defpackage #:ghostty-vt
  (:use #:cl)
  (:local-nicknames (#:ffi #:ghostty-vt.ffi))
  (:export
   ;; loading
   #:load-ghostty-vt
   #:ghostty-vt-available-p
   #:ghostty-vt-version
   #:*supported-major-version*
   #:check-layouts
   ;; conditions
   #:ghostty-vt-error
   #:ghostty-vt-error-result
   #:ghostty-vt-error-function
   #:ghostty-vt-unavailable
   #:ghostty-vt-unavailable-reason
   #:ghostty-vt-layout-mismatch
   ;; helpers
   #:check-result
   #:with-octets-pointer
   #:call-with-output-buffer
   #:with-sized
   #:foreign-utf8
   #:make-mode
   #:without-float-traps
   ;; shim (struct-by-value calls)
   #:key-event-set-utf8
   #:key-event-get-utf8
   #:mouse-event-set-position
   #:terminal-scroll-viewport))
