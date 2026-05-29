import SwiftUI

struct PasswordGeneratorView: View {
    @Binding var generatedPassword: String
    @Environment(\.dismiss) private var dismiss

    @State private var length: Double = 16
    @State private var includeUppercase: Bool = true
    @State private var includeLowercase: Bool = true
    @State private var includeDigits: Bool = true
    @State private var includeSymbols: Bool = true
    @State private var currentPassword: String = ""
    @State private var strength: PasswordGenerator.Strength = .fair

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                generatedPasswordSection
                Divider()
                optionsSection
            }
            .navigationTitle("密码生成器")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("使用") {
                        generatedPassword = currentPassword
                        dismiss()
                    }
                    .disabled(currentPassword.isEmpty)
                }
            }
        }
        .frame(width: 420, height: 380)
        .onAppear { regenerate() }
    }

    private var generatedPasswordSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(currentPassword)
                    .font(.system(.title3, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer()

                Button {
                    ClipboardCleaner().copyToClipboard(currentPassword, clearAfter: 30)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("复制密码")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 16) {
                strengthIndicator
                Spacer()
                Button {
                    regenerate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("重新生成")
            }
            .padding(.horizontal, 4)
        }
        .padding(16)
    }

    private var strengthIndicator: some View {
        HStack(spacing: 4) {
            Text("强度:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(strength.rawValue)
                .font(.caption.weight(.medium))
                .foregroundStyle(strengthColor)
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .frame(width: 8, height: 8)
                        .foregroundStyle(index < strengthBars ? AnyShapeStyle(strengthColor) : AnyShapeStyle(.quaternary))
                }
            }
        }
    }

    private var strengthColor: Color {
        switch strength {
        case .veryWeak: return .red
        case .weak: return .orange
        case .fair: return .yellow
        case .strong: return .green
        case .veryStrong: return .blue
        }
    }

    private var strengthBars: Int {
        switch strength {
        case .veryWeak: return 1
        case .weak: return 2
        case .fair: return 3
        case .strong: return 4
        case .veryStrong: return 4
        }
    }

    private var optionsSection: some View {
        Form {
            Section {
                HStack {
                    Text("长度: \(Int(length))")
                    Spacer()
                    Stepper("", value: $length, in: 4...64)
                        .onChange(of: length) { _, _ in regenerate() }
                }
            }

            Section("字符类型") {
                Toggle("大写字母 (A-Z)", isOn: $includeUppercase)
                    .onChange(of: includeUppercase) { _, _ in regenerate() }
                Toggle("小写字母 (a-z)", isOn: $includeLowercase)
                    .onChange(of: includeLowercase) { _, _ in regenerate() }
                Toggle("数字 (0-9)", isOn: $includeDigits)
                    .onChange(of: includeDigits) { _, _ in regenerate() }
                Toggle("特殊符号 (!@#$...)", isOn: $includeSymbols)
                    .onChange(of: includeSymbols) { _, _ in regenerate() }
            }
        }
        .formStyle(.grouped)
    }

    private func regenerate() {
        let options = PasswordGenerator.Options(
            length: Int(length),
            includeUppercase: includeUppercase,
            includeLowercase: includeLowercase,
            includeDigits: includeDigits,
            includeSymbols: includeSymbols
        )
        guard options.isValid else {
            currentPassword = ""
            strength = .veryWeak
            return
        }
        currentPassword = PasswordGenerator.generate(options: options)
        strength = PasswordGenerator.strength(of: currentPassword)
    }
}