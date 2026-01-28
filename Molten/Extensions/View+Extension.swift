//
//  View+Extension.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 21/12/2023.
//

import SwiftUI

// MARK: - Conditional View
extension View {
    /// Whether the view should be empty.
    /// - Parameter bool: Set to `true` to show the view (return EmptyView instead).
    func showIf(_ bool: Bool) -> some View {
        modifier(ConditionalView(show: [bool]))
    }
    
    /// returns a original view only if all conditions are true
    func showIf(_ conditions: Bool...) -> some View {
        modifier(ConditionalView(show: conditions))
    }
}

struct ConditionalView: ViewModifier {
    
    let show: [Bool]
    
    func body(content: Content) -> some View {
        Group {
            if show.filter({ $0 == false }).count == 0 {
                content
            } else {
                EmptyView()
            }
        }
    }
}


extension View {
    /// Usually you would pass  `@Environment(\.displayScale) var displayScale`
    @MainActor func render(scale displayScale: CGFloat = 1.0) -> PlatformImage? {
        let renderer = ImageRenderer(content: self)
        
        renderer.scale = displayScale
        
#if os(iOS) || os(visionOS)
        let image = renderer.uiImage
#elseif os(macOS)
        let image = renderer.nsImage
#endif
        
        return image
    }
}

extension View {
    /// Applies the given transform if the given condition evaluates to `true`.
    /// - Parameters:
    ///   - condition: The condition to evaluate.
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the condition is `true`.
    /// https://www.avanderlee.com/swiftui/conditional-view-modifier/
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Legacy Enchanted gradient (kept for compatibility)
struct GradientForegroundStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.foregroundStyle(
            LinearGradient(
                colors: [Color(hex: "4285f4"), Color(hex: "9b72cb"), Color(hex: "d96570"), Color(hex: "#d96570")],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

struct MovingGradientForegroundStyle: ViewModifier {
    @State private var animateGradient = false

    func body(content: Content) -> some View {
        content.overlay(
            LinearGradient(
                colors: [Color(hex: "4285f4"), Color(hex: "9b72cb")],
                startPoint: animateGradient ? .leading : .trailing,
                endPoint: animateGradient ? .trailing : .leading
            )
            .animation(Animation.linear(duration: 3).repeatForever(autoreverses: false), value: animateGradient)
        )
        .mask(content)
        .onAppear {
            animateGradient = true
        }
    }
}

// MARK: - Molten Style (distinctive warm metallic gradient)
/// A molten metal-inspired gradient with warm amber, orange, and gold tones
struct MoltenForegroundStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.foregroundStyle(
            LinearGradient(
                colors: [
                    Color(hex: "FF6B35"),  // Warm orange
                    Color(hex: "F7C35F"),  // Golden amber
                    Color(hex: "FFB347"),  // Light orange/gold
                    Color(hex: "E85D04")   // Deep burnt orange
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

/// Animated molten effect with a flowing heat shimmer
struct MoltenAnimatedStyle: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "DC2F02"), location: 0.0),      // Deep red
                        .init(color: Color(hex: "E85D04"), location: 0.25),     // Burnt orange
                        .init(color: Color(hex: "F7C35F"), location: 0.5),      // Golden amber
                        .init(color: Color(hex: "FFBA08"), location: 0.75),     // Bright gold
                        .init(color: Color(hex: "FF6B35"), location: 1.0)       // Warm orange
                    ],
                    startPoint: UnitPoint(x: phase, y: 0),
                    endPoint: UnitPoint(x: phase + 1, y: 1)
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: true)) {
                    phase = 0.5
                }
            }
    }
}

/// Molten glow effect - adds a subtle warm glow behind text
struct MoltenGlowStyle: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            // Glow layer
            content
                .foregroundStyle(Color(hex: "FF6B35").opacity(0.6))
                .blur(radius: 8)
            
            // Main gradient layer
            content
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(hex: "FFBA08"),  // Bright gold
                            Color(hex: "F7C35F"),  // Golden amber
                            Color(hex: "FF6B35")   // Warm orange
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}


extension View {
    func enchantify() -> some View {
        modifier(GradientForegroundStyle())
    }
    
    func enchantifyMoving() -> some View {
        self.modifier(MovingGradientForegroundStyle())
    }
    
    /// Applies the Molten gradient style (warm amber/orange/gold)
    func moltenify() -> some View {
        modifier(MoltenForegroundStyle())
    }
    
    /// Applies the animated Molten gradient with flowing heat effect
    func moltenifyAnimated() -> some View {
        modifier(MoltenAnimatedStyle())
    }
    
    /// Applies the Molten style with a warm glow effect
    func moltenifyGlow() -> some View {
        modifier(MoltenGlowStyle())
    }
}


extension View {
    /// Adds an underlying hidden button with a performing action that is triggered on pressed shortcut
    /// - Parameters:
    ///   - key: Key equivalents consist of a letter, punctuation, or function key that can be combined with an optional set of modifier keys to specify a keyboard shortcut.
    ///   - modifiers: A set of key modifiers that you can add to a gesture.
    ///   - perform: Action to perform when the shortcut is pressed
    public func onKeyboardShortcut(key: KeyEquivalent, modifiers: EventModifiers = .command, perform: @escaping () -> ()) -> some View {
        ZStack {
            Button("") {
                perform()
            }
            .hidden()
            .keyboardShortcut(key, modifiers: modifiers)
            
            self
        }
    }
}
