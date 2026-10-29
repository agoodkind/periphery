import AppIntents
import Foundation
import SwiftUI

public struct SPMLocalizedView: View {
    @State private var isOn = false
    private let isPrimary = true

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("mac_section_key") {
                    Button("mac_button_key") {}
                    Label("mac_label_key", systemImage: "mac_label_system_image_key")
                    Toggle("mac_toggle_key", isOn: $isOn)
                    Text("mac_text_key")
                    Text(isPrimary ? "mac_ternary_true_key" : "mac_ternary_false_key")
                    SPMCustomRow(title: "mac_custom_init_key")
                    SPMCustomRow()
                }
            }
            .navigationTitle("mac_navigation_title_key")
        }
    }
}

public struct SPMCustomRow: View {
    let title: LocalizedStringKey

    public init(title: LocalizedStringKey = "mac_default_value_key") {
        self.title = title
    }

    public var body: some View {
        Text(title)
    }
}

public enum SPMLocalizedStrings {
    public static let annotatedProperty: LocalizedStringResource = "mac_annotated_property_key"

    public static var returnedResource: LocalizedStringResource {
        "mac_returned_resource_key"
    }

    public static func resource(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }

    public static func localizationValue(_ value: String.LocalizationValue) -> String {
        String(localized: value)
    }

    public static func plain(_ value: String) -> String {
        value
    }

    public static func variadic(_ values: LocalizedStringResource...) -> Int {
        values.count
    }

    public static func use() {
        _ = resource("mac_resource_param_key")
        _ = localizationValue("mac_localization_value_param_key")
        _ = plain("mac_plain_string_param_key")
        _ = variadic("mac_variadic_key", "mac_variadic_key")
    }
}
