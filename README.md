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
# Use --force to skip interactive prompts (recommended for remote execution)
curl -sL https://raw.githubusercontent.com/andredestro/cordova-plugin-converter/main/cdv2spm.js | node - path/to/plugin.xml --force
```

**Note:** Interactive prompts don't work with piped execution. Use `--force` to automatically overwrite files, or download the script first:

```sh
# Alternative: download and run locally for interactive mode
curl -sL https://raw.githubusercontent.com/andredestro/cordova-plugin-converter/main/cdv2spm.js -o cdv2spm.js
node cdv2spm.js plugin.xml
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

## Important Limitations

### CocoaPods Dependencies
The script **cannot automatically convert CocoaPods dependencies** to Swift Package Manager equivalents. Here's why:

- **Different repositories**: CocoaPods and SPM often use different repository URLs
- **Name differences**: Package names may differ between CocoaPods and SPM
- **Availability**: Not all CocoaPods have SPM equivalents
- **Version mapping**: Version schemes may not match directly

**What the script does:**
- Extracts `<pod>` dependencies from your `plugin.xml`
- Adds them as **comments** in the generated `Package.swift`
- You must **manually** find and add the correct SPM dependencies

**Manual steps required:**
1. Review the commented dependencies in `Package.swift`
2. Search for SPM equivalents (GitHub, Swift Package Index, etc.)
3. Replace comments with actual `.package()` declarations
4. Update target dependencies accordingly
5. Test that your plugin builds correctly

### Example
If your `plugin.xml` contains:
```xml
<pod name="OSInAppBrowserLib" spec="2.2.1" />
```

The script generates:
```swift
// OSInAppBrowserLib (2.2.1)
```

You need to manually replace it with:
```swift
.package(url: "https://github.com/outsystems/OSInAppBrowserLib-iOS.git", from: "2.2.1")
```

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
