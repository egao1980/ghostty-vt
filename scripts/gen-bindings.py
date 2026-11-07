#!/usr/bin/env python3
"""Generate the raw CFFI layer for libghostty-vt.

Inputs (both vendored, both from the same release):
  include/ghostty-vt-types.json   ghostty_type_json() output: every struct,
                                  union, enum, bitfield and callback, with
                                  sizes and offsets
  include/ghostty/vt/**/*.h       GHOSTTY_API prototypes

Outputs:
  src/ffi-package.lisp            package GHOSTTY-VT.FFI and its exports
  src/ffi.lisp                    defctype / defcenum / defcstruct / defcunion,
                                  bitfield readers, defcfun

The package does not use CL, so names like STRING (GhosttyString) never
collide with CL symbols. Functions that pass or return a struct by value are
skipped here; native/ghostty-vt-cl.c flattens the ones we need.

Usage: scripts/gen-bindings.py   (from the repo root)
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TYPES = json.loads((ROOT / "include/ghostty-vt-types.json").read_text())["types"]
HEADERS = sorted((ROOT / "include/ghostty/vt").rglob("*.h"))

PRIMITIVE = {
    "u8": ":uint8", "u16": ":uint16", "u32": ":uint32", "u64": ":uint64",
    "i8": ":int8", "i16": ":int16", "i32": ":int32", "i64": ":int64",
    "f32": ":float", "f64": ":double", "bool": "bool",
    "usize": ":size", "isize": ":ssize", "pointer": ":pointer",
}
C_PRIMITIVE = {
    "void": ":void", "bool": "bool", "char": ":char", "float": ":float",
    "double": ":double", "size_t": ":size", "intptr_t": ":intptr",
    "uintptr_t": ":uintptr", "int": ":int",
    "uint8_t": ":uint8", "uint16_t": ":uint16", "uint32_t": ":uint32",
    "uint64_t": ":uint64", "int8_t": ":int8", "int16_t": ":int16",
    "int32_t": ":int32", "int64_t": ":int64",
}


def kebab(name):
    name = re.sub(r"^Ghostty", "", name)
    name = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", name)
    name = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1-\2", name)
    return name.lower()


def snake_kebab(name):
    return name.lower().replace("_", "-")


def keyword(name):
    k = snake_kebab(name)
    return f":|{k.upper()}|" if k[0].isdigit() else f":{k}"


def type_ref(spec):
    """CFFI type for a field/param spec from the JSON."""
    t = spec["type"] if isinstance(spec, dict) else spec
    if t in PRIMITIVE:
        return PRIMITIVE[t]
    info = TYPES.get(t)
    if info is None:
        raise KeyError(t)
    kind = info["kind"]
    if kind == "struct":
        return f"(:struct {kebab(t)})"
    if kind == "union":
        return f"(:union {kebab(t)})"
    if kind in ("opaque", "callback"):
        return ":pointer"
    return kebab(t)  # enum, packed, alias


def deps(info):
    out = set()
    for f in info.get("fields", {}).values():
        t = f["type"]
        if t == "array":
            t = f["elem"] if isinstance(f["elem"], str) else f["elem"]["type"]
        if TYPES.get(t, {}).get("kind") in ("struct", "union"):
            out.add(t)
    return out


def emit_types(out, exports):
    out.append(";;; Scalar types")
    out.append("(cffi:defctype bool (:boolean :uint8))")
    exports.add("bool")
    for name, info in sorted(TYPES.items()):
        kind = info["kind"]
        lname = kebab(name)
        if kind == "alias":
            out.append(f"(cffi:defctype {lname} {type_ref(info['type'])})")
        elif kind == "packed":
            out.append(f"(cffi:defctype {lname} {PRIMITIVE[info['underlying']]})")
        elif kind in ("opaque", "callback"):
            out.append(f"(cffi:defctype {lname} :pointer)")
        else:
            continue
        exports.add(lname)

    out.append("\n;;; Enums")
    for name, info in sorted(TYPES.items()):
        if info["kind"] != "enum":
            continue
        lname = kebab(name)
        base = PRIMITIVE[info["underlying"]]
        values = [f"({keyword(k)} {v})"
                  for k, v in sorted(info["values"].items(), key=lambda kv: kv[1])
                  if k != "MAX_VALUE"]
        out.append(f"(cffi:defcenum ({lname} {base})\n  " + "\n  ".join(values) + ")")
        exports.add(lname)

    out.append("\n;;; Bitfield readers: (READER integer) → field value")
    for name, info in sorted(TYPES.items()):
        if info["kind"] != "packed":
            continue
        lname = kebab(name)
        for field, bit in info["bits"].items():
            if "type" not in bit:
                continue  # tagged union arm; read through the API instead
            reader = f"{lname}-{snake_kebab(field)}"
            lsb, width, ftype = bit["lsb"], bit["width"], bit["type"]
            if ftype == "bool":
                body = f"(cl:logbitp {lsb} value)"
            elif TYPES.get(ftype, {}).get("kind") == "enum":
                body = (f"(cffi:foreign-enum-keyword '{kebab(ftype)} "
                        f"(cl:ldb (cl:byte {width} {lsb}) value) :errorp cl:nil)")
            else:
                body = f"(cl:ldb (cl:byte {width} {lsb}) value)"
            out.append(f"(cl:defun {reader} (value) {body})")
            exports.add(reader)

    out.append("\n;;; Structs and unions (explicit offsets from ghostty_type_json)")
    done = set()
    pending = sorted(n for n, i in TYPES.items() if i["kind"] in ("struct", "union"))
    while pending:
        progressed = False
        for name in list(pending):
            info = TYPES[name]
            if not deps(info) <= done:
                continue
            lname = kebab(name)
            macro = "defcstruct" if info["kind"] == "struct" else "defcunion"
            slots = []
            for field, f in sorted(info["fields"].items(),
                                   key=lambda kv: kv[1]["offset"]):
                fname = snake_kebab(field)
                # Union members all sit at offset 0; defcunion takes no :offset.
                offset = f" :offset {f['offset']}" if info["kind"] == "struct" else ""
                if f["type"] == "array":
                    slots.append(f"({fname} {type_ref(f['elem'])} :count {f['count']}{offset})")
                else:
                    slots.append(f"({fname} {type_ref(f)}{offset})")
            out.append(f"(cffi:{macro} ({lname} :size {info['size']})\n  "
                       + "\n  ".join(slots) + ")")
            exports.add(lname)
            exports.update(snake_kebab(f) for f in info["fields"])
            done.add(name)
            pending.remove(name)
            progressed = True
        if not progressed:
            sys.exit(f"cyclic struct dependencies: {pending}")


def emit_layout_table(out, exports):
    """Sizes the bindings were generated with, for a load-time ABI check."""
    rows = " ".join(f'("{n}" . {i["size"]})' for n, i in sorted(TYPES.items())
                    if i["kind"] in ("struct", "union"))
    out.append("\n(cl:defparameter +layouts+\n  '(" + rows + ")\n"
               '  "(C-name . size) of every struct and union in include/ghostty-vt-types.json.")')
    exports.add("+layouts+")


def c_type(text):
    """CFFI type for a C type in a prototype, or None if passed by value."""
    text = " ".join(text.replace("*", " * ").split())
    if "*" in text:
        return ":pointer"
    base = text.replace("const ", "").strip()
    if base in C_PRIMITIVE:
        return C_PRIMITIVE[base]
    info = TYPES.get(base)
    if info is None:
        raise KeyError(base)
    if info["kind"] in ("struct", "union"):
        return None
    return type_ref(base)


def prototypes():
    for header in HEADERS:
        s = header.read_text()
        s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
        s = re.sub(r"//[^\n]*", "", s)
        s = re.sub(r"^\s*#.*$", "", s, flags=re.M)
        for m in re.finditer(r"GHOSTTY_API\s+([^;]*?\))\s*;", s, flags=re.S):
            proto = " ".join(m.group(1).split())
            ret, name, args = re.match(r"(.*?)\b(ghostty_\w+)\s*\((.*)\)$", proto).groups()
            params = []
            for arg in [a.strip() for a in args.split(",")]:
                if arg in ("", "void"):
                    continue
                am = re.match(r"(.*?)(\w+)$", arg)
                params.append((am.group(2), am.group(1)))
            yield header.relative_to(ROOT / "include"), ret.strip(), name, params


def emit_functions(out, exports, skipped):
    out.append("\n;;; Functions")
    current = None
    for header, ret, name, params in prototypes():
        if header != current:
            out.append(f"\n;; {header}")
            current = header
        rtype = c_type(ret)
        ptypes = [(n, c_type(t)) for n, t in params]
        if rtype is None or any(t is None for _, t in ptypes):
            out.append(f";; skipped (struct by value): {name}")
            skipped.append(name)
            continue
        lname = snake_kebab(name[len("ghostty_"):])
        args = " ".join(f"({snake_kebab(n)} {t})" for n, t in ptypes)
        out.append(f'(cffi:defcfun ("{name}" {lname}) {rtype}{" " if args else ""}{args})')
        exports.add(lname)


def main():
    exports, skipped, body = set(), [], []
    emit_types(body, exports)
    emit_layout_table(body, exports)
    emit_functions(body, exports, skipped)
    header = (";;;; GENERATED by scripts/gen-bindings.py from include/ — do not edit.\n"
              f";;;; libghostty-vt {json.loads((ROOT / 'include/ghostty-vt-types.json').read_text())['library_version']}\n")
    (ROOT / "src/ffi.lisp").write_text(
        header + "\n(cl:in-package #:ghostty-vt.ffi)\n\n" + "\n".join(body) + "\n")
    names = "\n".join(f"   #:{n}" for n in sorted(exports))
    (ROOT / "src/ffi-package.lisp").write_text(
        header + "\n(cl:defpackage #:ghostty-vt.ffi\n  (:use)\n"
        "  (:documentation \"Raw libghostty-vt C API. Names drop the ghostty_/Ghostty prefix.\")\n"
        f"  (:export\n{names}))\n")
    print(f"{len(exports)} exports, {len(skipped)} skipped: {', '.join(skipped)}")


if __name__ == "__main__":
    main()
