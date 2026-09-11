import SwiftUI

struct BendySettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings: AppSettings
    private let setEnabled: (Bool) -> Void
    private let pause: () -> Void
    private let quit: () -> Void
    private let previewSound: () -> Void

    init(
        settings: AppSettings,
        setEnabled: @escaping (Bool) -> Void,
        pause: @escaping () -> Void,
        quit: @escaping () -> Void,
        previewSound: @escaping () -> Void
    ) {
        _settings = ObservedObject(wrappedValue: settings)
        self.setEnabled = setEnabled
        self.pause = pause
        self.quit = quit
        self.previewSound = previewSound
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 13) {
                    BendyMacBookPreview(
                        angle: settings.effectiveAngle,
                        style: settings.style,
                        perspective: settings.perspective,
                        blur: settings.blur,
                        shadow: settings.shadow
                    )
                    .frame(height: 159)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Foldly preview")
                    .accessibilityValue("\(settings.style.rawValue) style at \(Int(settings.effectiveAngle.rounded())) degrees")

                    statusCard
                    stylePicker
                    lidControls
                    finishControls

                    HStack {
                        Toggle(isOn: $settings.sound) {
                            Label("Fold finish sound", systemImage: settings.sound ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityHint("Plays a soft swish and glassy finish when the desktop unfolds")
                        Button(action: previewSound) { Label("Preview", systemImage: "play.fill") }
                            .controlSize(.small)
                            .accessibilityLabel("Preview fold sound")
                            .help("Listen without enabling screen capture")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
            }

            actionBar
        }
        .frame(width: 520, height: 650)
        .background(Color(red: 0.969, green: 0.973, blue: 0.981))
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.2))
                Image(systemName: "macbook")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 47, height: 47)

            VStack(alignment: .leading, spacing: 2) {
                Text("Foldly")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                Text("Give it a fold.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Toggle("Enable", isOn: Binding(
                    get: { settings.enabled },
                    set: { setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12.5, weight: .semibold))
                .accessibilityLabel("Enable Foldly")
                .accessibilityHint("Starts screen capture immediately and keeps it on until paused or disabled")

                Text("Folds below 105° · capture while enabled")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .frame(height: 82)
        .background(
            LinearGradient(
                colors: [Color(red: 0.55, green: 0.52, blue: 0.86), Color(red: 0.40, green: 0.37, blue: 0.70)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.3), radius: 3)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(settings.sensorStatus)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(BendyPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let error = settings.lastError, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(red: 0.70, green: 0.31, blue: 0.26))
                        .fixedSize(horizontal: false, vertical: true)
                } else if settings.currentSensorAngle == nil {
                    Text("Use the manual angle if this Mac does not expose a lid sensor.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(BendyPalette.muted)
                } else if let angle = settings.currentSensorAngle {
                    Text("Live lid angle: \(Int(angle.rounded()))°")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(BendyPalette.muted)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(BendyPalette.lilac.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sensor status")
    }

    private var statusColor: Color {
        if settings.lastError != nil { return Color(red: 0.82, green: 0.39, blue: 0.31) }
        if settings.currentSensorAngle != nil { return Color(red: 0.27, green: 0.64, blue: 0.42) }
        return Color(red: 0.88, green: 0.60, blue: 0.22)
    }

    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Bend style")
            HStack(spacing: 7) {
                ForEach(BendyStyle.allCases) { style in
                    Button {
                        settings.style = style
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(styleColor(style))
                                .frame(width: 8, height: 8)
                            Text(style.rawValue)
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .foregroundStyle(settings.style == style ? BendyPalette.lavenderDark : BendyPalette.muted)
                        .background(
                            settings.style == style ? BendyPalette.lilac : Color.white,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(settings.style == style ? BendyPalette.lavender.opacity(0.58) : BendyPalette.line, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(style.rawValue) bend style")
                    .accessibilityAddTraits(settings.style == style ? .isSelected : [])
                }
            }
        }
    }

    private var lidControls: some View {
        VStack(spacing: 9) {
            HStack {
                Toggle("Follow MacBook lid", isOn: $settings.followLid)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 12.5, weight: .medium))
                    .accessibilityHint("Uses the lid sensor when available")
                Spacer()
                Text(settings.followLid ? "Sensor" : "Manual")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BendyPalette.lavenderDark)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(BendyPalette.lilac, in: Capsule())
            }

            if !settings.followLid {
                LabeledBendySlider(
                    title: "Lid angle",
                    value: $settings.manualAngle,
                    range: 15...120,
                    displayValue: "\(Int(settings.manualAngle.rounded()))°"
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(BendyPalette.line, lineWidth: 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: settings.followLid)
    }

    private var finishControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel("Finish")
            LabeledBendySlider(title: "Perspective", value: $settings.perspective, range: 0...1, displayValue: percent(settings.perspective))
            LabeledBendySlider(title: "Edge softness", value: $settings.blur, range: 0...1, displayValue: percent(settings.blur))
            LabeledBendySlider(title: "Fold shadow", value: $settings.shadow, range: 0...1, displayValue: percent(settings.shadow))
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(BendyPalette.line, lineWidth: 1))
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(settings.enabled && !settings.paused ? Color.green : BendyPalette.muted.opacity(0.6))
                    .frame(width: 7, height: 7)
                Text(settings.activityDescription)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BendyPalette.muted)
            }

            Spacer()

            Button(settings.paused ? "Resume" : "Pause", action: pause)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!settings.enabled)
                .accessibilityHint(settings.paused ? "Resumes the desktop effect" : "Temporarily stops the desktop effect")

            Button("Quit", role: .destructive, action: quit)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .frame(height: 55)
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(BendyPalette.line).frame(height: 1) }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(BendyPalette.muted)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func styleColor(_ style: BendyStyle) -> Color {
        switch style {
        case .silk: return Color(red: 0.58, green: 0.50, blue: 0.87)
        case .shade: return Color(red: 0.27, green: 0.27, blue: 0.36)
        case .frost: return Color(red: 0.62, green: 0.78, blue: 0.85)
        }
    }
}

