#!/usr/bin/env node

/**
 * Cordova plugin.xml to Swift Package converter
 */

const fs = require('fs').promises;
const path = require('path');
const readline = require('readline');

// CLI flags
const force = process.argv.includes('--force');
const dryRun = process.argv.includes('--dry-run');
const verbose = process.argv.includes('--verbose');
const noGitignore = process.argv.includes('--no-gitignore');

/** ANSI colors for log output */
function colorize(level, message) {
    const colors = {
        info: '\x1b[36m',    // cyan
        warn: '\x1b[33m',    // yellow
        error: '\x1b[31m',   // red
        success: '\x1b[32m', // green
        debug: '\x1b[35m'    // magenta
    };
    const reset = '\x1b[0m';
    return (colors[level] || '') + message + reset;
}

/** Unified logger with levels */
function log(level, message) {
    const prefix = {
        info: '[INFO]',
        warn: '[WARN]',
        error: '[ERROR]',
        success: '[SUCCESS]',
        debug: '[DEBUG]'
    }[level] || '';
    if (level === 'debug' && !verbose) return;
    console.log(colorize(level, `${prefix} ${message}`));
}

/** Ask user confirmation */
function confirmAction(message, defaultYes = true) {
    if (force) return Promise.resolve(true);
    return new Promise((resolve) => {
        const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
        const suffix = defaultYes ? ' (Y/n): ' : ' (y/N): ';
        rl.question(message + suffix, (answer) => {
            rl.close();
            const normalized = answer.trim().toLowerCase();
            if (!normalized) return resolve(defaultYes);
            resolve(normalized === 'y' || normalized === 'yes');
        });
    });
}

/**
 * Very naive XML parser only for plugin.xml structure
 * Extracts plugin id and <pod> dependencies
 */
