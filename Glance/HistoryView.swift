import SwiftUI
import UIKit

struct HistoryView: View {
    @State private var records = RecordStore.loadAll()

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView(
                    "No screenshots yet",
                    systemImage: "photo",
                    description: Text("Choose a screenshot from Glance's home screen or share one from another app.")
                )
            } else {
                List {
                    ForEach(records) { record in
                        NavigationLink {
                            HistoryDetailView(record: record)
                        } label: {
                            RecordRow(record: record)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("History")
        .onAppear {
            records = RecordStore.loadAll()
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            RecordStore.delete(records[index])
        }
        records.remove(atOffsets: offsets)
    }
}

struct HistoryDetailView: View {
    let record: GlanceRecord
    @Environment(\.openURL) private var openURL
    @State private var currentRecord: GlanceRecord

    init(record: GlanceRecord) {
        self.record = record
        _currentRecord = State(initialValue: RecordStore.load(record.id) ?? record)
    }

    var body: some View {
        detailContent
            .onAppear {
                currentRecord = RecordStore.load(record.id) ?? record
            }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let image = RecordStore.image(for: currentRecord),
           let imageData = RecordStore.imageData(for: currentRecord) {
            AnalysisScreen(
                image: image,
                imageData: imageData,
                analysis: currentRecord.analysis,
                recordID: currentRecord.id,
                areaAnalyses: currentRecord.areaAnalyses,
                onOpenURL: { url in
                    openURL(url)
                }
            )
            .navigationTitle("Screenshot")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(
                "Screenshot missing",
                systemImage: "photo",
                description: Text("This analysis is still here, but the image file is gone.")
            )
            .navigationTitle("Screenshot")
        }
    }
}
