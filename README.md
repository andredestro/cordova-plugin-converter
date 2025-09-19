# Cordova Plugin Converter

A Node.js script to convert a Cordova `plugin.xml` into a Swift Package Manager `Package.swift` for iOS plugins.

## Features
- Parses the plugin ID and CocoaPods dependencies from your `plugin.xml`
- Generates a basic `Package.swift` file for SwiftPM integration with cordova-ios dependency
- Automatically updates (or creates) `.gitignore` to include `.build/` and `Package.resolved`
- Optionally removes the `<podspec>` section from `plugin.xml` after conversion
- Interactive confirmation prompts for file overwrites and modifications
- Comprehensive CLI options for automation and debugging

## Usage

### Basic Usage
```sh
node cdv2spm.js [path/to/plugin.xml] [options]
```

If you omit the path, it will look for `plugin.xml` in the current directory.

### Command Line Options
- `--force` - Overwrite files without confirmation prompts
- `--dry-run` - Show what would be done without actually writing files
- `--verbose` - Show debug information during execution
- `--no-gitignore` - Skip updating the .gitignore file
- `--help, -h` - Show help message and exit

### Examples

**Basic conversion with prompts:**
```sh
node cdv2spm.js
```

**Force overwrite without prompts:**
```sh
node cdv2spm.js plugin.xml --force
```

**Preview changes without writing files:**
```sh
node cdv2spm.js plugin.xml --dry-run --verbose
```

**Convert specific plugin.xml and skip .gitignore update:**
```sh
node cdv2spm.js path/to/my-plugin.xml --no-gitignore
```

### Remote Execution
You can run the script directly from GitHub without cloning:

```sh
curl -sL https://raw.githubusercontent.com/andredestro/cordova-plugin-converter/main/cdv2spm.js | node - path/to/plugin.xml
```

## What It Does

1. **Parses plugin.xml** - Extracts plugin ID and CocoaPods dependencies from `<podspec>` sections
2. **Generates Package.swift** - Creates a SwiftPM package file with:
   - Cordova-ios as a package dependency
   - Your plugin as a library target
   - CocoaPods dependencies as comments for manual adaptation
3. **Updates .gitignore** - Adds Swift Package Manager build artifacts to ignore list
4. **Cleans plugin.xml** - Optionally removes `<podspec>` sections after conversion

## Generated Package.swift Structure

The script generates a Package.swift with:
- iOS 14+ platform requirement
- cordova-ios package dependency from Apache's GitHub repository
- Your plugin as a library target with source path pointing to `src/ios`
- CocoaPods dependencies included as comments for manual review

## Requirements
- Node.js 14 or newer

## Interactive Mode

By default, the script runs in interactive mode and will ask for confirmation before:
- Overwriting existing `Package.swift` files
- Updating `.gitignore` 
- Removing `<podspec>` sections from `plugin.xml`

Use `--force` to skip all confirmations for automated workflows.

## License
MIT