function parsePluginXml(content) {
    const obj = { plugin: {} };

    // extract plugin id
    const pluginIdMatch = content.match(/<plugin[^>]*\s+id="([^"]+)"/i);
    if (pluginIdMatch) obj.plugin['@_id'] = pluginIdMatch[1];

    // extract pods
    const pods = [];
    const podRegex = /<pod\s+name="([^"]+)"\s+spec="([^"]+)"\s*\/>/g;
    let match;
    while ((match = podRegex.exec(content)) !== null) {
        pods.push({ '@_name': match[1], '@_spec': match[2] });
    }
    if (pods.length > 0) {
        obj.plugin.podspec = { pods };
    }

    return { 
        name: obj.plugin['@_id'] || 'Unknown',
        dependencies: pods.map(p => `${p['@_name']} (${p['@_spec']})`),
        parsed: obj,
        raw: content // keep original XML string for later rewriting
    };
}

/**
 * Build updated plugin.xml string
 */
function buildPluginXml(meta) {
    let xml = meta.raw;

    // remove <podspec> if necessary
    if (!meta.parsed.plugin.podspec) {
        xml = xml.replace(/<podspec>[\s\S]*?<\/podspec>/, '');
    }

    // ensure iOS platform has package="swift"
    xml = xml.replace(
        /<platform\s+name="ios"([^>]*)>/,
        (m, attrs) => m.includes('package=') ? m : `<platform name="ios"${attrs} package="swift">`
    );

    return xml;
}

/**
 * Generate a Package.swift template
 */
function generatePackageSwift(meta) {
    const packageDependencies = [
        '        .package(url: "https://github.com/apache/cordova-ios.git", branch: "master")',
        ...meta.dependencies.map(dep => `        // ${dep}`)
    ];

    const targetDependencies = [
        '                .product(name: "Cordova", package: "cordova-ios")',
        ...meta.dependencies.map(dep => `                // ${dep}`)
    ];

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

/** Remove podspec section from parsed object */
function removePodspec(plugin) {
    if (plugin.plugin?.podspec) {
        delete plugin.plugin.podspec;
        return true;
    }
    return false;
}

/** Update .gitignore with SwiftPM build artifacts */
async function updateGitignore(targetDir) {
    const gitignorePath = path.join(targetDir, '.gitignore');
    let currentContent = '';
    try {
        currentContent = await fs.readFile(gitignorePath, 'utf8');
    } catch (_) {}

    let lines = currentContent.split(/\r?\n/).filter(Boolean);
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
        const newContent = lines.join('\n') + '\n';
        if (!dryRun) {
            await fs.writeFile(gitignorePath, newContent);
        }
        log('success', `${gitignorePath} updated with .build/ and Package.resolved`);
    } else {
        log('info', `.gitignore already contains .build/ and Package.resolved`);
    }
}

/** Main entry */
(async () => {
    try {
        let pluginXmlPath;
        if (process.argv.length < 3 || process.argv[2].startsWith('--')) {
            pluginXmlPath = path.resolve(process.cwd(), 'plugin.xml');
            log('info', `Using plugin.xml at ${pluginXmlPath}`);
        } else {
            pluginXmlPath = path.resolve(process.argv[2]);
            log('info', `Using plugin.xml at ${pluginXmlPath}`);
        }

        let pluginXmlContent;
        try {
            pluginXmlContent = await fs.readFile(pluginXmlPath, 'utf8');
        } catch (err) {
            log('error', `Failed to read plugin.xml: ${err.message}`);
            process.exit(1);
        }

        const meta = parsePluginXml(pluginXmlContent);
        log('info', `Plugin name: ${meta.name}`);
        if (meta.dependencies.length) {
            log('info', `Dependencies found: ${meta.dependencies.join(', ')}`);
        } else {
            log('warn', 'No <pod> dependencies found.');
        }

        // Generate Package.swift
        const packageSwift = generatePackageSwift(meta);
        const outPath = path.join(path.dirname(pluginXmlPath), 'Package.swift');
        let writePkg = true;
        if (await fs.stat(outPath).catch(() => false)) {
            if (!await confirmAction(`Package.swift already exists. Overwrite?`)) {
                log('info', 'Skipping overwrite of Package.swift');
                writePkg = false;
            }
        }
        if (writePkg) {
            if (dryRun) {
                log('info', `[DRY-RUN] Package.swift would be written at ${outPath}`);
            } else {
                await fs.writeFile(outPath, packageSwift);
                log('success', `Package.swift generated at ${outPath}`);
            }
        }

        // Update .gitignore
        if (!noGitignore) {
            if (await confirmAction(`Update .gitignore in ${path.dirname(outPath)}?`)) {
                if (dryRun) {
                    log('info', `[DRY-RUN] .gitignore would be updated in ${path.dirname(outPath)}`);
                } else {
                    await updateGitignore(path.dirname(outPath));
                }
            }
        }

        // Modify plugin.xml if needed
        let changed = false;
        if (meta.parsed.plugin.podspec) {
            if (await confirmAction('Remove <podspec> section from plugin.xml?')) {
                changed = removePodspec(meta.parsed) || changed;
                log('success', '<podspec> removed from plugin.xml');
            }
        }

        if (changed) {
            const newXml = buildPluginXml(meta);
            if (dryRun) {
                log('info', `[DRY-RUN] plugin.xml would be updated`);
            } else {
                await fs.writeFile(pluginXmlPath, newXml);
                log('success', 'plugin.xml updated');
            }
        }

        // Final notes
        if (!dryRun && meta.dependencies.length > 0) {
            console.log('\n' + '='.repeat(60));
            console.log('[IMPORTANT] Manual steps required:');
            console.log('CocoaPods dependencies were added as comments in Package.swift.');
            console.log('Convert them manually to Swift Package Manager equivalents.');
            console.log('='.repeat(60));
        } else if (!dryRun) {
            log('success', 'Conversion completed! Your Package.swift is ready.');
        }
    } catch (err) {
        log('error', `Unexpected error: ${err.message}`);
        process.exit(1);
    }
})();
