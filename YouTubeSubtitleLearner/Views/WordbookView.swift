import SwiftUI

struct WordbookView: View {
    @ObservedObject private var store = WordbookStore.shared
    @State private var newWord = ""
    @State private var newMeaning = ""
    @State private var query = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("単語", text: $newWord).textFieldStyle(.roundedBorder)
                    TextField("意味(任意)", text: $newMeaning).textFieldStyle(.roundedBorder)
                    Button("追加") { add() }.buttonStyle(.borderedProminent).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }.padding(.horizontal)
                TextField("検索", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal)
                List {
                    ForEach(filtered) { e in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(e.text).font(.headline)
                                if let m = e.meaning, !m.isEmpty { Text(m).font(.caption).foregroundColor(.secondary) }
                            }
                            Spacer()
                            Button { store.toggleKnown(e) } label: {
                                Image(systemName: e.isKnown ? "checkmark.circle.fill" : "checkmark.circle")
                            }
                        }
                    }
                    .onDelete(perform: store.delete)
                }
            }
            .navigationTitle("単語帳")
        }
    }

    private var filtered: [WordEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = store.items
        if q.isEmpty { return base }
        return base.filter { $0.text.lowercased().contains(q) || ($0.meaning?.lowercased().contains(q) ?? false) }
    }

    private func add() {
        store.add(text: newWord, meaning: newMeaning)
        newWord = ""; newMeaning = ""
    }
}

