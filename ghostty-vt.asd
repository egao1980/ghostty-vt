(defsystem "ghostty-vt"
  :version "0.3.1"
  :description "CFFI bindings + native overlays for libghostty-vt 1.0 (Ghostty's terminal emulation library)"
  :author "egao1980"
  :license "MIT"
  :defsystem-depends-on ("asdf-native")
  :depends-on ("cffi" "uiop")
  :serial t
  :pathname "src"
  :components ((:file "ffi-package")
               (:file "package")
               (:file "conditions")
               ;; $GHOSTTY_VT_NATIVE, native/ (overlay), lib/<os>-<arch>/ (checkout).
               ;; Core first: the shim's dependency then resolves to it.
               (:native-library "ghostty-vt" :versions ("1"))
               (:native-library "ghostty-vt-cl" :env "GHOSTTY_VT_NATIVE")
               (:file "ffi")
               (:file "api")
               (:file "shim")
               (:file "checks"))
  :in-order-to ((test-op (test-op "ghostty-vt/tests")))
  ;; Overlays: lib/<os>-<arch>/ per platform, from the :native-library components.
  :properties (:cl-repo (:provides ("ghostty-vt"))))

(defsystem "ghostty-vt/tests"
  :depends-on ("ghostty-vt" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "api-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
