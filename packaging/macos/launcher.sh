#!/bin/sh
# Starts the portable Photon.app: registers the presentation broker that
# `photon run` normally registers, then runs the browser with the environment
# `photon run` normally sets.
set -eu

macos=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
contents=$(dirname -- "$macos")
support="$HOME/Library/Application Support/Photon/Portable"
mkdir -p "$support"

uid=$(id -u)
service="org.photonbrowser.photon.presentation.u$uid.portable.gpui-ce"
domain="gui/$uid"
target="$domain/$service"
broker="$macos/photon-presentation-broker"

# The broker runs from a stable copy so moving the app doesn't strand it.
if ! cmp -s "$broker" "$support/presentation_broker" 2>/dev/null; then
    launchctl bootout "$target" 2>/dev/null || true
    cp "$broker" "$support/presentation_broker.new"
    mv "$support/presentation_broker.new" "$support/presentation_broker"
fi

if ! launchctl print "$target" >/dev/null 2>&1; then
    plist="$support/$service.plist"
    cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$service</string>
<key>ProgramArguments</key><array><string>$support/presentation_broker</string><string>$service</string></array>
<key>MachServices</key><dict><key>$service</key><true/><key>$service.iosurface</key><true/></dict>
<key>RunAtLoad</key><true/>
<key>StandardErrorPath</key><string>$support/broker.err</string>
</dict></plist>
EOF
    launchctl bootstrap "$domain" "$plist" 2>/dev/null || launchctl print "$target" >/dev/null
fi

export PHOTON_HELPER_DIRECTORY="$macos"
export PHOTON_PRESENTATION_XPC_SERVICE="$service"
export PHOTON_PRESENTATION_CHANNEL_ID="photon-gpui-ce-$$-$(date +%s)"
export DYLD_LIBRARY_PATH="$contents/Frameworks${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"

exec "$macos/Photon-bin" -ApplePersistenceIgnoreState YES "$@"
