#!/bin/bash
# Decode the Savedd app icon from base64 chunks
cd "$(dirname "$0")" || exit 1
cat AppIcon-1024.b64.part0 AppIcon-1024.b64.part1 AppIcon-1024.b64.part2 AppIcon-1024.b64.part3 > AppIcon-1024.b64
base64 -d AppIcon-1024.b64 > AppIcon-1024.png
echo "Decoded to Assets/AppIcon-1024.png"
echo "Drop this into Xcode Assets.xcassets > AppIcon > App Store slot"
echo "Xcode will generate the remaining sizes automatically."
