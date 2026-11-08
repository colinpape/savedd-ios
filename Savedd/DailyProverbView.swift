import SwiftUI

struct ProverbReminderSetup: View {
    @EnvironmentObject private var reminders: ProverbReminders
    @Environment(\.openURL) private var openURL
    var showActions = true
    var onContinue: (() -> Void)?
    private var chapter: ProverbChapter? {
        ProverbLibrary.bundled?.chapters.first { $0.day == ProverbLibrary.day() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let chapter {
                VStack(alignment: .leading, spacing: 14) {
                    Label("DAILY PROVERB", systemImage: "sun.max")
                        .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(SaveddBrand.gold)
                    Text("“\(chapter.highlight)”")
                        .font(.system(.title3, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(chapter.reference) · World English Bible")
                        .font(.caption).foregroundStyle(SaveddBrand.muted)
                    Text("Notification preview · Today’s chapter")
                        .font(.caption2).foregroundStyle(SaveddBrand.muted)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SaveddBrand.card, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(SaveddBrand.border))
            }
            DatePicker("Remind me at", selection: Binding(
                get: { reminders.selectedDate },
                set: { date in Task { await reminders.changeTime(date) } }
            ), displayedComponents: .hourAndMinute)
            .disabled(reminders.busy)
            Text("The day of the month guides your reading: on the 8th, read Proverbs 8. Reminders follow your phone’s local time. No account needed.")
                .font(.subheadline).foregroundStyle(SaveddBrand.muted)
                .fixedSize(horizontal: false, vertical: true)
            if reminders.enabled && reminders.canNotify {
                Label("Daily reminder set for \(reminders.timeDescription)", systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(SaveddBrand.gold)
            }
            if reminders.permission == .denied {
                Text("Notifications are off in iPhone Settings. You can enable them there, then return to Savedd.")
                    .font(.subheadline).foregroundStyle(SaveddBrand.muted)
                Button("Open notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
                .frame(minHeight: 44)
            }
            if let error = reminders.error {
                Text(error).font(.subheadline).foregroundStyle(SaveddBrand.muted)
            }
            if showActions {
                if reminders.enabled && reminders.canNotify {
                    Button("Turn off daily reminders") { reminders.disable() }
                        .frame(minHeight: 44)
                } else {
                    Button {
                        Task { await reminders.enable() }
                    } label: {
                        HStack {
                            if reminders.busy { ProgressView() }
                            Text("Enable daily reminder")
                        }
                    }
                    .buttonStyle(GoldButtonStyle())
                    .disabled(reminders.busy || reminders.permission == .denied)
                }
                if let onContinue {
                    Button(reminders.enabled && reminders.canNotify ? "Continue" : "Maybe later", action: onContinue)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .disabled(reminders.busy)
                }
            }
        }
        .task { await reminders.refresh() }
    }
}

struct DailyProverbView: View {
    let chapter: ProverbChapter
    let onExplore: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var fullChapter = false

    var body: some View {
        NavigationStack {
            ZStack {
                OnboardingBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Label("PROVERBS \(chapter.day)", systemImage: "book.closed")
                            .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(SaveddBrand.gold)
                        Text("A little wisdom, every day.")
                            .font(.system(.largeTitle, design: .serif)).accessibilityAddTraits(.isHeader)
                        Text("“\(chapter.highlight)”")
                            .font(.system(.title2, design: .serif))
                        Text("\(chapter.reference) · World English Bible")
                            .font(.subheadline).foregroundStyle(SaveddBrand.gold)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("A MOMENT TO REFLECT").font(.caption.weight(.semibold)).tracking(2)
                            Text(chapter.reflection).font(.body)
                            Text("Reflection by Savedd").font(.caption).foregroundStyle(SaveddBrand.muted)
                        }
                        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(SaveddBrand.card, in: RoundedRectangle(cornerRadius: 20))
                        Button(fullChapter ? "Hide full chapter" : "Read Proverbs \(chapter.day)") {
                            fullChapter.toggle()
                        }
                        .buttonStyle(GoldButtonStyle())
                        if fullChapter {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Proverbs \(chapter.day)").font(.system(.title, design: .serif))
                                ForEach(chapter.verses, id: \.number) { verse in
                                    Text("\(verse.number)  \(verse.text)")
                                        .font(.system(.body, design: .serif))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        Button {
                            if let destination = SaveddSearchEngine.destination(for: "Proverbs \(chapter.day) meaning and context") {
                                dismiss()
                                onExplore(destination.url)
                            }
                        } label: { Label("Explore this chapter with Savedd", systemImage: "magnifyingglass") }
                        .frame(minHeight: 44)
                        Text("Scripture: World English Bible (WEB), public domain. The same chapter returns each month.")
                            .font(.caption).foregroundStyle(SaveddBrand.muted)
                    }
                    .frame(maxWidth: 560, alignment: .leading).padding(24)
                    .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(SaveddBrand.foreground).tint(SaveddBrand.gold)
            .navigationTitle("Daily Proverb").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close Daily Proverb")
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
