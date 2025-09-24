import XCTest
@testable import cdv2spm

final class SPMPackageParserTests: XCTestCase {
    private var logger: Logger!
    private var parser: SPMPackageParser!
    
    override func setUp() {
        super.setUp()
        logger = Logger(verbose: false)
        parser = SPMPackageParser(logger: logger)
    }
    
    func testIsLibraryPackage() {
        let libraryPackage = """
        products: [
            .library(name: "MyLibrary", targets: ["MyLibrary"])
        ]
        """
        
        let executablePackage = """
        products: [
            .executable(name: "MyExecutable", targets: ["MyExecutable"])
        ]
        """
        
        XCTAssertTrue(parser.isLibraryPackage(libraryPackage))
        XCTAssertFalse(parser.isLibraryPackage(executablePackage))
    }
}
