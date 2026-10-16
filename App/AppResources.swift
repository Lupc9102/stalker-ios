import UIKit

enum AppResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }
    static var backdrop: UIImage? {
        guard let url = bundle.url(forResource: "ZoneBackdrop", withExtension: "jpg") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
