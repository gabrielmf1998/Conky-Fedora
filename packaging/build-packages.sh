#!/usr/bin/env bash
# Builds the .rpm (Fedora) and the .pkg.tar.zst (Arch) into dist/.
#
# The Arch package is assembled by hand because makepkg does not exist on
# Fedora. It mirrors the package() steps of the PKGBUILD, which stays the
# canonical recipe on an Arch box.
set -euo pipefail

NAME=conky-fedora-panel
TRAY=conky-panel-tray
VERSION=1.1.0
RELEASE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

mkdir -p "$DIST"

say "packing the source tarball"
SRCDIR="$WORK/$NAME-$VERSION"
mkdir -p "$SRCDIR"
cp -r "$ROOT"/{conky,tray,systemd,assets,packaging,docs,LICENSE,README.md,install.sh} \
      "$SRCDIR/" 2>/dev/null || true
find "$SRCDIR" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
rm -f "$SRCDIR/packaging/build-packages.sh"
tar -C "$WORK" -czf "$WORK/$NAME-$VERSION.tar.gz" "$NAME-$VERSION"

# ── RPM ─────────────────────────────────────────────────────
if command -v rpmbuild >/dev/null; then
    say "building the RPM"
    TOP="$WORK/rpm"
    mkdir -p "$TOP"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
    cp "$WORK/$NAME-$VERSION.tar.gz" "$TOP/SOURCES/"
    cp "$ROOT/packaging/fedora/$NAME.spec" "$TOP/SPECS/"
    rpmbuild --define "_topdir $TOP" -bb "$TOP/SPECS/$NAME.spec" >"$WORK/rpm.log" 2>&1 || {
        tail -25 "$WORK/rpm.log"; exit 1; }
    find "$TOP/RPMS" -name '*.rpm' -exec cp {} "$DIST/" \;
    say "RPM: $(find "$DIST" -name "$NAME-$VERSION*.rpm" -printf '%f\n' | head -1)"
else
    say "rpmbuild missing, skipping the RPM"
fi

# ── Arch ────────────────────────────────────────────────────
say "building the Arch package"
PKG="$WORK/pkg"
SHARE="$PKG/usr/share/$NAME"
install -d "$SHARE/scripts" "$SHARE/conkytray"
install -m 0644 "$ROOT/conky/pride.conf"    "$SHARE/"
install -m 0755 "$ROOT"/conky/scripts/*.sh  "$SHARE/scripts/"
install -m 0644 "$ROOT/conky/60-rapl.rules" "$SHARE/"
install -m 0644 "$ROOT"/tray/conkytray/*.py "$SHARE/conkytray/"

install -Dm 0755 "$ROOT/packaging/$TRAY"          "$PKG/usr/bin/$TRAY"
install -Dm 0644 "$ROOT/systemd/$NAME.service"    "$PKG/usr/lib/systemd/user/$NAME.service"
install -Dm 0644 "$ROOT/systemd/$TRAY.service"    "$PKG/usr/lib/systemd/user/$TRAY.service"
install -Dm 0644 "$ROOT/systemd/$TRAY.desktop"    "$PKG/usr/share/applications/$TRAY.desktop"
for size in 48 64 128 256; do
    install -Dm 0644 "$ROOT/assets/$TRAY-${size}.png" \
        "$PKG/usr/share/icons/hicolor/${size}x${size}/apps/$TRAY.png"
done
install -Dm 0644 "$ROOT/LICENSE"   "$PKG/usr/share/licenses/$NAME/LICENSE"
install -Dm 0644 "$ROOT/README.md" "$PKG/usr/share/doc/$NAME/README.md"
cp -r "$ROOT/docs" "$PKG/usr/share/doc/$NAME/"

SIZE=$(du -sb "$PKG" | cut -f1)
cat > "$PKG/.PKGINFO" <<EOF
pkgname = $NAME
pkgbase = $NAME
pkgver = $VERSION-$RELEASE
pkgdesc = Dense Conky system panel with a tray control icon
url = https://github.com/gabrielmf1998/Conky-Fedora
builddate = $(date +%s)
packager = Gabriel Marques Ferrarezi <110578985+gabrielmf1998@users.noreply.github.com>
size = $SIZE
arch = any
license = MIT
depend = conky
depend = python
depend = pyside6
optdepend = lm_sensors: board temperatures, fan RPM and voltages
optdepend = nvidia-utils: the GPU section, via nvidia-smi
optdepend = ttf-terminus-ttf: the bitmap font the panel is designed around
EOF

cd "$PKG"
# root:root é obrigatório — sem isso o pacman instala com o uid de quem
# empacotou. --no-xattrs tira os rótulos de SELinux do Fedora.
TAROPTS=(--no-xattrs --no-fflags --uid 0 --gid 0 --uname root --gname root)
LANG=C bsdtar "${TAROPTS[@]}" -czf .MTREE --format=mtree \
    --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' \
    .PKGINFO usr
LANG=C bsdtar "${TAROPTS[@]}" -cf - .PKGINFO .MTREE usr |
    zstd -q -c -T0 -18 > "$DIST/$NAME-$VERSION-$RELEASE-any.pkg.tar.zst"
say "Arch: $NAME-$VERSION-$RELEASE-any.pkg.tar.zst"

cd "$DIST"
sha256sum ./*.rpm ./*.pkg.tar.zst > SHA256SUMS 2>/dev/null || true
say "done. Artifacts in dist/:"
ls -1sh "$DIST"
