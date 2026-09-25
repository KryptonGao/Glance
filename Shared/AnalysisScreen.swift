import SwiftUI
import UIKit

struct AnalysisScreen: View {
    let image: UIImage
    let imageData: Data
    let analysis: GlanceAnalysis
    let recordID: UUID?
    var onOpenURL: (URL) -> Void

    @State private var areaAnalyses: [AreaAnalysis]
    @State private var selectedAreaID: UUID?
    @State private var selectionPoints: [NormalizedPoint] = []
    @State private var activeStroke: [NormalizedPoint] = []
    @State private var selectionUndoStack: [[NormalizedPoint]] = []
    @State private var isSelectingArea = false
    @State private var isAnalyzingArea = false
    @State private var areaErrorMessage: String?
    @State private var pendingAreaSaveIDs: Set<UUID> = []
    @State private var areaSaveErrorMessage: String?
    @State private var pendingEvent: CalendarAction?
    @State private var pendingReminder: ReminderAction?
    @State private var addedActionIDs: Set<UUID> = []
    @State private var addingActionIDs: Set<UUID> = []
    @State private var toast: ToastMessage?
    @State private var askContext: AskContext?

    init(
        image: UIImage,
        imageData: Data,
        analysis: GlanceAnalysis,
        recordID: UUID? = nil,
        areaAnalyses: [AreaAnalysis] = [],
        onOpenURL: @escaping (URL) -> Void
    ) {
        self.image = UIImage(data: imageData) ?? image
        self.imageData = imageData
        self.analysis = analysis
        self.recordID = recordID
        self.onOpenURL = onOpenURL
        _areaAnalyses = State(initialValue: areaAnalyses)
        _selectedAreaID = State(initialValue: nil)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Area selection")
                                .font(.headline)
                            Text(isSelectingArea
                                 ? "Trace a region on the screenshot. Scrolling resumes after the stroke."
                                 : "Scroll to browse, or draw an area to focus on a detail.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Button {
                            isSelectingArea.toggle()
                            activeStroke = []
                            areaErrorMessage = nil
                        } label: {
                            Label(
                                isSelectingArea ? "Cancel" : "Draw area",
                                systemImage: isSelectingArea ? "xmark" : "lasso"
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(isAnalyzingArea)
                        .accessibilityHint(isSelectingArea
                                           ? "Turn off drawing mode."
                                           : "Turn on drawing mode to select part of the screenshot.")
                    }

                    AreaSelectionCanvas(
                        image: image,
                        selectedOutline: selectedArea?.outline ?? selectionPoints,
                        activeStroke: activeStroke,
                        isSelectingArea: isSelectingArea,
                        isDisabled: isAnalyzingArea,
                        onStrokeBegan: beginStroke(at:),
                        onStrokeChanged: appendStrokePoint(_:),
                        onStrokeEnded: finishStroke
                    )

                    if !selectionPoints.isEmpty {
                        HStack(spacing: 12) {
                            Button("Undo", systemImage: "arrow.uturn.backward", action: undoSelection)
                                .disabled(isAnalyzingArea)
                            Button("Clear", systemImage: "xmark.circle", action: clearSelection)
                                .disabled(isAnalyzingArea)
                            Spacer(minLength: 0)
                        }

                        Button {
                            Task { await analyzeSelectedArea() }
                        } label: {
                            Label(
                                areaErrorMessage == nil ? "Analyze this area" : "Retry analysis",
                                systemImage: areaErrorMessage == nil ? "sparkle.magnifyingglass" : "arrow.clockwise"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAnalyzingArea || selectionPoints.count < 3)
                    }

                    if isAnalyzingArea {
                        ProgressView("Analyzing area…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let areaErrorMessage {
                        Text(areaErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let areaSaveErrorMessage {
                        Text(areaSaveErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if recordID != nil, !pendingAreaSaveIDs.isEmpty {
                            Button("Retry save", systemImage: "arrow.clockwise", action: retrySavingAreas)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
            }

            if !areaAnalyses.isEmpty {
                Section {
                    Picker("Analysis", selection: analysisSelection) {
                        Text("Full screenshot")
                            .tag(nil as UUID?)
                        ForEach(areaAnalyses.indices, id: \.self) { index in
                            HStack {
                                Text("Area")
                                Text(index + 1, format: .number)
                            }
                            .tag(Optional(areaAnalyses[index].id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section(selectedArea == nil ? "Summary" : "Area analysis") {
                Group {
                    if visibleAnalysis.summary.isEmpty {
                        Text("No summary.")
                    } else {
                        Text(visibleAnalysis.summary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !visibleAnalysis.searches.isEmpty {
                Section("Search") {
                    ForEach(visibleAnalysis.searches) { search in
                        Button {
                            open(search)
                        } label: {
                            row(
                                title: search.title,
                                detail: search.query,
                                symbol: "magnifyingglass",
                                action: "Search"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Search for \(search.query)"))
                    }
                }
            }

            if !visibleAnalysis.events.isEmpty {
                Section("Calendar") {
                    ForEach(visibleAnalysis.events) { event in
                        Button {
                            guard !addedActionIDs.contains(event.id),
                                  !addingActionIDs.contains(event.id)
                            else { return }
                            addingActionIDs.insert(event.id)
                            pendingEvent = event
                        } label: {
                            row(
                                title: event.title,
                                detail: event.detailText,
                                symbol: "calendar",
                                action: "Add",
                                isAdded: addedActionIDs.contains(event.id),
                                isAdding: addingActionIDs.contains(event.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(addedActionIDs.contains(event.id) || addingActionIDs.contains(event.id))
                    }
                }
            }

            if !visibleAnalysis.reminders.isEmpty {
                Section("Reminders") {
                    ForEach(visibleAnalysis.reminders) { reminder in
                        Button {
                            guard !addedActionIDs.contains(reminder.id),
                                  !addingActionIDs.contains(reminder.id)
                            else { return }
                            pendingReminder = reminder
                        } label: {
                            row(
                                title: reminder.title,
                                detail: reminder.detailText,
                                symbol: "checklist",
                                action: "Add",
                                isAdded: addedActionIDs.contains(reminder.id),
                                isAdding: addingActionIDs.contains(reminder.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(addedActionIDs.contains(reminder.id) || addingActionIDs.contains(reminder.id))
                    }
                }
            }

            Section {
                Button {
                    openAskGlance()
                } label: {
                    Label("Ask Glance", systemImage: "bubble.left")
                }
            } footer: {
                Text("Nothing is added until you confirm it.")
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: toast.kind.symbol)
                        .foregroundStyle(toast.kind.tint)
                        .accessibilityHidden(true)
                    Text(toast.message)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08))
                }
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1)
                .accessibilityElement(children: .combine)
                .allowsHitTesting(false)
            }
        }
        .task(id: toast?.id) {
            guard toast != nil else { return }
            do {
                try await Task.sleep(for: .seconds(2.5))
            } catch {
                return
            }
            withAnimation(.easeOut(duration: 0.2)) {
                toast = nil
            }
        }
        .sheet(item: $pendingEvent) { event in
            SystemEventEditor(action: event) { saved in
                pendingEvent = nil
                addingActionIDs.remove(event.id)
                if saved {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addedActionIDs.insert(event.id)
                    }
                    showToast(String(localized: "Added to Calendar."), kind: .success)
                }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "Add this reminder?",
            isPresented: reminderDialogPresented,
            titleVisibility: .visible,
            presenting: pendingReminder
        ) { reminder in
            Button("Add Reminder") {
                let reminder = reminder
                guard !addedActionIDs.contains(reminder.id),
                      addingActionIDs.insert(reminder.id).inserted
                else { return }
                Task { await addReminder(reminder) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { reminder in
            Text(reminder.title)
        }
        .sheet(item: $askContext) { context in
            AskGlanceSheet(imageData: context.imageData, summary: context.summary)
        }
        .scrollDisabled(!activeStroke.isEmpty)
    }

    private var selectedArea: AreaAnalysis? {
        guard let selectedAreaID else { return nil }
        return areaAnalyses.first { $0.id == selectedAreaID }
    }

    private var visibleAnalysis: GlanceAnalysis {
        selectedArea?.analysis ?? analysis
    }

    private var analysisSelection: Binding<UUID?> {
        Binding(
            get: { selectedAreaID },
            set: { selectAnalysis($0) }
        )
    }

    private var reminderDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingReminder != nil },
            set: { if !$0 { pendingReminder = nil } }
        )
    }

    private func selectAnalysis(_ id: UUID?) {
        selectedAreaID = id
        selectionPoints = []
        activeStroke = []
        selectionUndoStack = []
        areaErrorMessage = nil
    }

    private func beginStroke(at point: NormalizedPoint) {
        selectionUndoStack.append(selectionPoints)
        selectionPoints = []
        selectedAreaID = nil
        activeStroke = [point]
        areaErrorMessage = nil
    }

    private func appendStrokePoint(_ point: NormalizedPoint) {
        activeStroke.append(point)
    }

    private func finishStroke() {
        selectionPoints = activeStroke
        activeStroke = []
        isSelectingArea = false
        if selectionPoints.count < 3 {
            areaErrorMessage = String(localized: "Draw a larger loop around the area.")
        }
    }

    private func undoSelection() {
        selectionPoints = selectionUndoStack.popLast() ?? []
        areaErrorMessage = nil
    }

    private func clearSelection() {
        selectionPoints = []
        activeStroke = []
        selectionUndoStack = []
        areaErrorMessage = nil
    }

    private func analyzeSelectedArea() async {
        guard selectionPoints.count >= 3, !isAnalyzingArea else { return }
        let outline = selectionPoints
        isAnalyzingArea = true
        areaErrorMessage = nil
        defer { isAnalyzingArea = false }

        do {
            let maskedJPEG = try AreaImageMasker.makeMaskedJPEG(from: imageData, outline: outline)
            let provider = try GlanceClient.makeProvider()
            let result = try await provider.analyze(imageData: maskedJPEG, prompt: GlancePrompts.analyzeArea)
            let area = AreaAnalysis(outline: outline, analysis: result)
            areaAnalyses.append(area)
            selectedAreaID = area.id
            selectionPoints = []
            activeStroke = []
            selectionUndoStack = []

            guard let recordID else {
                pendingAreaSaveIDs.insert(area.id)
                areaSaveErrorMessage = String(localized: "This area result could not be saved to history.")
                return
            }
            do {
                try RecordStore.addAreaAnalysis(area, to: recordID)
            } catch {
                pendingAreaSaveIDs.insert(area.id)
                areaSaveErrorMessage = String(localized: "This area result could not be saved to history.")
            }
        } catch {
            areaErrorMessage = error.localizedDescription
        }
    }

    private func retrySavingAreas() {
        guard let recordID else { return }
        for id in Array(pendingAreaSaveIDs) {
            guard let area = areaAnalyses.first(where: { $0.id == id }) else { continue }
            do {
                try RecordStore.addAreaAnalysis(area, to: recordID)
                pendingAreaSaveIDs.remove(id)
            } catch {
                areaSaveErrorMessage = String(localized: "This area result could not be saved to history.")
                return
            }
        }
        if pendingAreaSaveIDs.isEmpty {
            areaSaveErrorMessage = nil
        }
    }

    private func openAskGlance() {
        let askImageData: Data
        if let selectedArea {
            do {
                askImageData = try AreaImageMasker.makeMaskedJPEG(from: imageData, outline: selectedArea.outline)
            } catch {
                showToast(error.localizedDescription, kind: .error)
                return
            }
        } else {
            askImageData = imageData
        }
        askContext = AskContext(imageData: askImageData, summary: visibleAnalysis.summary)
    }

    private func row(
        title: String,
        detail: String?,
        symbol: String,
        action: LocalizedStringKey,
        isAdded: Bool = false,
        isAdding: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)
                if let detail, !detail.isEmpty, detail != title {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            if isAdded {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else if isAdding {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("Adding…"))
            } else {
                Text(action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func open(_ search: SearchAction) {
        let query = search.query.isEmpty ? search.title : search.query
        let engine = ProviderConfig.load().searchEngine
        guard let url = engine.searchURL(for: query) else { return }
        onOpenURL(url)
    }

    private func addReminder(_ reminder: ReminderAction) async {
        do {
            try await EventActions.addReminder(reminder)
            withAnimation(.easeInOut(duration: 0.2)) {
                addedActionIDs.insert(reminder.id)
            }
            showToast(String(localized: "Added to Reminders."), kind: .success)
        } catch {
            showToast(error.localizedDescription, kind: .error)
        }
        addingActionIDs.remove(reminder.id)
    }

    private func showToast(_ message: String, kind: ToastKind) {
        withAnimation(.easeOut(duration: 0.2)) {
            toast = ToastMessage(message: message, kind: kind)
        }
    }

    private struct ToastMessage: Identifiable {
        let id = UUID()
        let message: String
        let kind: ToastKind
    }

    private enum ToastKind {
        case success
        case error

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .error: "exclamationmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: .green
            case .error: .red
            }
        }
    }

    private struct AskContext: Identifiable {
        var id = UUID()
        let imageData: Data
        let summary: String
    }
}

struct AskGlanceSheet: View {
    let imageData: Data
    let summary: String

    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answer = ""
    @State private var reasoning = ""
    @State private var isThinkingExpanded = false
    @State private var errorMessage: String?
    @State private var isSending = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !summary.isEmpty {
                        Text(summary)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Ask about this screenshot", text: $question, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFocused)

                    Button {
                        Task { await ask() }
                    } label: {
                        Group {
                            if isSending {
                                Text("Asking…")
                            } else {
                                Text("Ask Glance")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(isSending || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if isSending {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }

                    if !reasoning.isEmpty {
                        DisclosureGroup(isExpanded: $isThinkingExpanded) {
                            Text(reasoning)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.top, 4)
                        } label: {
                            Text("Thinking")
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(.secondary)
                    }

                    if !answer.isEmpty {
                        Text(answer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Ask Glance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
    }

    private func ask() async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        errorMessage = nil
        answer = ""
        reasoning = ""
        isThinkingExpanded = false
        defer { isSending = false }
        do {
            let provider = try GlanceClient.makeProvider()
            let reply = try await provider.ask(
                imageData: imageData,
                prompt: GlancePrompts.ask(summary: summary, question: trimmed)
            )
            answer = reply.text
            reasoning = reply.reasoning
            isThinkingExpanded = reply.text.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ShareAnalysisView: View {
    let image: UIImage
    var onOpenURL: (URL) -> Void

    @State private var analysis: GlanceAnalysis?
    @State private var imageData: Data?
    @State private var savedRecord: GlanceRecord?
    @State private var errorMessage: String?
    @State private var didStart = false

    var body: some View {
        Group {
            if let analysis, let imageData {
                AnalysisScreen(
                    image: image,
                    imageData: imageData,
                    analysis: analysis,
                    recordID: savedRecord?.id,
                    onOpenURL: onOpenURL
                )
            } else {
                VStack(spacing: 28) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 24)
                        .accessibilityLabel(Text("Screenshot"))

                    if let errorMessage {
                        ContentUnavailableView {
                            Label("Analysis failed", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("Retry", systemImage: "arrow.clockwise") {
                                Task { await retryAnalysis() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        ProgressView("Analyzing…")
                    }
                    Spacer()
                }
                .padding(.top, 24)
            }
        }
        .task { await analyze() }
    }

    private func analyze() async {
        guard !didStart else { return }
        didStart = true
        do {
            guard let jpeg = ImageJPEG.encode(image) else {
                throw GlanceAIError.invalidResponse(String(localized: "Glance couldn't read this image."))
            }
            imageData = jpeg
            let provider = try GlanceClient.makeProvider()
            let result = try await provider.analyze(imageData: jpeg, prompt: GlancePrompts.analyze)
            do {
                savedRecord = try RecordStore.save(imageJPEG: jpeg, analysis: result)
            } catch {
                savedRecord = nil
            }
            analysis = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func retryAnalysis() async {
        didStart = false
        errorMessage = nil
        analysis = nil
        savedRecord = nil
        await analyze()
    }
}
