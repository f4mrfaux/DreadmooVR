"""Disassembler for cooked Unreal Blueprint (Kismet) bytecode, UE 5.x serialized form.

Produces one pseudo-code line per statement, labelled with the in-memory code offset so
jump targets line up. Read-only; nothing is executed.
"""
import struct


class ParseError(Exception):
    pass


class Dis:
    def __init__(self, pkg, script):
        self.pkg, self.b = pkg, script
        self.p = 0  # on-disk position
        self.m = 0  # in-memory offset (what jumps refer to)

    # ---- primitive readers ---------------------------------------------------
    def _take(self, fmt, size, mem=None):
        if self.p + size > len(self.b):
            raise ParseError("read past end")
        v = struct.unpack_from(fmt, self.b, self.p)[0]
        self.p += size
        self.m += size if mem is None else mem
        return v

    def u8(self):
        return self._take("<B", 1)

    def u16(self):
        return self._take("<H", 2)

    def i32(self):
        return self._take("<i", 4)

    def u32(self):
        return self._take("<I", 4)

    def i64(self):
        return self._take("<q", 8)

    def u64(self):
        return self._take("<Q", 8)

    def f32(self):
        return self._take("<f", 4)

    def f64(self):
        return self._take("<d", 8)

    def obj(self, short=True):
        return self.pkg.obj(self._take("<i", 4, mem=8), short)

    def name(self):
        idx = self._take("<I", 4, mem=0)
        num = self._take("<I", 4, mem=12)
        return self.pkg.fname(idx, num)

    def prop(self):
        n = self._take("<i", 4, mem=0)
        if n < 0 or n > 8:
            raise ParseError(f"bad field path length {n}")
        parts = []
        for _ in range(n):
            idx = self._take("<I", 4, mem=0)
            num = self._take("<I", 4, mem=0)
            parts.append(self.pkg.fname(idx, num))
        self._take("<i", 4, mem=8)  # owner struct
        return parts[0] if parts else "None"

    def cstr(self):
        end = self.b.index(b"\x00", self.p)
        s = self.b[self.p:end].decode("latin-1")
        n = end - self.p + 1
        self.p += n
        self.m += n
        return s

    def wstr(self):
        q = self.p
        while self.b[q:q + 2] != b"\x00\x00":
            q += 2
        s = self.b[self.p:q].decode("utf-16le", "replace")
        n = q - self.p + 2
        self.p += n
        self.m += n
        return s

    # ---- expressions ---------------------------------------------------------
    def args(self, terminator):
        out = []
        while True:
            if self.p >= len(self.b):
                raise ParseError("unterminated list")
            if self.b[self.p] == terminator:
                self.u8()
                return out
            out.append(self.expr())

    def expr(self):
        op = self.u8()
        f = getattr(self, f"op_{op:02X}", None)
        if f is None:
            raise ParseError(f"unknown opcode 0x{op:02X} at disk {self.p - 1}")
        return f()

    # variables
    def op_00(self):
        return self.prop()

    def op_01(self):
        return "self." + self.prop()

    def op_02(self):
        return "default." + self.prop()

    def op_48(self):
        return self.prop()

    def op_6C(self):
        return "sparse." + self.prop()

    def op_33(self):
        return "prop:" + self.prop()

    # flow
    def op_04(self):
        e = self.expr()
        return "return" if e == "" else f"return {e}"

    def op_06(self):
        return f"goto L{self.u32():04X}"

    def op_07(self):
        t = self.u32()
        return f"if not ({self.expr()}) goto L{t:04X}"

    def op_09(self):
        self.u16()
        self.u8()
        return f"assert({self.expr()})"

    def op_0B(self):
        return ""

    def op_0C(self):
        self.i32()
        return ""

    def op_4C(self):
        return f"push L{self.u32():04X}"

    def op_4D(self):
        return "pop-flow"

    def op_4E(self):
        return f"goto computed({self.expr()})"

    def op_4F(self):
        return f"if not ({self.expr()}) pop-flow"

    def op_53(self):
        return "<end>"

    def op_18(self):
        self.u32()
        return self.expr()

    # assignment
    def op_0F(self):
        self.prop()
        return self._assign()

    def _assign(self):
        dst = self.expr()
        return f"{dst} = {self.expr()}"

    op_14 = op_5F = op_60 = op_43 = op_44 = _assign

    def op_64(self):
        return f"frame.{self.prop()} = {self.expr()}"

    # context
    def _context(self):
        o = self.expr()
        self.u32()
        self.prop()
        return f"{o}.{self.expr()}"

    op_12 = op_19 = op_1A = _context

    def op_42(self):
        member = self.prop()
        return f"{self.expr()}.{member}"

    def op_51(self):
        return self.expr()

    def op_17(self):
        return "self"

    # calls
    def _call_obj(self):
        fn = self.obj(short=False)
        short = fn.rsplit(".", 2)
        label = ".".join(short[-2:]) if len(short) >= 2 and "KismetMathLibrary" not in fn else short[-1]
        return f"{label}({', '.join(self.args(0x16))})"

    op_1C = op_46 = op_68 = _call_obj

    def _call_name(self):
        fn = self.name()
        return f"{fn}({', '.join(self.args(0x16))})"

    op_1B = op_45 = _call_name

    def op_63(self):
        self.obj()
        a = self.args(0x16)
        return f"{a[0]}.Broadcast({', '.join(a[1:])})" if a else "Broadcast()"

    # constants
    def op_1D(self):
        return str(self.i32())

    def op_1E(self):
        return f"{self.f32():g}"

    def op_37(self):
        return f"{self.f64():g}"

    def op_35(self):
        return str(self.i64())

    def op_36(self):
        return str(self.u64())

    def op_1F(self):
        return '"' + self.cstr() + '"'

    def op_34(self):
        return '"' + self.wstr() + '"'

    def op_20(self):
        return self.obj()

    def op_21(self):
        return "'" + self.name() + "'"

    def op_22(self):
        return "Rot(%g,%g,%g)" % (self.f64(), self.f64(), self.f64())

    def op_23(self):
        return "Vec(%g,%g,%g)" % (self.f64(), self.f64(), self.f64())

    def op_41(self):
        return "Vec3f(%g,%g,%g)" % (self.f32(), self.f32(), self.f32())

    def op_2B(self):
        v = [self.f64() for _ in range(10)]
        return "Transform(rot=%g,%g,%g,%g loc=%g,%g,%g scale=%g,%g,%g)" % tuple(v)

    def op_24(self):
        return str(self.u8())

    op_2C = op_24

    def op_25(self):
        return "0"

    def op_26(self):
        return "1"

    def op_27(self):
        return "true"

    def op_28(self):
        return "false"

    def op_2A(self):
        return "null"

    op_2D = op_2A

    def op_11(self):
        self.prop()
        return str(self.u8())

    def op_5B(self):
        return f"L{self.u32():04X}"

    def op_29(self):
        t = self.u8()
        if t == 0:
            return 'Text("")'
        if t == 1:
            src = self.expr()
            self.expr()
            self.expr()
            return f"Text({src})"
        if t in (2, 3):
            return f"Text({self.expr()})"
        if t == 4:
            self.obj()
            a = self.expr()
            return f"TextTable({a}, {self.expr()})"
        raise ParseError(f"text literal type {t}")

    def op_67(self):
        return f"soft({self.expr()})"

    def op_6D(self):
        return f"fieldpath({self.expr()})"

    # casts
    def op_13(self):
        c = self.obj()
        return f"classcast<{c}>({self.expr()})"

    def op_2E(self):
        c = self.obj()
        return f"cast<{c}>({self.expr()})"

    def op_38(self):
        self.u8()
        return self.expr()

    def _iface_cast(self):
        c = self.obj()
        return f"iface<{c}>({self.expr()})"

    op_52 = op_54 = op_55 = _iface_cast

    # containers
    def op_2F(self):
        s = self.obj()
        self.i32()
        return f"{s}{{{', '.join(self.args(0x30))}}}"

    def op_31(self):
        dst = self.expr()
        return f"{dst} = [{', '.join(self.args(0x32))}]"

    def op_39(self):
        dst = self.expr()
        self.i32()
        return f"{dst} = set[{', '.join(self.args(0x3A))}]"

    def op_3B(self):
        dst = self.expr()
        self.i32()
        return f"{dst} = map[{', '.join(self.args(0x3C))}]"

    def op_65(self):
        self.prop()
        self.i32()
        return f"[{', '.join(self.args(0x66))}]"

    def op_3D(self):
        self.prop()
        self.i32()
        return f"set[{', '.join(self.args(0x3E))}]"

    def op_3F(self):
        self.prop()
        self.prop()
        self.i32()
        return f"map[{', '.join(self.args(0x40))}]"

    def op_6B(self):
        a = self.expr()
        return f"{a}[{self.expr()}]"

    def op_69(self):
        n = self.u16()
        self.u32()
        idx = self.expr()
        cases = []
        for _ in range(n):
            k = self.expr()
            self.u32()
            cases.append(f"{k}: {self.expr()}")
        return f"switch({idx}){{{'; '.join(cases)}; default: {self.expr()}}}"

    # delegates
    def op_4B(self):
        return "delegate:" + self.name()

    def op_61(self):
        fn = self.name()
        d = self.expr()
        return f"bind({d}, {self.expr()}, '{fn}')"

    def op_5C(self):
        d = self.expr()
        return f"{d} += {self.expr()}"

    def op_62(self):
        d = self.expr()
        return f"{d} -= {self.expr()}"

    def op_5D(self):
        return f"{self.expr()}.Clear()"

    # misc no-ops
    def op_15(self):
        return ""

    def op_4A(self):
        return ""

    def op_50(self):
        return ""

    def op_5A(self):
        return ""

    def op_5E(self):
        return ""

    def op_6A(self):
        if self.u8() == 4:
            self.name()
        return ""

    def op_72(self):
        return f"abort-if-not({self.expr()})"

    def statements(self):
        out = []
        while self.p < len(self.b):
            off = self.m
            s = self.expr()
            if s == "<end>":
                break
            if s:
                out.append((off, s))
        return out


FUNC_NET = 0x40


def find_script(data):
    """Locate the serialized script inside a UFunction export. Returns (bytes, flags) or None."""
    n = len(data)
    for tail in (12, 14):
        if n < tail + 9 or data[n - tail - 1] != 0x53:
            continue
        flags = struct.unpack_from("<I", data, n - tail)[0]
        if (tail == 14) != bool(flags & FUNC_NET):
            continue
        end = n - tail
        for q in range(0, end - 8):
            mem, disk = struct.unpack_from("<ii", data, q)
            # On-disk size can exceed in-memory size: field paths serialize larger than a pointer.
            if disk == end - (q + 8) and disk > 0 and 0 < mem < 4 * disk + 64:
                return data[q + 8:end], flags
    return None


def disassemble(pkg, export):
    found = find_script(pkg.export_bytes(export))
    if not found:
        return None, None
    script, flags = found
    d = Dis(pkg, script)
    return d.statements(), flags
