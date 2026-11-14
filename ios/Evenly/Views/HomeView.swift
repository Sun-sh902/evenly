import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var showServer = false
    @State private var serverOK: Bool?

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    actions
                    if app.recents.isEmpty { howItWorks } else { recentList }
                    serverStatus
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showServer = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Server settings")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { GroupScreen(groupId: $0) }
            .sheet(isPresented: $showCreate) { CreateGroupView() }
            .sheet(isPresented: $showJoin) { JoinGroupView() }
            .sheet(isPresented: $showServer, onDismiss: { Task { await checkServer() } }) { ServerSettingsView() }
            .task(id: app.serverAddress) { await checkServer() }
            .toast($app.pendingNotice)
        }
        .tint(.ink)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                BrandMark(size: 30)
                Text("Evenly").font(.system(size: 22, weight: .semibold)).tracking(-0.4)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, 4)

            HStack(spacing: 8) {
                Circle().fill(Color.brand).frame(width: 8, height: 8)
                    .background(Circle().fill(Color.brandSoft).frame(width: 16, height: 16))
                Text("Free, open, and without a daily cap").font(.system(size: 13)).foregroundStyle(Color.ink2)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.line))

            VStack(alignment: .leading, spacing: 0) {
                Text("Split the bill,").font(.display(46))
                Text("not the friendship.").font(.display(46)).italic().foregroundStyle(Color.brand)
            }
            .tracking(-1)
            .lineSpacing(-4)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .combine)

            Text("Track shared costs for trips, flats and dinners. Nobody signs up and nobody hits a limit. Share one link and the whole group is in.")
                .font(.system(size: 16))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { showCreate = true } label: {
                Label("New group", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            Button { showJoin = true } label: {
                Label("Join", systemImage: "link").frame(maxWidth: .infinity)
            }
            .buttonStyle(GhostButtonStyle())
            .frame(maxWidth: 140)
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your groups").font(.display(28)).tracking(-0.5)
                Spacer()
                Text("On this device").font(.system(size: 13)).foregroundStyle(Color.ink3)
            }
            ForEach(app.recents) { r in
                NavigationLink(value: r.id) { RecentCard(item: r) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { withAnimation { app.forget(r.id) } } label: {
                            Label("Remove from this device", systemImage: "minus.circle")
                        }
                    }
            }
        }
    }

    private var howItWorks: some View {
        VStack(spacing: 12) {
            step(1, "Make a group", "Name it, add the people. That's the whole setup.")
            step(2, "Log what you spend", "Split equally, by exact amounts, by shares or by percent. Pennies always add up.")
            step(3, "Settle in fewer moves", "Evenly works out the smallest set of payments so everyone ends at zero.")
        }
    }

    private func step(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(n)").font(.display(34)).foregroundStyle(Color.brand).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(text).font(.system(size: 14)).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private var serverStatus: some View {
        Button { showServer = true } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(serverOK == nil ? Color.ink3 : serverOK == true ? Color.pos : Color.neg)
                    .frame(width: 8, height: 8)
                Text(serverOK == false ? "Can't reach \(app.serverURL?.host ?? "server")" : "Server: \(app.serverURL?.host ?? "not set")")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink3)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink3)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens server settings")
    }

    private func checkServer() async {
        serverOK = nil
        serverOK = (try? await app.client?.health()) ?? false
        if serverOK == true { await app.refreshMeta() }
    }
}

private struct RecentCard: View {
    let item: RecentGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(item.name).font(.system(size: 17, weight: .semibold)).tracking(-0.2).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink3)
            }
            HStack {
                HStack(spacing: 4) {
                    ForEach(Array(item.memberNames.prefix(5).enumerated()), id: \.offset) { i, name in
                        Avatar(name: name, colorIndex: i, size: 26)
                    }
                    if item.memberNames.count > 5 {
                        Text("+\(item.memberNames.count - 5)").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.ink3)
                    }
                }
                Spacer()
                Text("\(Money.format(item.total, currency: item.currency, digits: item.digits)) · \(item.seen.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink3)
            }
        }
        .card()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
