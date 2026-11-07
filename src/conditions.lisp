(in-package #:ghostty-vt)

(define-condition ghostty-vt-error (error)
  ((result :initarg :result :reader ghostty-vt-error-result)
   (function :initarg :function :initform nil :reader ghostty-vt-error-function))
  (:report (lambda (c s)
             (format s "libghostty-vt~@[ ~A~] returned ~S"
                     (ghostty-vt-error-function c) (ghostty-vt-error-result c))))
  (:documentation "A libghostty-vt call returned a GhosttyResult other than
:SUCCESS. RESULT is the keyword (:OUT-OF-MEMORY :INVALID-VALUE :OUT-OF-SPACE
:NO-VALUE :IO-ERROR :LIMIT-EXCEEDED :REJECTED :UNSUPPORTED)."))

(define-condition ghostty-vt-unavailable (error)
  ((reason :initarg :reason :reader ghostty-vt-unavailable-reason))
  (:report (lambda (c s)
             (format s "libghostty-vt is not available: ~A"
                     (ghostty-vt-unavailable-reason c)))))

(define-condition ghostty-vt-layout-mismatch (ghostty-vt-unavailable) ())
