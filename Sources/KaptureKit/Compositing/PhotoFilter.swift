import Foundation

/// Filters are recorded in the recipe by name, never baked into the stored
/// frame, so changing one re-renders instead of degrading the original.
public enum PhotoFilter: String, Codable, CaseIterable, Sendable {
    case none
    case blackAndWhite
    case sepia
    case grain
    case highContrast

    public var displayName: String {
        switch self {
        case .none: "None"
        case .blackAndWhite: "Black & White"
        case .sepia: "Sepia"
        case .grain: "Grain"
        case .highContrast: "High Contrast"
        }
    }
}
