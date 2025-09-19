# Cordova plugin converter

A Node.js script to convert a Cordova `plugin.xml` into a Swift Package Manager `Package.swift` for iOS plugins.

## Features
- Parses the plugin id and CocoaPods dependencies from your `plugin.xml`.
- Generates a basic `Package.swift` file for SwiftPM integration.
- Ensures `.build/` and `Package.resolved` are ignored in your `.gitignore`.

## Usage

### 1. Run Directly with Node.js
Clone or download this repository, then run:

```sh
node cdv2spm.js path/to/plugin.xml
```
If you omit the path, it will look for `plugin.xml` in the current directory.

### 2. Run Remotely with curl
You can run the script directly from GitHub (or any raw URL) without cloning:

```sh
curl -sL https://raw.githubusercontent.com/andredestro/cordova-plugin-converter/main/cdv2spm.js | node - path/to/plugin.xml
```

## Requirements
- Node.js 14 or newer

## Output
- Generates a `Package.swift` file in the same directory as your `plugin.xml`.
- Updates (or creates) `.gitignore` to include `.build/` and `Package.resolved`.

## License
MIT
