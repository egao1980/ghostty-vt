# ghostty-vt

CFFI bindings and native overlays for [libghostty-vt 1.0](https://mitchellh.com/writing/libghostty-1-0), Ghostty's portable terminal emulation library. This is not the terminal protocol. That is [`terminal-protocol`](https://github.com/egao1980/terminal-protocol), and [`terminal-backend-ghostty`](https://github.com/egao1980/terminal-backend-ghostty) builds on this repo.

| Package | Contents |
|---------|----------|
| `ghostty-vt.ffi` | The raw C API, **generated** from `include/ghostty-vt-types.json` (`ghostty_type_json()`) and the headers. Names drop the `ghostty_` / `Ghostty` prefix: `ghostty_terminal_new` → `ffi:terminal-new`, `GhosttyRenderStateColors` → `(:struct ffi:render-state-colors)`. Enums are keywords. |
| `ghostty-vt` | Loader, `check-result` → `ghostty-vt-error`, output-buffer and pinned-octets helpers, `with-sized`, `without-float-traps`, and the struct-by-value shim calls |

```lisp
(asdf:load-system "ghostty-vt")
(ghostty-vt:ghostty-vt-version) ; ⇒ "1.0.0"
```

## Overlays

| Platform | Files |
|----------|-------|
| `linux/amd64`, `linux/arm64` (glibc ≥ 2.31) | `libghostty-vt.so.1`, `libghostty-vt-cl.so` |
| `darwin/arm64` | `libghostty-vt.1.dylib`, `libghostty-vt-cl.dylib` |
| `windows/amd64` | `ghostty-vt.dll`, `ghostty-vt-cl.dll` |

`scripts/build-ghostty-vt.sh [os-arch …]` downloads the signed release tarballs, checks the minisign signatures and `SHA256SUMS`, and builds with Zig 0.17. Zig cross-compiles, so one host builds every Linux and Windows overlay. Output goes to `lib/<os>-<arch>/`. `GHOSTTY_VT_NATIVE=/dir` points the loader elsewhere.

## Safety checks at load

- The library must be major version 1. The shim ABI must match.
- **Layouts:** every struct and union size in the generated bindings is compared with the loaded library's own `ghostty_type_json()`. A mismatch signals `ghostty-vt-layout-mismatch`.

## The shim

`native/ghostty-vt-cl.c` wraps the six calls the backend needs that pass a struct by value: key-event UTF-8 get/set, mouse position get/set, viewport scroll, and grid refs (shim ABI 2). Those structs travel in integer registers, float registers or a hidden pointer depending on the ABI. A C compiler gets that right; CFFI without libffi can't. The shim adds no other logic.

## Regenerating

`scripts/gen-bindings.py` rewrites `src/ffi.lisp` and `src/ffi-package.lisp`. See [include/PROVENANCE.md](include/PROVENANCE.md).

## License

MIT. Overlay contents: [NOTICE](NOTICE).
