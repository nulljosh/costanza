import SwiftUI

// Poets and readers: author pages, follow, kudos and the pixel avatar.

/// A quiet "I read this": a reader gives one and can take it back, and only the author sees the count.
struct KudosRow: View {
    let poem: Poem
    var store: Store
    @State private var given = false
    @State private var count: Int?
    @State private var busy = false

    var body: some View {
        Group {
            if store.token == nil {
                Text("Sign in to tell the poet you read this.").foregroundStyle(.secondary)
            } else if poem.user_id == store.userId {
                if let count { Text(count == 1 ? "1 reader told you they read this. Only you see this." : "\(count) readers told you they read this. Only you see this.").foregroundStyle(.secondary) }
            } else {
                Button {
                    busy = true
                    Task { if await store.setKudos(poem, given: !given) { given.toggle() }; busy = false }
                } label: { Label(given ? "You read this" : "I read this", systemImage: given ? "checkmark" : "book") }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(given ? .secondary : .accentPink)
                .disabled(busy)
            }
        }
        .font(.subheadline)
        .task(id: store.token) { (given, count) = await store.kudos(for: poem) }
    }
}

struct AuthorView: View {
    let name: String
    var store: Store
    private var poems: [Poem] { store.shown.filter { $0.pen_name == name } }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    PixelAvatar(seed: name).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.title2.bold())
                        Text(poems.count == 1 ? "1 poem" : "\(poems.count) poems").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.token != nil, !poems.contains(where: { $0.user_id == store.userId }) {
                        let on = store.follows.contains(name)
                        Button(on ? "Following" : "Follow") { Task { await store.toggleFollow(name) } }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(on ? .secondary : .accentPink)
                    }
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            }
            ForEach(poems) { p in NavigationLink(value: Route.poem(p.id)) { PoemRow(poem: p, byline: false) } }
        }
        .listStyle(.plain)
        .readingColumn()
        .navigationTitle(name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// The same 8 by 8 mirrored pixel face the web draws from a pen name (web/app.html avatarSvg),
/// down to JavaScript's float rounding in the generator, so a poet looks the same everywhere.
struct PixelAvatar: View {
    let seed: String
    var body: some View {
        Canvas { ctx, size in
            var h: UInt32 = 0
            for u in seed.utf16 { h = h &* 31 &+ UInt32(u) }
            func rand() -> Double {
                let d = Double(h) * 1103515245 + 12345 // JS multiplies in doubles; match its rounding
                h = UInt32(truncatingIfNeeded: Int64(d))
                return Double(h) / 4294967296
            }
            let palettes: [[UInt32]] = [[0xB5836A, 0x7C93A6, 0x4A5A68], [0x7C8B6B, 0xA8B99A, 0xCBD8BE], [0x0077b6, 0x00b4d8, 0x90e0ef], [0xA5735C, 0xD2A88E, 0xE3B778], [0x2d6a4f, 0x52b788, 0xb7e4c7]]
            let bgs: [UInt32] = [0x111111, 0x0c1220, 0x1a1a1a, 0x0f0f1a, 0x0a1a0a]
            let palette = palettes[Int(rand() * Double(palettes.count))]
            let bg = bgs[Int(rand() * Double(bgs.count))]
            let px = size.width / 8
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: bg)))
            for row in 0..<8 {
                for col in 0..<4 {
                    guard rand() > 0.45 else { continue }
                    let c = Color(hex: palette[Int(rand() * 3)])
                    ctx.fill(Path(CGRect(x: CGFloat(col) * px, y: CGFloat(row) * px, width: px, height: px)), with: .color(c))
                    ctx.fill(Path(CGRect(x: CGFloat(7 - col) * px, y: CGFloat(row) * px, width: px, height: px)), with: .color(c))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

extension Color {
    init(hex: UInt32) { self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255) }
}
