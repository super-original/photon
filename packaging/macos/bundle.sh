#!/bin/sh
# Packs a release build into a self-contained Photon.app.
#   Contents/MacOS       launcher, browser, broker and Engine helper processes
#   Contents/Resources   Engine resources (beside the helpers, as in build/)
#   Contents/Frameworks  Engine libraries
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
out=${1:-"$root/dist"}
app="$out/Photon.app"
contents="$app/Contents"

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources" "$contents/Frameworks"

cp -R "$root/build/app-release/." "$contents/MacOS/"
cp "$root/target/release/Photon" "$contents/MacOS/Photon-bin"
cp "$root/target/release/photon-presentation-broker" "$contents/MacOS/"
cp "$root/packaging/macos/launcher.sh" "$contents/MacOS/Photon"
chmod +x "$contents/MacOS/Photon"
cp -R "$root/build/Resources/." "$contents/Resources/"
for libraries in lib lib64; do
    if [ -d "$root/build/engine-release/$libraries" ]; then
        find "$root/build/engine-release/$libraries" -maxdepth 1 -name '*.dylib*' -exec cp -P {} "$contents/Frameworks/" \;
    fi
done

# Icon from the brand PNG master.
iconset="$out/Photon.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
master="$root/crates/photon-brand/assets/app-icon.png"
for size in 16 32 128 256 512; do
    sips -z $size $size "$master" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$master" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$contents/Resources/Photon.icns"
rm -rf "$iconset"

version=$(git -C "$root" rev-parse --short HEAD)
cat >"$contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Photon</string>
<key>CFBundleIdentifier</key><string>org.photonbrowser.photon.portable</string>
<key>CFBundleName</key><string>Photon</string>
<key>CFBundleDisplayName</key><string>Photon</string>
<key>CFBundleIconFile</key><string>Photon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.0-$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict></plist>
EOF

# The build linked absolute rpaths into the build tree; point everything at
# the bundle's Frameworks instead, then re-sign ad hoc.
for file in "$contents/MacOS/"* "$contents/Frameworks/"*; do
    [ -f "$file" ] && [ ! -L "$file" ] || continue
    file -b "$file" | grep -q Mach-O || continue
    case "$file" in
        */Frameworks/*) rpath='@loader_path' ;;
        *) rpath='@executable_path/../Frameworks' ;;
    esac
    otool -l "$file" | awk '/LC_RPATH/ {getline; getline; print $2}' | while read -r old; do
        case "$old" in
            "$root"/*) install_name_tool -delete_rpath "$old" "$file" 2>/dev/null || true ;;
        esac
    done
    install_name_tool -add_rpath "$rpath" "$file" 2>/dev/null || true
    codesign --force --sign - "$file"
done
codesign --force --sign - "$app"

echo "Bundled $app"
du -sh "$app"
