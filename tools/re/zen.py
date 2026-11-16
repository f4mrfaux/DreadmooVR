"""Parser for Unreal 5.6 "Zen" cooked packages as stored in IoStore containers.

Resolves names, imports (engine script objects and other packages) and exports, and
locates each export's serialized bytes. Read-only.
"""
import struct

TYPE_EXPORT, TYPE_SCRIPT, TYPE_PACKAGE, TYPE_NULL = 0, 1, 2, 3
IDX_MASK = (1 << 62) - 1


def load_name_batch(b, p):
    """Returns (names, end_offset)."""
    num = struct.unpack_from("<I", b, p)[0]
    p += 4
    if num == 0:
        return [], p
    p += 4  # string byte count
    p += 8  # hash version
    p += 8 * num
    headers = b[p:p + 2 * num]
    p += 2 * num
    names = []
    for i in range(num):
        h0, h1 = headers[2 * i], headers[2 * i + 1]
        ln = ((h0 & 0x7F) << 8) | h1
        if h0 & 0x80:
            p += p & 1
            names.append(b[p:p + 2 * ln].decode("utf-16le", "replace"))
            p += 2 * ln
        else:
            names.append(b[p:p + ln].decode("latin-1"))
            p += ln
    return names, p


class ScriptObjects:
    """Engine/native objects (classes, functions, structs) addressable by hash."""

    def __init__(self, data):
        names, p = load_name_batch(data, 0)
        n = struct.unpack_from("<i", data, p)[0]
        p += 4
        self.entries = {}
        for i in range(n):
            idx, num, gidx, outer, cdo = struct.unpack_from("<IIQQQ", data, p + i * 32)
            nm = names[idx & 0x3FFFFFFF]
            if num:
                nm = f"{nm}_{num - 1}"
            self.entries[gidx] = (nm, outer)
        self._cache = {}

    def path(self, gidx):
        if gidx in self._cache:
            return self._cache[gidx]
        parts = []
        cur = gidx
        guard = 0
        while cur in self.entries and guard < 16:
            nm, outer = self.entries[cur]
            parts.append(nm)
            cur = outer
            guard += 1
        parts.reverse()
        if not parts:
            s = f"<script:{gidx:016x}>"
        else:
            s = parts[0] + ("." + ".".join(parts[1:]) if len(parts) > 1 else "")
        self._cache[gidx] = s
        return s

    def leaf(self, gidx):
        e = self.entries.get(gidx)
        return e[0] if e else f"<script:{gidx:016x}>"


class Export:
    __slots__ = ("index", "name", "outer", "cls", "sup", "template", "hash", "flags", "size", "offset")


