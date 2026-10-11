import ApplicationServices

/// Thin wrapper over `AXUIElement` for reading attributes of UI elements in other apps.
///
/// Every call here is synchronous IPC into the target process, so use it off the main thread.
struct AXElement {
    let ref: AXUIElement

    static func systemWide() -> AXElement {
        AXElement(ref: AXUIElementCreateSystemWide())
    }

    static func application(pid: pid_t) -> AXElement {
        AXElement(ref: AXUIElementCreateApplication(pid))
    }

    /// Hit-tests the accessibility tree at a point in global display coordinates (top-left origin).
    func element(at point: CGPoint) -> (AXElement?, AXError) {
        var hit: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(ref, Float(point.x), Float(point.y), &hit)
        return (hit.map(AXElement.init), error)
    }

    var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(ref, &pid) == .success ? pid : nil
    }

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var title: String? { string(kAXTitleAttribute) }
    var label: String? { string(kAXDescriptionAttribute) }
    var value: String? { string(kAXValueAttribute) }

    var url: URL? {
        guard let value = attribute(kAXURLAttribute) else { return nil }
        // Usually a CFURL, but some apps hand back a string.
        return (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
    }

    var parent: AXElement? { element(kAXParentAttribute) }
    var focusedElement: AXElement? { element(kAXFocusedUIElementAttribute) }

    var windows: [AXElement] {
        guard let value = attribute(kAXWindowsAttribute), let array = value as? [AnyObject] else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? AXElement(ref: item as! AXUIElement) : nil
        }
    }

    var children: [AXElement] {
        guard let value = attribute(kAXChildrenAttribute), let array = value as? [AnyObject] else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? AXElement(ref: item as! AXUIElement) : nil
        }
    }

    /// Up to `limit` graphics in a web page under this element, in page order, from the engine's own
    /// search. WebKit's graphics are images; Chromium's are images and videos.
    func graphics(limit: Int) -> [AXElement] {
        let query: [String: Any] = ["AXSearchKey": "AXGraphicSearchKey", "AXDirection": "AXDirectionNext", "AXResultsLimit": limit]
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(ref, "AXUIElementsForSearchPredicate" as CFString, query as CFDictionary, &value) == .success,
              let array = value as? [AnyObject] else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? AXElement(ref: item as! AXUIElement) : nil
        }
    }

    /// Frame in global display coordinates (top-left origin).
    var frame: CGRect? {
        guard let origin: CGPoint = axValue(kAXPositionAttribute, type: .cgPoint),
              let size: CGSize = axValue(kAXSizeAttribute, type: .cgSize) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    func set(_ name: String, to value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(ref, name as CFString, value)
    }

    func setMessagingTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(ref, seconds)
    }

    // MARK: - Raw attribute access

    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ name: String) -> String? {
        attribute(name) as? String
    }

    private func element(_ name: String) -> AXElement? {
        guard let value = attribute(name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXElement(ref: value as! AXUIElement)
    }

    private func axValue<T>(_ name: String, type: AXValueType) -> T? {
        guard let value = attribute(name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        return AXValueGetValue(value as! AXValue, type, pointer) ? pointer.pointee : nil
    }
}
