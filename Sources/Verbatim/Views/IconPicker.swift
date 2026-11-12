import SwiftUI

/// About 200 of Apple's SF Symbols, sorted into a few groups, with search words
/// so "science" finds the flask. Only names that exist on macOS 26.
enum IconCatalog {
    struct Icon: Identifiable, Hashable {
        let name: String
        let words: String
        var id: String { name }
    }

    struct Category: Identifiable {
        let title: String
        let icons: [Icon]
        var id: String { title }
    }

    private static func list(_ items: [(String, String)]) -> [Icon] {
        items.map { Icon(name: $0.0, words: $0.1) }
    }

    static let categories: [Category] = [
        Category(title: "School", icons: list([
            ("book", "book reading english literature novel"),
            ("book.closed", "book reading english literature"),
            ("books.vertical", "books library reading shelf"),
            ("text.book.closed", "textbook book reading"),
            ("character.book.closed", "dictionary words language vocabulary"),
            ("graduationcap", "school graduation class university"),
            ("backpack", "school bag backpack"),
            ("studentdesk", "class desk classroom student"),
            ("pencil", "pencil write writing essay edit"),
            ("pencil.and.outline", "write draw edit"),
            ("highlighter", "highlight study notes"),
            ("paperclip", "attach clip"),
            ("folder", "folder files class"),
            ("doc.text", "document essay paper notes"),
            ("note.text", "notes note"),
            ("list.bullet.clipboard", "clipboard checklist homework assignment"),
            ("checklist", "checklist todo homework tasks"),
            ("bookmark", "bookmark save"),
            ("building.columns", "school history government university"),
            ("building.2", "building campus city"),
            ("bell", "bell school period"),
            ("calendar", "calendar date schedule"),
            ("clock", "clock time period"),
            ("alarm", "alarm morning wake"),
            ("magnifyingglass", "search research investigate"),
            ("lightbulb", "idea lightbulb think"),
            ("brain.head.profile", "brain think psychology mind"),
            ("brain", "brain think science"),
            ("quote.bubble", "quote speech discussion"),
            ("text.quote", "quote poem poetry"),
            ("character.bubble", "language speaking chinese"),
            ("abc", "abc spelling english letters"),
            ("textformat", "text writing grammar"),
            ("archivebox", "archive box old"),
            ("tray", "tray inbox"),
        ])),
        Category(title: "Subjects", icons: list([
            ("globe.americas", "globe world studies geography earth"),
            ("globe.europe.africa", "globe world studies geography europe africa"),
            ("globe.asia.australia", "globe world studies geography asia myanmar"),
            ("map", "map geography history travel"),
            ("mappin.and.ellipse", "place location geography"),
            ("scroll", "history scroll ancient story"),
            ("theatermasks", "drama theater theatre play acting"),
            ("music.note", "music note band choir"),
            ("music.mic", "music singing choir"),
            ("pianokeys", "piano music keys"),
            ("guitars", "guitar music band"),
            ("paintbrush", "art paint painting"),
            ("paintpalette", "art palette paint design"),
            ("pencil.and.ruler", "design technology drawing math"),
            ("camera", "photography camera media"),
            ("film", "film movie media"),
            ("function", "math function algebra"),
            ("sum", "math sum"),
            ("percent", "math percent"),
            ("x.squareroot", "math square root algebra"),
            ("number", "math number"),
            ("plus.forwardslash.minus", "math plus minus calculator"),
            ("chart.bar", "chart statistics economics data"),
            ("chart.pie", "chart statistics data"),
            ("flask", "science chemistry flask lab"),
            ("testtube.2", "science chemistry lab"),
            ("atom", "science physics atom"),
            ("bolt", "physics energy electricity"),
            ("leaf", "biology plant nature"),
            ("ladybug", "biology insect nature"),
            ("laptopcomputer", "computer science laptop ict"),
            ("desktopcomputer", "computer science ict"),
            ("chevron.left.forwardslash.chevron.right", "code programming computer science"),
            ("keyboard", "typing computer"),
            ("cpu", "computer technology"),
            ("figure.run", "pe sport running fitness"),
            ("sportscourt", "pe sport court"),
            ("soccerball", "pe sport football soccer"),
            ("basketball", "pe sport basketball"),
            ("dumbbell", "pe gym fitness"),
            ("cross.case", "health first aid"),
            ("stethoscope", "health medicine biology"),
            ("dollarsign.circle", "money economics business"),
            ("banknote", "money economics business"),
            ("briefcase", "business work career"),
            ("hammer", "design technology build"),
            ("wrench.and.screwdriver", "design technology tools"),
            ("translate", "language translate french spanish chinese"),
        ])),
        Category(title: "Things", icons: list([
            ("star", "star favorite important"),
            ("heart", "heart love"),
            ("tag", "tag label"),
            ("pin", "pin important"),
            ("flag", "flag goal"),
            ("mic", "mic microphone podcast speech"),
            ("waveform", "audio sound voice"),
            ("headphones", "headphones listening audio"),
            ("speaker.wave.2", "speaker sound loud"),
            ("bubble.left", "chat talk"),
            ("bubble.left.and.bubble.right", "chat discussion debate talk"),
            ("person", "person teacher student"),
            ("person.2", "people pair group"),
            ("person.3", "people group class"),
            ("hand.raised", "hand question raise"),
            ("hand.thumbsup", "good like"),
            ("eye", "see look"),
            ("crown", "crown king queen history"),
            ("trophy", "trophy win competition"),
            ("medal", "medal award"),
            ("gift", "gift present"),
            ("key", "key"),
            ("lock", "lock private"),
            ("puzzlepiece", "puzzle problem"),
            ("gamecontroller", "game play"),
            ("dice", "dice game chance probability"),
            ("cup.and.saucer", "coffee tea break"),
            ("fork.knife", "food lunch"),
            ("house", "home house"),
            ("car", "car travel"),
            ("bus", "bus school trip"),
            ("airplane", "plane trip travel"),
            ("tram", "train tram travel"),
            ("bicycle", "bike cycling"),
            ("sailboat", "boat sea"),
            ("tent", "camping trip outdoor"),
            ("binoculars", "explore look"),
            ("wand.and.stars", "magic myth story"),
            ("sparkles", "sparkle new magic"),
        ])),
        Category(title: "Nature", icons: list([
            ("sun.max", "sun weather morning"),
            ("moon", "moon night"),
            ("moon.stars", "night sky stars"),
            ("cloud", "cloud weather"),
            ("cloud.rain", "rain weather monsoon"),
            ("cloud.bolt", "storm weather thunder"),
            ("snowflake", "snow winter cold"),
            ("wind", "wind weather"),
            ("tornado", "tornado weather"),
            ("flame", "fire hot"),
            ("drop", "water drop"),
            ("leaf", "leaf plant nature"),
            ("tree", "tree forest nature environment"),
            ("mountain.2", "mountain geography hike"),
            ("globe", "globe earth world"),
            ("rainbow", "rainbow weather"),
            ("pawprint", "animal pet"),
            ("bird", "bird animal"),
            ("fish", "fish sea animal"),
            ("cat", "cat animal pet"),
            ("dog", "dog animal pet"),
            ("ant", "ant insect animal"),
            ("tortoise", "tortoise turtle slow story fable"),
            ("hare", "rabbit hare fast story fable"),
            ("carrot", "food vegetable"),
        ])),
        Category(title: "Shapes", icons: list([
            ("circle", "circle shape"),
            ("square", "square shape"),
            ("triangle", "triangle shape"),
            ("diamond", "diamond shape"),
            ("hexagon", "hexagon shape"),
            ("seal", "seal badge"),
            ("checkmark.circle", "done check"),
            ("exclamationmark.triangle", "warning important"),
            ("questionmark.circle", "question help"),
            ("info.circle", "info"),
            ("sparkle", "sparkle star"),
            ("infinity", "infinity math"),
            ("asterisk", "asterisk note"),
            ("at", "at email"),
            ("target", "target goal aim"),
            ("scope", "scope aim"),
            ("shield", "shield safe"),
            ("flag.checkered", "finish race"),
        ])),
    ]

