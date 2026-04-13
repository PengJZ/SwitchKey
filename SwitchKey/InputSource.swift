import Foundation
import Cocoa
import Carbon

struct InputSourceInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

class InputSource: NSObject {
    private let inputSource: TISInputSource

    private init(inputSource: TISInputSource) {
        self.inputSource = inputSource
        super.init()
    }

    static func current() -> InputSource {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return InputSource(inputSource: source)
    }

    static func allSelectable() -> [InputSourceInfo] {
        let properties = [
            kTISPropertyInputSourceIsSelectCapable as String: true,
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String
        ] as CFDictionary

        guard let inputSourceListCF = TISCreateInputSourceList(properties, false) else {
            return []
        }
        let inputSourceList = inputSourceListCF.takeRetainedValue() as? [TISInputSource] ?? []

        var infos: [InputSourceInfo] = []
        for source in inputSourceList {
            if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
               let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                var name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
                
                if name.lowercased().contains("pinyin") || name.contains("拼音") {
                    name = "简体拼音"
                }

                infos.append(InputSourceInfo(id: id, name: name))
            }
        }
        return infos
    }

    static func with(_ inputSourceID: String) -> InputSource? {
        let properties = [
            kTISPropertyInputSourceIsEnabled as String: true,
            kTISPropertyInputSourceIsSelectCapable as String: true
        ] as CFDictionary

        guard let inputSourceListCF = TISCreateInputSourceList(properties, false) else {
            return nil
        }
        let inputSourceList = inputSourceListCF.takeRetainedValue() as? [TISInputSource] ?? []

        for source in inputSourceList {
            if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
                let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                if id == inputSourceID {
                    return InputSource(inputSource: source)
                }
            }
        }
        return nil
    }

    func inputSourceID() -> String {
        guard let idPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    }

    func localizedName() -> String {
        guard let namePtr = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) else { return "" }
        return Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
    }

    func icon() -> NSImage {
        if let iconRefPtr = TISGetInputSourceProperty(inputSource, kTISPropertyIconRef) {
            let iconRef = OpaquePointer(iconRefPtr)
            return NSImage(iconRef: iconRef)
        }
        if let urlPtr = TISGetInputSourceProperty(inputSource, kTISPropertyIconImageURL) {
            let url = Unmanaged<CFURL>.fromOpaque(urlPtr).takeUnretainedValue() as URL
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return NSImage()
    }

    func activate() {
        TISSelectInputSource(inputSource)
    }
}
