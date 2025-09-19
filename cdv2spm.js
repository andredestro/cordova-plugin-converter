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

// Ensure .build/ and Package.resolved are in .gitignore
function updateGitignore() {
    const gitignorePath = path.join(process.cwd(), '.gitignore');
    let lines = [];
    if (fs.existsSync(gitignorePath)) {
        lines = fs.readFileSync(gitignorePath, 'utf8').split(/\r?\n/);
    }
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
        fs.writeFileSync(gitignorePath, filtered.join('\n'));
        console.log('.gitignore updated with .build/ and Package.resolved');
    }
}


let pluginXmlPath;
if (process.argv.length < 3) {
    // Default to plugin.xml in the current working directory
    pluginXmlPath = path.resolve(process.cwd(), 'plugin.xml');
    if (!fs.existsSync(pluginXmlPath)) {
        console.error('plugin.xml not found in the current directory.');
        console.error('Usage: node pod2spm.js [path/to/plugin.xml]');
        process.exit(1);
    }
    console.log('No plugin.xml path provided, using', pluginXmlPath);
} else {
    pluginXmlPath = process.argv[2];
}

updateGitignore();

const pluginXmlContent = fs.readFileSync(pluginXmlPath, 'utf8');
const meta = parsePluginXml(pluginXmlContent);
const swiftPkg = generatePackageSwift(meta);

const outPath = path.join(path.dirname(pluginXmlPath), 'Package.swift');
fs.writeFileSync(outPath, swiftPkg);
console.log(`Package.swift generated at ${outPath}`);
