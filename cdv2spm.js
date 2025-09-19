(function showHelpAndExit() {
    if (process.argv.includes('--help') || process.argv.includes('-h')) {
        console.log(`\nUsage: node cdv2spm.js [path/to/plugin.xml] [options]\n\nOptions:\n  --force         Overwrite files without confirmation\n  --dry-run       Show what would be done, but do not write files\n  --verbose       Show debug information\n  --no-gitignore  Do not update .gitignore\n  --help, -h      Show this help message\n`);
        process.exit(0);
    }
})();
// Script to convert plugin.xml to a Package.swift scaffold
// Usage: node cdv2spm.js path/to/plugin.xml

const fs = require('fs');
const path = require('path');

function parsePluginXml(content) {
    // Extract <plugin id="...">
    const pluginTag = content.match(/<plugin\s+[^>]*?id=["']([^"']+)["']/);
    const name = pluginTag ? pluginTag[1] : 'Unknown';

    // Extract pod dependencies from <podspec> section
    // Example: <pod name="OSInAppBrowserLib" spec="2.2.1" />
    const podspecBlock = content.match(/<podspec>[\s\S]*?<\/podspec>/);
    let dependencies = [];
    if (podspecBlock) {
        const podMatches = [...podspecBlock[0].matchAll(/<pod\s+name=["']([^"']+)["']\s+spec=["']([^"']+)["'][^>]*\/>/g)];
        dependencies = podMatches.map(m => `${m[1]} (${m[2]})`);
    }

    return {
        name,
        dependencies,
    };
}

function generatePackageSwift(meta) {
    // Always add cordova-ios as a package dependency
    const packageDependencies = [
        '        .package(url: "https://github.com/apache/cordova-ios.git", branch: "master")',
        ...meta.dependencies.map(dep => `        // ${dep}`)
    ];

    // Always add Cordova as a target dependency
    const targetDependencies = [
        '                .product(name: "Cordova", package: "cordova-ios")'
    ];

    // Add pod dependencies as comments (or adapt as needed)
    targetDependencies.push(...meta.dependencies.map(dep => `                // ${dep}`));

    return `// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "${meta.name}",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "${meta.name}",
            targets: ["${meta.name}"])
    ],
    dependencies: [
${packageDependencies.join(',\n')}
    ],
    targets: [
        .target(
            name: "${meta.name}",
            dependencies: [
${targetDependencies.join(',\n')}
            ],
            path: "src/ios")
    ]
)
`;
}

// Remove <podspec> section from plugin.xml (pure, returns updated content)
function removePodspecSection(content) {
    return content.replace(/^[ \t]*<podspec>[\s\S]*?<\/podspec>[ \t]*\r?\n?/gm, '');
}

// Write updated plugin.xml if changed
function writePluginXmlIfChanged(pluginXmlPath, oldContent, newContent) {
    if (oldContent !== newContent) {
        fs.writeFileSync(pluginXmlPath, newContent);
        return true;
    }
    return false;
}

// Ensure .build/ and Package.resolved are in .gitignore
function getUpdatedGitignoreContent(currentContent) {
    let lines = currentContent ? currentContent.split(/\r?\n/) : [];
    let changed = false;
    if (!lines.includes('.build/')) {
        lines.push('.build/');
        changed = true;
    }
    if (!lines.includes('Package.resolved')) {
        lines.push('Package.resolved');
        changed = true;
    }
    if (changed) {
        const filtered = lines.filter((line, idx, arr) => line !== '' || arr[idx - 1] !== '');
        return filtered.join('\n');
    }
    return null; // no change
}

function updateGitignore(targetDir) {
    const gitignorePath = path.join(targetDir, '.gitignore');
    let existed = fs.existsSync(gitignorePath);
    let currentContent = existed ? fs.readFileSync(gitignorePath, 'utf8') : '';
    const updatedContent = getUpdatedGitignoreContent(currentContent);
    if (updatedContent) {
        fs.writeFileSync(gitignorePath, updatedContent);
        if (existed) {
            console.log('[SUCCESS] .gitignore updated with .build/ and Package.resolved');
        } else {
            console.log('[SUCCESS] .gitignore created with .build/ and Package.resolved');
        }
    } else {
        console.log('[INFO] .gitignore already contains .build/ and Package.resolved');
    }
}

const readline = require('readline');
function askUser(question) {
    return new Promise((resolve) => {
        const rl = readline.createInterface({
            input: process.stdin,
            output: process.stdout
        });
        rl.question(question, (answer) => {
            rl.close();
            resolve(answer.trim().toLowerCase());
        });
    });
}

let pluginXmlPath;

// CLI flags
const force = process.argv.includes('--force');
const dryRun = process.argv.includes('--dry-run');
const verbose = process.argv.includes('--verbose');
const noGitignore = process.argv.includes('--no-gitignore');

