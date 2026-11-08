import SwiftUI

struct SaveddRootView: View {
    @StateObject private var store = OnboardingStore()
    @StateObject private var reminders = ProverbReminders.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var firstBrowserURL: URL?

    var body: some View {
        Group {
            if store.isComplete || visualTabsPreview {
                ContentView(initialURL: firstBrowserURL ?? referralURL(SaveddSearchEngine.homeURL))
                    .preferredColorScheme(store.preferences.appearance.colorScheme)
            } else {
                OnboardingView { signupURL in
                    firstBrowserURL = referralURL(signupURL ?? SaveddSearchEngine.homeURL)
                    store.complete()
                }
                .preferredColorScheme(.dark)
            }
        }
        .environmentObject(store)
        .environmentObject(reminders)
        .sheet(item: $reminders.presentedChapter) { chapter in
            DailyProverbView(chapter: chapter) { reminders.searchURL = $0 }
        }
        .task { await reminders.refresh() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await reminders.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await reminders.refresh() }
        }
    }

    private var visualTabsPreview: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--visual-tabs-preview")
            || ProcessInfo.processInfo.arguments.contains("--address-editor-preview")
            || ProcessInfo.processInfo.arguments.contains("--share-menu-preview")
            || ProcessInfo.processInfo.arguments.contains("--navigation-regression")
        #else
        return false
        #endif
    }

    private func referralURL(_ url: URL) -> URL {
        guard let partner = store.preferences.partner,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var query = components.queryItems ?? []
        query.removeAll { $0.name == "ref" }
        query.append(URLQueryItem(name: "ref", value: partner.pubkey))
        components.queryItems = query
        return components.url ?? url
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: OnboardingStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var headingFocused: Bool
    @StateObject private var directory = PartnerDirectory()
    @State private var step = 0
    let onFinish: (URL?) -> Void

    private let steps = ["Welcome", "Your invitation", "Your preferences", "Daily wisdom", "Your account"]

    init(onFinish: @escaping (URL?) -> Void) {
        self.onFinish = onFinish
        #if DEBUG
        // Simulator screenshots can open each real screen without test-only
        // partners, simulated accounts, or changing the release experience.
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--onboarding-preview-step"),
           args.indices.contains(index + 1), let value = Int(args[index + 1]), (0...4).contains(value) {
            _step = State(initialValue: value)
        }
        #endif
    }

    var body: some View {
        ZStack {
            OnboardingBackground()
            VStack(spacing: 0) {
                HStack {
                    if step > 0 {
                        Button { move(to: step - 1) } label: {
                            Image(systemName: "chevron.left").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Back")
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                    Spacer()
                    Text("SAVEDD").font(.system(.subheadline, design: .serif)).tracking(3)
                    Spacer()
                    Text("\(step + 1) / \(steps.count)").font(.caption.monospacedDigit()).frame(width: 44, height: 44)
                }
                .foregroundStyle(SaveddBrand.muted)

                HStack(spacing: 6) {
                    ForEach(0..<steps.count) { index in
                        Capsule().fill(index <= step ? SaveddBrand.gold : SaveddBrand.border).frame(height: 3)
                    }
                }
                .padding(.horizontal, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step + 1) of \(steps.count): \(steps[step])")

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if step == 0 {
                            welcome
                        } else {
                            heading
                            switch step {
                            case 1: PartnerPicker(directory: directory)
                            case 2: SaveddPreferencesForm()
                            case 3: ProverbReminderSetup(onContinue: { move(to: 4) })
                            default: account
                            }
                        }
                    }
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 8)
                    .padding(.top, 32)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                    .id(step)
                }
                .scrollDismissesKeyboard(.interactively)

                actions
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 640)
        }
        .foregroundStyle(SaveddBrand.foreground)
        .tint(SaveddBrand.gold)
        .task { directory.loadIfNeeded() }
        .onDisappear { directory.stop() }
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(SaveddBrand.gold.opacity(0.07))
                    .overlay(Circle().stroke(SaveddBrand.gold.opacity(0.24), lineWidth: 1))
                SaveddMark().fill(SaveddBrand.gold).padding(20)
            }
            .frame(width: 128, height: 128)
            .accessibilityHidden(true)
            .padding(.top, 24)

            VStack(spacing: 12) {
                Text("SAVEDD")
                    .font(.system(size: 48, weight: .medium, design: .serif)).tracking(7)
                    .minimumScaleFactor(0.7).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)
                Text("Seek, and ye shall find.")
                    .font(.system(.title2, design: .serif).italic())
                    .foregroundStyle(SaveddBrand.gold)
                Text("MATTHEW 7:7").font(.caption2).tracking(3).foregroundStyle(SaveddBrand.muted)
            }
            VStack(spacing: 12) {
                Text("A better place to search.")
                    .font(.system(.title, design: .serif))
                Text("Everyday search, informed by Christian values. Make Savedd feel like yours in a few simple steps.")
                    .font(.body).foregroundStyle(SaveddBrand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 16)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(step == 1 ? "Who introduced you?" : step == 2 ? "Make yourself at home." : step == 3 ? "A little wisdom, every day." : "Keep your settings with you.")
                .font(.system(.largeTitle, design: .serif))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            Text(step == 1 ? "Find the person or community who shared Savedd with you. This step is optional."
                 : step == 2 ? "Choose how you like to search. You can change these anytime in Settings."
                 : step == 3 ? "Start a daily rhythm with Proverbs. Choose a time for a gentle reminder, or skip for now."
                 : "An account will let you save your preferences beyond this device.")
                .foregroundStyle(SaveddBrand.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Your choices, ready to go", systemImage: "checkmark.circle")
                    .font(.headline).foregroundStyle(SaveddBrand.gold)
                summary("Appearance", value: store.preferences.appearance.title)
                summary("Search language", value: SaveddPreferencesForm.languageName(store.preferences.language))
                summary("Privacy Mode", value: store.preferences.privacyMode ? "On" : "Off")
                if let partner = store.preferences.partner {
                    summary("Introduced by", value: partner.name)
                } else if !store.preferences.referralCode.isEmpty {
                    summary("Code saved", value: store.preferences.referralCode)
                }
            }
            .padding(20)
            .background(SaveddBrand.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(SaveddBrand.border))

            Label("Your preferences are already saved on this device.", systemImage: "iphone")
                .font(.subheadline).foregroundStyle(SaveddBrand.muted)
                .fixedSize(horizontal: false, vertical: true)
            if SaveddAccountConfiguration.signupURL == nil {
                Text("Email sign-up is coming soon. You can start searching now and create an account later.")
                    .font(.subheadline).foregroundStyle(SaveddBrand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func summary(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).foregroundStyle(SaveddBrand.muted)
            Spacer(minLength: 0)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 6) {
            if step == 4 {
                Button { onFinish(SaveddAccountConfiguration.signupURL) } label: {
                    Label("Create an account", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(SaveddAccountConfiguration.signupURL == nil)
                Button("Continue without an account") { onFinish(nil) }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else if step != 3 {
                Button {
                    if step == 1 { resolveReferral() }
                    move(to: step + 1)
                } label: {
                    HStack {
                        Text(step == 0 ? "Get started" : "Continue")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(step == 1 && !validReferralInput)
                if step == 1 {
                    Button("Skip for now") {
                        store.preferences.referralCode = ""
                        store.preferences.partner = nil
                        move(to: 2)
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 48)
                } else {
                    Text(step == 0 ? "A few choices. Then you’re ready to search." : "Saved on this device. Always yours to change.")
                        .font(.caption).foregroundStyle(SaveddBrand.muted)
                        .multilineTextAlignment(.center).padding(.vertical, 12)
                }
            }
        }
    }

    private var validReferralInput: Bool {
        let code = store.preferences.referralCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty || store.preferences.partner != nil ||
            code.range(of: "^[A-Za-z0-9][A-Za-z0-9-]{1,31}$", options: .regularExpression) != nil
    }

    private func resolveReferral() {
        let code = store.preferences.referralCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if store.preferences.partner == nil {
            store.preferences.partner = directory.partners.first { $0.slug == code }
        }
        store.preferences.referralCode = store.preferences.partner?.slug ?? code
    }

    private func move(to next: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = next }
        headingFocused = true
    }
}

private struct PartnerPicker: View {
    @EnvironmentObject private var store: OnboardingStore
    @ObservedObject var directory: PartnerDirectory
    @Environment(\.dynamicTypeSize) private var typeSize

    private var query: String { store.preferences.referralCode.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [SaveddPartner] { directory.partners.filter { $0.matches(query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Partner name or referral code").font(.subheadline.weight(.medium))
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(SaveddBrand.muted)
                    TextField("Search partners or enter a code", text: Binding(
                        get: { store.preferences.referralCode },
                        set: { store.preferences.referralCode = String($0.prefix(80)); store.preferences.partner = nil }
                    ))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.done)
                    .accessibilityLabel("Partner name or referral code")
                    if !query.isEmpty {
                        Button {
                            store.preferences.referralCode = ""
                            store.preferences.partner = nil
                        } label: { Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Clear partner search")
                    }
                }
                .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 56)
                .background(SaveddBrand.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(SaveddBrand.border))
            }

            if let selected = store.preferences.partner {
                Label("Selected: \(selected.name)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(SaveddBrand.gold).font(.subheadline)
            }

            if directory.isLoading {
                HStack { ProgressView(); Text("Finding Savedd partners…").font(.subheadline) }
                    .foregroundStyle(SaveddBrand.muted).padding(.vertical)
            } else if let error = directory.error {
                Text(error).font(.subheadline).foregroundStyle(SaveddBrand.muted)
                Button("Try again") { directory.load() }.frame(minHeight: 44)
            } else if matches.isEmpty {
                Text(query.isEmpty ? "No partners are listed yet. Have a code? You can enter it above."
                     : "No matching partner. Check the spelling, or continue to save your code for later.")
                    .font(.subheadline).foregroundStyle(SaveddBrand.muted)
            } else {
                Text("CHOOSE YOUR REFERRER").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(SaveddBrand.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 136), spacing: 12)], spacing: 12) {
                    ForEach(matches) { partner in
                        Button {
                            store.preferences.partner = partner
                            store.preferences.referralCode = partner.slug
                        } label: {
                            VStack(spacing: 10) {
                                ZStack(alignment: .bottomTrailing) {
                                    Circle().fill(SaveddBrand.gold.opacity(0.12))
                                    Text(partner.initials).font(.system(.title2, design: .serif)).frame(maxWidth: .infinity, maxHeight: .infinity)
                                    if store.preferences.partner?.id == partner.id {
                                        Image(systemName: "checkmark.circle.fill").background(SaveddBrand.card, in: Circle())
                                    }
                                }
                                .foregroundStyle(SaveddBrand.gold).frame(width: 64, height: 64)
                                Text(partner.name).font(.subheadline.weight(.medium)).foregroundStyle(SaveddBrand.foreground)
                                Text(partner.slug).font(.caption).foregroundStyle(SaveddBrand.muted)
                            }
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 144).padding(12)
                            .background(SaveddBrand.card, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(store.preferences.partner?.id == partner.id ? SaveddBrand.gold : SaveddBrand.border))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(partner.name), code \(partner.slug)")
                        .accessibilityAddTraits(store.preferences.partner?.id == partner.id ? [.isSelected] : [])
                    }
                }
            }
            if !query.isEmpty && store.preferences.partner == nil {
                Text(query.range(of: "^[A-Za-z0-9][A-Za-z0-9-]{1,31}$", options: .regularExpression) == nil
                     ? "Choose a matching partner above, or enter a code with 2–32 letters, numbers, or hyphens."
                     : "Select a partner to confirm your choice. An unrecognized code is saved on this device only.")
                    .font(.caption).foregroundStyle(SaveddBrand.muted)
            }
        }
    }
}

struct SaveddPreferencesForm: View {
    @EnvironmentObject private var store: OnboardingStore
    static let languages = [("", "Any language"), ("en", "English"), ("da", "Dansk"), ("de", "Deutsch"),
                            ("es", "Español"), ("fr", "Français"), ("it", "Italiano"), ("nl", "Nederlands"),
                            ("no", "Norsk"), ("sv", "Svenska"), ("fi", "Suomi"), ("pl", "Polski"),
                            ("pt", "Português"), ("ja", "日本語"), ("zh", "中文"), ("ru", "Русский")]
    static func languageName(_ code: String) -> String {
        languages.first { $0.0 == code }?.1 ?? Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance").font(.headline)
                HStack(spacing: 12) {
                    ForEach(SaveddAppearance.allCases, id: \.self) { appearance in
                        Button { store.preferences.appearance = appearance } label: {
                            VStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: appearance == .dark ? "moon.stars" : "sun.max")
                                        Spacer()
                                        Image(systemName: store.preferences.appearance == appearance ? "checkmark.circle.fill" : "circle")
                                    }
                                    Capsule().frame(width: 58, height: 4).opacity(0.5)
                                    Capsule().frame(width: 40, height: 4).opacity(0.25)
                                }
                                .padding(16)
                                .foregroundStyle(appearance == .dark ? SaveddBrand.gold : Color(red: 0.45, green: 0.35, blue: 0.12))
                                .background(appearance == .dark ? SaveddBrand.card : Color(red: 0.96, green: 0.94, blue: 0.89), in: RoundedRectangle(cornerRadius: 12))
                                Text(appearance.title).font(.subheadline.weight(.medium))
                            }
                            .padding(12).frame(maxWidth: .infinity)
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(store.preferences.appearance == appearance ? SaveddBrand.gold : SaveddBrand.border))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(appearance.title) appearance")
                        .accessibilityAddTraits(store.preferences.appearance == appearance ? [.isSelected] : [])
                    }
                }
                Text("Setup stays in Savedd’s dark style. Your choice applies when you start browsing.")
                    .font(.caption).foregroundStyle(SaveddBrand.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Search language").font(.headline)
                HStack {
                    Picker("Search language", selection: $store.preferences.language) {
                        ForEach(Self.languages, id: \.0) { language in Text(language.1).tag(language.0) }
                        if !Self.languages.contains(where: { $0.0 == store.preferences.language }) {
                            Text(Self.languageName(store.preferences.language)).tag(store.preferences.language)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(minHeight: 48)
                    Spacer()
                }
                Text("Preferred language for results where supported. App menus are currently in English.")
                    .font(.caption).foregroundStyle(SaveddBrand.muted)
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $store.preferences.privacyMode) {
                    Label("Privacy Mode", systemImage: "shield.lefthalf.filled").font(.headline)
                }
                Text("Use the community index instead of external search providers. You may see fewer results.")
                    .font(.subheadline).foregroundStyle(SaveddBrand.muted)
                Text("This isn’t private browsing or a VPN. Pages you visit and optional AI answers can still connect to other services.")
                    .font(.caption).foregroundStyle(SaveddBrand.muted)
            }
            .padding(20).background(SaveddBrand.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(SaveddBrand.border))
        }
    }
}

struct SaveddSettingsView: View {
    @State private var reading: ProverbChapter?
    @EnvironmentObject private var reminders: ProverbReminders
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                OnboardingBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        SaveddPreferencesForm()
                        Divider()
                        Text("Daily Proverb").font(.system(.title, design: .serif))
                        Button("Read today’s proverb") { reading = ProverbLibrary.bundled?.chapters.first { $0.day == ProverbLibrary.day() } }
                            .frame(minHeight: 44)
                        ProverbReminderSetup()
                    }
                    .padding(24).frame(maxWidth: 560)
                }
            }
            .foregroundStyle(SaveddBrand.foreground).tint(SaveddBrand.gold)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $reading) { chapter in
            DailyProverbView(chapter: chapter) { url in
                dismiss()
                reminders.searchURL = url
            }
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView { _ in }.environmentObject(OnboardingStore(defaults: UserDefaults(suiteName: "savedd.preview")!))
            .environmentObject(ProverbReminders.shared)
            .preferredColorScheme(.dark)
    }
}