class Package:
    def __init__(self, data, ctx, path=""):
        self.data, self.ctx, self.path = data, ctx, path
        (has_ver, self.header_size, name_idx, _name_num, self.flags, self.cooked_header_size,
         hashes_off, import_off, export_off, bundle_off, dep_hdr_off, dep_ent_off, imp_names_off) = \
            struct.unpack_from("<IIIIIIiiiiiii", data, 0)
        if has_ver:
            raise ValueError("versioned packages are not supported")
        # Locate the name batch by its hash-version marker; the summary grew extra fields in 5.5+.
        marker = data.find(b"\x00\x00\x64\xc1\x00\x00\x00\x00", 0, 256)
        if marker < 8:
            raise ValueError("name batch not found")
        self.names, _ = load_name_batch(data, marker - 8)
        self.name = self.names[name_idx & 0x3FFFFFFF]

        self.import_hashes = list(struct.unpack_from(f"<{(import_off - hashes_off) // 8}Q", data, hashes_off))
        self.imports = list(struct.unpack_from(f"<{(export_off - import_off) // 8}Q", data, import_off))

        self.exports = []
        for i in range((bundle_off - export_off) // 72):
            (soff, ssize, nidx, nnum, outer, cls, sup, tmpl, phash, oflags, _filter) = \
                struct.unpack_from("<QQIIQQQQQIB", data, export_off + i * 72)
            e = Export()
            e.index = i
            e.name = self.names[nidx & 0x3FFFFFFF] + (f"_{nnum - 1}" if nnum else "")
            e.outer, e.cls, e.sup, e.template, e.hash, e.flags, e.size = outer, cls, sup, tmpl, phash, oflags, ssize
            # In 5.6 the cooked serial offset is relative to the start of the export payload area.
            e.offset = self.header_size + soff
            self.exports.append(e)
        self.payload_end = max((e.offset + e.size for e in self.exports), default=self.header_size)

        self.imported_packages = []
        if imp_names_off and imp_names_off < self.header_size:
            try:
                self.imported_packages, _ = load_name_batch(data, imp_names_off)
            except Exception:
                self.imported_packages = []

    # ---- reference resolution -------------------------------------------------
    def export_path(self, i):
        parts = []
        cur = i
        guard = 0
        while guard < 16:
            e = self.exports[cur]
            parts.append(e.name)
            if (e.outer >> 62) != TYPE_EXPORT:
                break
            cur = e.outer & IDX_MASK
            guard += 1
        return ".".join(reversed(parts))

    def resolve(self, poi, short=False):
        t = poi >> 62
        if t == TYPE_NULL:
            return "None"
        if t == TYPE_EXPORT:
            i = poi & IDX_MASK
            return self.exports[i].name if short else self.export_path(i)
        if t == TYPE_SCRIPT:
            return self.ctx.scripts.leaf(poi) if short else self.ctx.scripts.path(poi)
        v = poi & IDX_MASK
        pkg_i, hash_i = v >> 32, v & 0xFFFFFFFF
        pkg = self.imported_packages[pkg_i] if pkg_i < len(self.imported_packages) else f"<pkg{pkg_i}>"
        h = self.import_hashes[hash_i] if hash_i < len(self.import_hashes) else 0
        obj = self.ctx.export_name_by_hash(pkg, h)
        base = pkg.rsplit("/", 1)[-1]
        if obj is None:
            return base if short else f"{pkg}.<{h:016x}>"
        return obj if short else f"{pkg}.{obj}"

    def obj(self, package_index, short=True):
        """Resolve a serialized FPackageIndex (int32)."""
        if package_index == 0:
            return "None"
        if package_index > 0:
            i = package_index - 1
            if i >= len(self.exports):
                return f"<export{i}?>"
            return self.exports[i].name if short else self.export_path(i)
        i = -package_index - 1
        if i >= len(self.imports):
            return f"<import{i}?>"
        return self.resolve(self.imports[i], short)

    def fname(self, idx, num):
        i = idx & 0x3FFFFFFF
        if i >= len(self.names):
            return f"<name{i}?>"
        return self.names[i] + (f"_{num - 1}" if num else "")

    def export_bytes(self, e):
        return self.data[e.offset:e.offset + e.size]

    def class_of(self, e, short=True):
        return self.resolve(e.cls, short)


class Context:
    """Loads packages on demand and resolves cross-package references."""

    def __init__(self, store, global_store):
        self.store = store
        self.scripts = ScriptObjects(global_store.read_chunk(0))
        self._pkgs = {}
        self._hash_cache = {}
        self._by_lower = {}
        for p in store.files:
            if p.endswith((".uasset", ".umap")):
                self._by_lower[p.lower()] = p

    def file_for_package(self, pkg_name):
        """Map '/Game/A/B' or '/Plugin/A/B' to a container file path."""
        low = pkg_name.lower()
        if low.startswith("/game/"):
            tail = "dreadmoor/content/" + low[len("/game/"):]
            for ext in (".uasset", ".umap"):
                if tail + ext in self._by_lower:
                    return self._by_lower[tail + ext]
        parts = low.strip("/").split("/", 1)
        if len(parts) == 2:
            suffix = f"/{parts[0]}/content/{parts[1]}"
            for ext in (".uasset", ".umap"):
                for k, v in self._by_lower.items():
                    if k.endswith(suffix + ext):
                        return v
        return None

    def load(self, file_path):
        if file_path not in self._pkgs:
            self._pkgs[file_path] = Package(self.store.read_file(file_path), self, file_path)
        return self._pkgs[file_path]

    def export_name_by_hash(self, pkg_name, h):
        if pkg_name not in self._hash_cache:
            table = {}
            fp = self.file_for_package(pkg_name)
            if fp:
                try:
                    pkg = self.load(fp)
                    for i, e in enumerate(pkg.exports):
                        if e.hash:
                            table[e.hash] = pkg.export_path(i)
                except Exception:
                    pass
            self._hash_cache[pkg_name] = table
        return self._hash_cache[pkg_name].get(h)
