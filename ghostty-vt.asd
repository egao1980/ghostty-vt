(defsystem "ghostty-vt"
  :version "0.1.0"
  :description "CFFI bindings + native overlays for libghostty-vt 1.0 (Ghostty's terminal emulation library)"
  :author "egao1980"
  :license "MIT"
  :depends-on ("cffi" "uiop")
  :serial t
  :pathname "src"
  :components ((:file "ffi-package")
               (:file "package")
               (:file "conditions")
               (:file "loader")
               (:file "ffi")
               (:file "api")
               (:file "shim")
               (:file "checks"))
  :in-order-to ((test-op (test-op "ghostty-vt/tests")))
  :properties
  (:cl-repo
   (:cffi-libraries ("libghostty-vt" "libghostty-vt-cl")
    :provides ("ghostty-vt")
    :overlays
    ((:platform (:os "linux" :arch "amd64")
      :layers ((:role "native-library"
                :files (("lib/linux-amd64/libghostty-vt.so.1" . "libghostty-vt.so.1")
                        ("lib/linux-amd64/libghostty-vt-cl.so" . "libghostty-vt-cl.so")))))
     (:platform (:os "linux" :arch "arm64")
      :layers ((:role "native-library"
                :files (("lib/linux-arm64/libghostty-vt.so.1" . "libghostty-vt.so.1")
                        ("lib/linux-arm64/libghostty-vt-cl.so" . "libghostty-vt-cl.so")))))
     (:platform (:os "darwin" :arch "arm64")
      :layers ((:role "native-library"
                :files (("lib/darwin-arm64/libghostty-vt.1.dylib" . "libghostty-vt.1.dylib")
                        ("lib/darwin-arm64/libghostty-vt-cl.dylib" . "libghostty-vt-cl.dylib")))))
     (:platform (:os "windows" :arch "amd64")
      :layers ((:role "native-library"
                :files (("lib/windows-amd64/ghostty-vt.dll" . "ghostty-vt.dll")
                        ("lib/windows-amd64/ghostty-vt-cl.dll" . "ghostty-vt-cl.dll")))))))))

(defsystem "ghostty-vt/tests"
  :depends-on ("ghostty-vt" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "api-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
