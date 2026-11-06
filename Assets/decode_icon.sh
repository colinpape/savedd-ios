#!/bin/bash
# Decode the Savedd app icon
mkdir -p Assets
base64 -d Assets/AppIcon-1024.b64 > Assets/AppIcon-1024.png
echo "Decoded to Assets/AppIcon-1024.png"
echo "Drop this into Xcode Assets.xcassets > AppIcon > App Store slot"
