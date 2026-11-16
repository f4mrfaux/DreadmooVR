"""Minimal read-only Unreal IoStore (.utoc/.ucas) reader.

Supports unencrypted containers with an embedded directory index. Decompression uses an
Oodle runtime DLL that is already present on this machine (path passed in by the caller).
Nothing in the game install is modified.
"""
import ctypes
import struct

NONE = 0xFFFFFFFF


class Oodle:
    def __init__(self, dll_path):
        self.dll = ctypes.CDLL(dll_path)
        fn = self.dll.OodleLZ_Decompress
        fn.restype = ctypes.c_int64
        fn.argtypes = [
            ctypes.c_char_p, ctypes.c_int64, ctypes.c_char_p, ctypes.c_int64,
            ctypes.c_int, ctypes.c_int, ctypes.c_int,
            ctypes.c_void_p, ctypes.c_int64, ctypes.c_void_p, ctypes.c_void_p,
            ctypes.c_void_p, ctypes.c_int64, ctypes.c_int,
        ]
        self.fn = fn

    def decompress(self, comp, raw_len):
        out = ctypes.create_string_buffer(raw_len)
        n = self.fn(comp, len(comp), out, raw_len, 1, 0, 0, None, 0, None, None, None, 0, 3)
        if n != raw_len:
            raise ValueError(f"Oodle decompress failed: got {n}, wanted {raw_len}")
        return out.raw


class Reader:
    def __init__(self, b, pos=0):
        self.b, self.p = b, pos

    def u32(self):
        v = struct.unpack_from("<I", self.b, self.p)[0]
        self.p += 4
        return v

    def i32(self):
        v = struct.unpack_from("<i", self.b, self.p)[0]
        self.p += 4
        return v

    def fstring(self):
        n = self.i32()
        if n == 0:
            return ""
        if n < 0:
            s = self.b[self.p:self.p + (-n) * 2].decode("utf-16le")
            self.p += (-n) * 2
        else:
            s = self.b[self.p:self.p + n].decode("latin-1")
            self.p += n
        return s.rstrip("\x00")


class IoStore:
    def __init__(self, utoc_path, oodle):
        self.oodle = oodle
        self.ucas_path = utoc_path[:-5] + ".ucas"
        b = open(utoc_path, "rb").read()
        if b[:16] != b"-==--==--==--==-":
            raise ValueError("not a utoc")
        self.version = b[16]
        (hdr, n, nblk, blk_sz, nmeth, meth_len, self.block_size, dir_size, _parts) = struct.unpack_from("<9I", b, 20)
        self.flags = b[80]
        seeds = struct.unpack_from("<I", b, 84)[0]
        no_hash = struct.unpack_from("<I", b, 96)[0]
        p = hdr
        self.chunk_ids = [b[p + i * 12:p + i * 12 + 12] for i in range(n)]
        p += n * 12
        self.offlen = []
        for i in range(n):
            e = b[p + i * 10:p + i * 10 + 10]
            self.offlen.append((int.from_bytes(e[:5], "big"), int.from_bytes(e[5:], "big")))
        p += n * 10
        p += seeds * 4 + no_hash * 4
        self.blocks = []
        for i in range(nblk):
            e = b[p + i * 12:p + i * 12 + 12]
            self.blocks.append((int.from_bytes(e[0:5], "little"), int.from_bytes(e[5:8], "little"),
                                int.from_bytes(e[8:11], "little"), e[11]))
        p += nblk * blk_sz
        self.methods = [b[p + i * meth_len:p + (i + 1) * meth_len].split(b"\x00")[0].decode() for i in range(nmeth)]
        p += nmeth * meth_len
        self.files = {}
        if dir_size:
            self._parse_dir(b[p:p + dir_size])
        self._ucas = open(self.ucas_path, "rb")

    def _parse_dir(self, d):
        r = Reader(d)
        self.mount = r.fstring()
        dirs = [(r.u32(), r.u32(), r.u32(), r.u32()) for _ in range(r.u32())]
        files = [(r.u32(), r.u32(), r.u32()) for _ in range(r.u32())]
        strings = [r.fstring() for _ in range(r.u32())]

        stack = [(0, "")]
        while stack:
            di, path = stack.pop()
            name, child, sib, ffile = dirs[di]
            here = path if name == NONE else path + strings[name] + "/"
            fi = ffile
            while fi != NONE:
                fname, nxt, user = files[fi]
                self.files[here + strings[fname]] = user
                fi = nxt
            if sib != NONE:
                stack.append((sib, path))
            if child != NONE:
                stack.append((child, here))

    def chunk_type(self, i):
        return self.chunk_ids[i][11]

    def read_chunk(self, i):
        off, length = self.offlen[i]
        if length == 0:
            return b""
        first, last = off // self.block_size, (off + length - 1) // self.block_size
        out = bytearray()
        for bi in range(first, last + 1):
            boff, csz, usz, meth = self.blocks[bi]
            self._ucas.seek(boff)
            raw = self._ucas.read(csz)
            if meth == 0:
                out += raw[:usz]
            else:
                out += self.oodle.decompress(raw, usz)
        start = off % self.block_size
        return bytes(out[start:start + length])

    def find(self, needle):
        needle = needle.lower()
        return sorted(p for p in self.files if needle in p.lower())

    def read_file(self, path):
        return self.read_chunk(self.files[path])