    static let all: [Icon] = {
        var seen = Set<String>()
        return categories.flatMap(\.icons).filter { seen.insert($0.name).inserted }
    }()

    static func search(_ query: String, in category: String?) -> [Icon] {
        let pool = category.flatMap { c in categories.first { $0.title == c }?.icons } ?? all
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return pool }
        return pool.filter { icon in
            let hay = icon.words + " " + icon.name.replacingOccurrences(of: ".", with: " ")
            return words.allSatisfy { hay.contains($0) }
        }
    }
}

/// A group's or recording's icon, in its soft color.
struct ItemIcon: View {
    let name: String?
    let color: IconColor
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: name ?? "square.dashed")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(name == nil ? Color.secondary : color.color)
            .frame(width: size + 6, height: size + 6)
    }
}

/// Search, a few categories, a grid of icons and a row of soft colors.
/// Picking an icon changes it right away; Done or Esc closes.
struct IconPicker: View {
    let icon: String?
    let color: IconColor
    let pick: (String?, IconColor) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category: String?

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 4), count: 9)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search icons, like book or science", text: $query)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                categoryButton(nil, "All")
                ForEach(IconCatalog.categories) { c in categoryButton(c.title, c.title) }
            }
            .font(.caption)

            let icons = IconCatalog.search(query, in: query.isEmpty ? category : nil)
            ScrollView {
                if icons.isEmpty {
                    Text("No icon for \u{201C}\(query)\u{201D}. Try a subject, like history or music.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                        ForEach(icons) { item in
                            IconCell(name: item.name, selected: item.name == icon, color: color) {
                                pick(item.name, color)
                            }
                        }
                    }
                }
            }
            .frame(height: 170)

            Divider()
            // Colors on their own line, buttons on the next: all in one row
            // squeezed the words onto two lines each (Ryan saw "Col / or").
            HStack(spacing: 8) {
                Text("Color")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.trailing, 4)
                ForEach(IconColor.allCases) { c in
                    Button {
                        pick(icon, c)
                    } label: {
                        Circle()
                            .fill(c.color)
                            .frame(width: 16, height: 16)
                            .overlay {
                                if c == color {
                                    Circle().stroke(Theme.ink, lineWidth: 1.5).frame(width: 22, height: 22)
                                }
                            }
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(c.label)
                    .accessibilityLabel(c.label)
                    .accessibilityAddTraits(c == color ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button("Remove Icon") { pick(nil, color) }
                    .disabled(icon == nil)
                    .help("Show no icon next to the name")
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.ink)
                    .keyboardShortcut(.defaultAction)
            }
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 330)
    }

    private func categoryButton(_ value: String?, _ title: String) -> some View {
        Button(title) {
            category = value
            query = ""
        }
        .buttonStyle(.plain)
        .fontWeight(category == value && query.isEmpty ? .semibold : .regular)
        .foregroundStyle(category == value && query.isEmpty ? .primary : .secondary)
    }
}

private struct IconCell: View {
    let name: String
    let selected: Bool
    let color: IconColor
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 15))
                .foregroundStyle(selected ? color.color : Theme.ink)
                .frame(width: 30, height: 30)
                .background(
                    selected ? Color.primary.opacity(0.14) : hovering ? Color.primary.opacity(0.07) : .clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(name.replacingOccurrences(of: ".", with: " "))
        .accessibilityLabel(name.replacingOccurrences(of: ".", with: " "))
    }
}
