import DocuDeskCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .setup:
                SetupView()
            case let .problem(problem):
                StorageProblemView(problem: problem)
            case .ready:
                MainShell()
            }
        }
        .background(WindowConfigurator())
        .background(Theme.canvas)
        .onAppear {
            if model.phase == .loading { model.start() }
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }
}

struct MainShell: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 250)
            Rectangle().fill(Theme.border).frame(width: 1)
            VStack(spacing: 0) {
                TopBar()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.canvas)
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.toast)
        .sheet(item: $model.starterRequest) { request in
            StarterPicker(request: request)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let id = model.openDocumentID {
            DocumentEditorView(documentID: id)
                .id(id)
        } else {
            switch model.screen {
            case .dashboard: DashboardView()
            case .documents: DocumentsView()
            case .templates: TemplatesView()
            case .clients: ClientsView()
            case .products: ProductsView()
            case .reports: ReportsView()
            case .storage: StorageView()
            case .settings: SettingsView()
            }
        }
    }
}

// MARK: - Sidebar

/// The DocuDesk "D" brand mark, drawn from the shared vector geometry.
struct BrandMarkView: View {
    private struct Part: Shape {
        let upper: Bool

        func path(in rect: CGRect) -> Path {
            Path(upper ? BrandMark.upperPath(in: rect) : BrandMark.lowerPath(in: rect))
        }
    }

    static let light = Color(.displayP3, red: BrandMark.lightP3.red, green: BrandMark.lightP3.green, blue: BrandMark.lightP3.blue)
    static let dark = Color(.displayP3, red: BrandMark.darkP3.red, green: BrandMark.darkP3.green, blue: BrandMark.darkP3.blue)

    var body: some View {
        ZStack {
            Part(upper: true).fill(Self.light)
            Part(upper: false).fill(Self.dark)
        }
        .aspectRatio(BrandMark.size.width / BrandMark.size.height, contentMode: .fit)
    }
}

/// App logo tile: the brand mark on a white rounded square, matching the app icon.
struct LogoMark: View {
    var size: CGFloat = 40

    var body: some View {
        BrandMarkView()
            .frame(height: size * 0.56)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(LinearGradient(colors: [.white, Color(red: 0.94, green: 0.955, blue: 0.98)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).strokeBorder(Color.black.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: size * 0.1, y: size * 0.04)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    private let quickCreate: [DocumentKind] = [.invoice, .quotation, .estimate, .proposal, .purchaseOrder, .deliveryChallan, .creditNote, .agreement, .letter]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                LogoMark()
                VStack(alignment: .leading, spacing: 1) {
                    Text("DocuDesk").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                    Text("Create · Manage · Grow").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.top, 52)
            .padding(.horizontal, 22)
            .padding(.bottom, 24)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Screen.allCases) { screen in
                        SidebarItem(title: screen.title, icon: screen.icon, selected: model.openDocumentID == nil && model.screen == screen) {
                            model.navigate(to: screen)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quick Create")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .padding(.bottom, 6)
                        ForEach(quickCreate) { kind in
                            QuickCreateRow(kind: kind) { model.createDocument(kind) }
                        }
                    }
                    .padding(.bottom, 8)
                    .background(Theme.surfaceMuted.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 18)
                }
                .padding(.horizontal, 14)
            }

            StorageFooter()
                .padding(14)
        }
        .background(Theme.sidebar)
    }
}