private struct LabeledBendySlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let displayValue: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(BendyPalette.ink)
                .frame(width: 92, alignment: .leading)
            Slider(value: $value, in: range)
                .tint(BendyPalette.lavender)
                .accessibilityLabel(title)
                .accessibilityValue(displayValue)
            Text(displayValue)
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(BendyPalette.muted)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 20)
    }
}

private struct BendyMacBookPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let angle: Double
    let style: BendyStyle
    let perspective: Double
    let blur: Double
    let shadow: Double

    private var openness: Double {
        min(1, max(0, (angle - 15) / 90))
    }

    private var closure: Double { 1 - openness }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(red: 0.10, green: 0.10, blue: 0.12))

                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        LinearGradient(colors: wallpaper, startPoint: .topLeading, endPoint: .bottomTrailing)

                        Circle()
                            .fill(.white.opacity(style == .frost ? 0.27 : 0.13))
                            .frame(width: 150, height: 150)
                            .blur(radius: 18)
                            .offset(x: 72, y: -42)

                        WaveRibbon()
                            .fill(LinearGradient(colors: ribbon, startPoint: .leading, endPoint: .trailing))
                            .frame(height: geometry.size.height * 0.54)
                            .opacity(0.88)

                        LinearGradient(
                            colors: [.clear, .black.opacity(closure * (0.18 + shadow * 0.34 + (style == .shade ? 0.18 : 0)))],
                            startPoint: .bottom,
                            endPoint: .top
                        )

                        VStack(spacing: 0) {
                            HStack(spacing: 4) {
                                Circle().frame(width: 3, height: 3)
                                Text("Foldly").font(.system(size: 5.5, weight: .semibold))
                                Spacer()
                                Image(systemName: "wifi").font(.system(size: 5))
                                Text("9:41").font(.system(size: 5.5, weight: .medium))
                            }
                            .foregroundStyle(.black.opacity(0.65))
                            .padding(.horizontal, 7)
                            .frame(height: 12)
                            .background(.white.opacity(0.34))
                            Spacer()
                            HStack(spacing: 3) {
                                ForEach(0..<6, id: \.self) { item in
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(dockColor(item))
                                        .frame(width: 15, height: 15)
                                }
                            }
                            .padding(3)
                            .background(.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .padding(.bottom, 4)
                        }
                    }
                    .frame(height: geometry.size.height, alignment: .bottom)
                    .modifier(FoldPreviewBlur(radius: style == .frost ? closure * (0.8 + blur * 3.5) : closure * blur * 0.35, closure: closure))
                    .brightness(-closure * (style == .shade ? 0.24 : 0.06))
                    .rotation3DEffect(.degrees(-closure * 12.075 * max(0.25, perspective)), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
                    .clipped()
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: angle)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: style)
                }
                .padding(7)

                Capsule()
                    .fill(Color.black)
                    .frame(width: 44, height: 7)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 4)
            }
            .frame(width: 314, height: 137)
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 1))
            .rotation3DEffect(.degrees(-closure * 74), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.12)
            .shadow(color: .black.opacity(0.14 + closure * shadow * 0.12), radius: 13, y: 9)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: angle)

            ZStack(alignment: .top) {
                BendyBaseShape()
                    .fill(LinearGradient(colors: [.white, Color(red: 0.69, green: 0.70, blue: 0.73)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 358, height: 18)
                Capsule()
                    .fill(.black.opacity(0.22))
                    .frame(width: 58, height: 3)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var wallpaper: [Color] {
        switch style {
        case .silk: return [Color(red: 0.67, green: 0.60, blue: 0.92), Color(red: 0.43, green: 0.39, blue: 0.72)]
        case .shade: return [Color(red: 0.36, green: 0.32, blue: 0.51), Color(red: 0.17, green: 0.25, blue: 0.35)]
        case .frost: return [Color(red: 0.72, green: 0.81, blue: 0.91), Color(red: 0.52, green: 0.58, blue: 0.80)]
        }
    }

    private var ribbon: [Color] {
        switch style {
        case .silk: return [Color(red: 0.97, green: 0.76, blue: 0.76), Color(red: 0.69, green: 0.48, blue: 0.76)]
        case .shade: return [Color(red: 0.65, green: 0.42, blue: 0.62), Color(red: 0.28, green: 0.37, blue: 0.51)]
        case .frost: return [Color(red: 0.90, green: 0.89, blue: 0.98), Color(red: 0.61, green: 0.74, blue: 0.85)]
        }
    }

    private func dockColor(_ item: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.35, green: 0.66, blue: 0.91),
            Color(red: 0.94, green: 0.34, blue: 0.42),
            Color(red: 0.98, green: 0.73, blue: 0.32),
            Color(red: 0.47, green: 0.73, blue: 0.52),
            Color(red: 0.64, green: 0.44, blue: 0.83),
            Color(red: 0.31, green: 0.61, blue: 0.84)
        ]
        return colors[item % colors.count]
    }
}