(async () => {
try {
    if (verbose) {
        console.log('[DEBUG] CLI flags:', { force, dryRun, verbose, noGitignore });
    }

    if (process.argv.length < 3 || (process.argv[2] && process.argv[2].startsWith('--'))) {
        // Default to plugin.xml in the current working directory
        pluginXmlPath = path.resolve(process.cwd(), 'plugin.xml');
        if (!fs.existsSync(pluginXmlPath)) {
            console.error('[ERROR] plugin.xml not found in the current directory.');
            console.error('[ERROR] Usage: node pod2spm.js [path/to/plugin.xml] [--force]');
            process.exit(1);
        }
        console.log('[INFO] No plugin.xml path provided, using', pluginXmlPath);
    } else {
        pluginXmlPath = process.argv[2];
        console.log(`[INFO] Using plugin.xml at: ${pluginXmlPath}`);
    }

    console.log('[INFO] Reading plugin.xml...');
    let pluginXmlContent;
    try {
        pluginXmlContent = fs.readFileSync(pluginXmlPath, 'utf8');
    } catch (err) {
        console.error(`[ERROR] Failed to read plugin.xml: ${err.message}`);
        process.exit(1);
    }

    console.log('[INFO] Extracting metadata from plugin.xml...');
    const meta = parsePluginXml(pluginXmlContent);
    console.log(`[INFO] Plugin name: ${meta.name}`);
    if (meta.dependencies.length > 0) {
        console.log(`[INFO] Dependencies found: ${meta.dependencies.join(', ')}`);
    } else {
        console.log('[WARN] No <pod> dependencies found.');
    }
    console.log('[INFO] Generating Package.swift...');
    const packageSwift = generatePackageSwift(meta);

    // Always resolve outPath and .gitignore relative to pluginXmlPath (absolute)
    const pluginXmlAbsPath = path.isAbsolute(pluginXmlPath) ? pluginXmlPath : path.resolve(process.cwd(), pluginXmlPath);
    const outPath = path.join(path.dirname(pluginXmlAbsPath), 'Package.swift');
    let writePackage = true;
    if (fs.existsSync(outPath) && !force) {
        const answer = await askUser(`[CONFIRM] Package.swift already exists. Overwrite? (Y/n): `);
        if (answer === 'n' || answer === 'no') {
            console.log('[INFO] Skipping Package.swift overwrite.');
            writePackage = false;
        }
    }
    if (writePackage) {
        if (dryRun) {
            console.log(`[DRY-RUN] Would write Package.swift to: ${outPath}`);
        } else {
            try {
                fs.writeFileSync(outPath, packageSwift);
                console.log(`[SUCCESS] Package.swift generated at: ${outPath}`);
            } catch (err) {
                console.error(`[ERROR] Failed to write Package.swift: ${err.message}`);
                process.exit(1);
            }
        }
    }

    if (!noGitignore) {
        const targetDir = path.dirname(outPath);
        let editGitignore = true;
        if (!force) {
            const answer = await askUser(`[CONFIRM] Update .gitignore in ${targetDir}? (Y/n): `);
            if (answer === 'n' || answer === 'no') {
                console.log('[INFO] Skipping .gitignore update.');
                editGitignore = false;
            }
        }
        if (editGitignore) {
            console.log('[INFO] Updating .gitignore...');
            if (dryRun) {
                console.log(`[DRY-RUN] Would update .gitignore in: ${targetDir}`);
            } else {
                try {
                    updateGitignore(targetDir);
                } catch (err) {
                    console.error(`[ERROR] Failed to update .gitignore: ${err.message}`);
                }
            }
        }
    } else if (verbose) {
        console.log('[DEBUG] Skipping .gitignore update due to --no-gitignore');
    }

    // Only remove <podspec> if user confirms or --force
    let removePodspec = true;
    const hasPodspec = /<podspec>[\s\S]*?<\/podspec>/.test(pluginXmlContent);
    if (hasPodspec && !force) {
        const answer = await askUser(`[CONFIRM] Remove <podspec> section from plugin.xml? (Y/n): `);
        if (answer === 'n' || answer === 'no') {
            console.log('[INFO] Skipping <podspec> removal from plugin.xml.');
            removePodspec = false;
        }
    }
    if (removePodspec) {
        if (dryRun) {
            console.log('[DRY-RUN] Would remove <podspec> section from plugin.xml');
        } else {
            try {
                const updatedContent = removePodspecSection(pluginXmlContent);
                if (writePluginXmlIfChanged(pluginXmlPath, pluginXmlContent, updatedContent)) {
                    console.log('[SUCCESS] <podspec> section removed from plugin.xml');
                } else {
                    console.log('[WARN] No <podspec> section found in plugin.xml');
                }
            } catch (err) {
                console.error(`[ERROR] Failed to update plugin.xml: ${err.message}`);
            }
        }
    }
} catch (err) {
    console.error(`[ERROR] Unexpected error: ${err.message}`);
    process.exit(1);
}
})();