private struct SidebarItem: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? icon + ".fill" : icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(title).font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(selected ? Theme.accent : Theme.text.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.accentSoft : hovering ? Theme.surfaceMuted : .clear)
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(Theme.accent).frame(width: 3, height: 20).offset(x: -8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct QuickCreateRow: View {
    let kind: DocumentKind
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                KindBadge(kind: kind, size: 26)
                Text(kind.displayName).font(.system(size: 13)).foregroundStyle(Theme.text.opacity(0.9))
                Spacer()
                if hovering {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(hovering ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("New \(kind.displayName)")
    }
}

private struct StorageFooter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button { model.navigate(to: .storage) } label: {
            HStack(spacing: 10) {
                Circle().fill(model.backupIsStale ? Theme.warning : Theme.success).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.backupInProgress ? "Backing up…" : "Offline · Saved locally")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(model.lastBackup.map { "Backup \($0.relativeDescription)" } ?? "No backup yet")
                        .font(.system(size: 10.5))
                        .foregroundStyle(model.backupIsStale ? Theme.warning : Theme.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
        .id(model.revision)
    }
}

// MARK: - Top bar

struct TopBar: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var showCreate = false

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                TextField("Search documents, clients, items…", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .focused($searchFocused)
                    .onSubmit { model.navigate(to: .documents) }
                if model.searchText.isEmpty {
                    Text("⌘ K")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border))
                } else {
                    Button { model.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: 640, minHeight: 40)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(searchFocused ? Theme.accent.opacity(0.6) : Theme.border))
            .onChange(of: model.searchText) { _, text in
                if !text.isEmpty, model.screen != .documents || model.openDocumentID != nil {
                    model.navigate(to: .documents)
                }
            }
            .onChange(of: model.searchFocusRequest) { _, _ in searchFocused = true }

            Spacer(minLength: 12)

            Button { showCreate.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                    Text("Create Document")
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .popover(isPresented: $showCreate, arrowEdge: .bottom) {
                CreateMenu(customTypes: model.customTypes) { kind in
                    showCreate = false
                    model.createDocument(kind)
                } onCustom: { type in
                    showCreate = false
                    model.createDocument(customType: type)
                }
            }

            Button { model.navigate(to: .settings) } label: { Image(systemName: "gearshape") }
                .buttonStyle(IconButtonStyle(size: 38))
                .help("Settings")

            ProfileAvatar()
        }
        .padding(.horizontal, 26)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(Theme.canvas)
    }
}

private struct CreateMenu: View {
    let customTypes: [CustomDocumentType]
    let onSelect: (DocumentKind) -> Void
    let onCustom: (CustomDocumentType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !customTypes.isEmpty {
                Text("YOUR TYPES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                ForEach(customTypes) { type in
                    CustomRow(type: type) { onCustom(type) }
                }
            }
            ForEach(DocumentCategory.allCases) { category in
                Text(category.displayName.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                ForEach(DocumentKind.builtIn.filter { $0.category == category }) { kind in
                    MenuRow(kind: kind) { onSelect(kind) }
                }
            }
        }
        .padding(8)
        .frame(width: 240)
    }

    private struct CustomRow: View {
        let type: CustomDocumentType
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    KindBadge(kind: .custom, size: 26)
                    Text(type.name).font(.system(size: 13))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background(hovering ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }

    private struct MenuRow: View {
        let kind: DocumentKind
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    KindBadge(kind: kind, size: 26)
                    Text(kind.displayName).font(.system(size: 13))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background(hovering ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}

struct ProfileAvatar: View {
    @EnvironmentObject private var model: AppModel
    var size: CGFloat = 38

    var body: some View {
        Menu {
            Section("Company Profile") {
                ForEach(model.profiles) { profile in
                    Button {
                        model.switchProfile(to: profile.id)
                    } label: {
                        if profile.id == model.profile?.id {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            }
            Divider()
            Button("Manage Profiles…") { model.navigate(to: .settings) }
        } label: {
            avatar
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(model.profile.map { "Working as \($0.name)" } ?? "")
    }

    private var avatar: some View {
        let logo = model.store?.image(at: model.profile?.logoPath)
        return ZStack {
            if let logo {
                Image(nsImage: logo).resizable().scaledToFit().padding(4)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(logo == nil ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x6366F1), Color(hex: 0x1A6DF0)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Theme.surface), in: Circle())
        .overlay(Circle().strokeBorder(Theme.border))
    }

    private var initials: String {
        let words = (model.profile?.name ?? "D").split(separator: " ")
        return words.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}
