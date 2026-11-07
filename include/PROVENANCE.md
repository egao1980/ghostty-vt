# include/

| File | Source |
|------|--------|
| `ghostty/vt.h`, `ghostty/vt/**` | Installed headers of libghostty-vt **1.0.0** (`zig build --prefix …` from the signed source tarball) |
| `ghostty-vt-types.json` | `ghostty_type_json()` from that same build, pretty-printed |

| Field | Value |
|-------|-------|
| Upstream | https://github.com/ghostty-org/ghostty (tag `vt-1.0.0`) |
| Tarballs | `https://release.files.ghostty.org/libghostty-vt/1.0.0/` |
| Signing key | `RWQlAjJC23149WL2sEpT/l0QKy7hMIFhYdQOFy0Z7z7PbneUgvlsnYcV` (minisign) |
| Zig | 0.17.x |
| SPDX | MIT |

To bump: set `GHOSTTY_VT_VERSION`, run `scripts/build-ghostty-vt.sh`, copy the
new `include/` and `ghostty_type_json()` output here, then run
`scripts/gen-bindings.py`. `check-layouts` refuses a library whose struct
sizes differ from `+layouts+`.