private struct FoldPreviewBlur: ViewModifier {
    let radius: Double
    let closure: Double

    func body(content: Content) -> some View {
        let profile = FoldBlurProfile(closure: closure)
        // Sample the same smooth profile as Core Image, including its nonzero
        // hinge strength once the gradient extends below the display.
        let mask = LinearGradient(stops: (0...16).map { step in
            let position = Double(step) / 16
            return .init(color: .white.opacity(profile.strength(at: 1 - position)), location: position)
        }, startPoint: .top, endPoint: .bottom)
        content.overlay {
            content.blur(radius: radius, opaque: true).mask(mask)
        }
    }
}

private struct WaveRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.62))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.56, y: rect.height * 0.35),
            control1: CGPoint(x: rect.width * 0.18, y: rect.height * 0.20),
            control2: CGPoint(x: rect.width * 0.36, y: rect.height * 0.77)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.12),
            control1: CGPoint(x: rect.width * 0.75, y: rect.height * 0.02),
            control2: CGPoint(x: rect.width * 0.83, y: rect.height * 0.54)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct BendyBaseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.08, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.width * 0.92, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.68))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.95, y: rect.height * 0.85), control: CGPoint(x: rect.maxX, y: rect.height * 0.85))
        path.addLine(to: CGPoint(x: rect.width * 0.05, y: rect.height * 0.85))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.height * 0.68), control: CGPoint(x: rect.minX, y: rect.height * 0.85))
        path.closeSubpath()
        return path
    }
}

private enum BendyPalette {
    static let ink = Color(red: 0.15, green: 0.15, blue: 0.17)
    static let muted = Color(red: 0.49, green: 0.49, blue: 0.53)
    static let line = Color(red: 0.88, green: 0.88, blue: 0.91)
    static let lilac = Color(red: 0.93, green: 0.93, blue: 0.98)
    static let lavender = Color(red: 0.50, green: 0.47, blue: 0.82)
    static let lavenderDark = Color(red: 0.34, green: 0.31, blue: 0.60)
}
