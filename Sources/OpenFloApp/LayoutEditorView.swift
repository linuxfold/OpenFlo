import SwiftUI

struct LayoutEditorView: View {
    @ObservedObject var workspace: WorkspaceModel

    private let toolIcons = [
        "cursorarrow",
        "rectangle",
        "line.diagonal",
        "tablecells",
        "square.grid.2x2",
        "textformat",
        "oval",
        "capsule",
        "diamond",
        "triangle",
        "record.circle",
        "arrowtriangle.up.fill"
    ]

    var body: some View {
        VStack(spacing: 0) {
            layoutMenuBar
            layoutRibbon
            toolStrip
            canvasArea
        }
        .frame(minWidth: 1080, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var layoutMenuBar: some View {
        HStack(spacing: 34) {
            Text("Layout Editor")
                .fontWeight(.semibold)
                .padding(.horizontal, 24)
                .frame(height: 34)
                .overlay(Rectangle().stroke(Color.accentColor.opacity(0.45), lineWidth: 1))
            Text("File")
            Text("Edit")
            Text("Object")
            Text("Arrange")
            Spacer()
            Image(systemName: "gearshape.fill")
            Image(systemName: "bookmark.fill")
                .foregroundStyle(.teal)
            Image(systemName: "heart")
                .foregroundStyle(.red)
            Image(systemName: "questionmark")
                .foregroundStyle(.teal)
            Button {
                workspace.addLayout()
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .help("New layout")
        }
        .font(.title3)
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(.regularMaterial)
    }

    private var layoutRibbon: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(spacing: 16) {
                    Button {
                        workspace.addLayout()
                    } label: {
                        Image(systemName: "plus")
                            .font(.largeTitle)
                    }
                    .buttonStyle(.plain)
                    .help("Add layout")

                    Button {
                        workspace.selectedLayoutID = workspace.layouts.first?.id
                    } label: {
                        Image(systemName: "folder.fill")
                            .font(.title)
                    }
                    .buttonStyle(.plain)
                    .help("Layouts")

                    Button {
                        workspace.deleteSelectedLayout()
                    } label: {
                        Image(systemName: "minus")
                            .font(.title2.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .help("Delete layout")
                }
                .foregroundStyle(.teal)
                .frame(width: 42)

                List(selection: $workspace.selectedLayoutID) {
                    ForEach(workspace.layouts) { layout in
                        HStack(spacing: 6) {
                            Rectangle()
                                .stroke(Color.black, lineWidth: 1)
                                .frame(width: 10, height: 26)
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 20, height: 20)
                            Text(layout.name)
                                .font(.headline)
                        }
                        .tag(layout.id)
                    }
                }
                .listStyle(.plain)
                .frame(width: 360, height: 120)
                .overlay(Rectangle().stroke(.gray, lineWidth: 1))
            }
            .padding(6)
            .frame(width: 430, height: 150)
            .overlay(alignment: .bottom) {
                Text("Layouts")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Group")
                    Menu("{Workspace Selection}") {}
                        .frame(width: 290)
                }
                HStack {
                    Text("Iterate by")
                    Menu("Off") {}
                        .frame(width: 90)
                }
                Spacer()
                Text("Iteration")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .frame(width: 390, height: 150)

            Divider()

            VStack(spacing: 6) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.teal)
                Text("Batch")
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .frame(width: 96, height: 150)

            Spacer()
        }
        .frame(height: 150)
        .background(.regularMaterial)
        .overlay(Rectangle().stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
    }

    private var toolStrip: some View {
        HStack(spacing: 4) {
            ForEach(toolIcons, id: \.self) { icon in
                Button {} label: {
                    Image(systemName: icon)
                        .font(.title3)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
            }

            Divider()
                .frame(height: 30)
                .padding(.horizontal, 8)

            Button {} label: {
                Image(systemName: "arrow.uturn.left")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            Button {} label: {
                Image(systemName: "arrow.uturn.right")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            Spacer()
            Button {} label: {
                Image(systemName: "chevron.left.2")
                    .font(.title3)
            }
            .buttonStyle(.bordered)
            .help("Properties")
        }
        .padding(.horizontal, 6)
        .frame(height: 44)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var canvasArea: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.white

                rulerTop
                    .frame(height: 28)
                    .padding(.leading, 28)

                rulerLeft
                    .frame(width: 28)
                    .padding(.top, 28)

                Rectangle()
                    .stroke(.black, lineWidth: 1.5)
                    .padding(.leading, 28)
                    .padding(.top, 28)
                    .padding(.trailing, 28)
                    .padding(.bottom, 26)

                Text("Drag Populations & Statistics Here")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.gray)
                    .position(x: geometry.size.width * 0.48, y: 86)

                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Button {} label: { Image(systemName: "minus.magnifyingglass") }
                        Menu("100%") {}
                            .frame(width: 82)
                        Button {} label: { Image(systemName: "plus.magnifyingglass") }
                        Spacer()
                    }
                    .buttonStyle(.bordered)
                    .padding(.leading, 4)
                    .padding(.bottom, 4)
                }

                Text("Properties")
                    .font(.headline)
                    .rotationEffect(.degrees(-90))
                    .position(x: geometry.size.width - 12, y: geometry.size.height / 2)
            }
        }
    }

    private var rulerTop: some View {
        HStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { inch in
                VStack(spacing: 0) {
                    Spacer()
                    Text("\(inch)")
                        .font(.caption)
                    Rectangle()
                        .fill(.black)
                        .frame(width: 1, height: 10)
                }
                .frame(width: 120)
            }
            Spacer()
        }
        .background(Color(nsColor: .controlColor))
    }

    private var rulerLeft: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { inch in
                HStack(spacing: 0) {
                    Spacer()
                    Text("\(inch)")
                        .font(.caption)
                    Rectangle()
                        .fill(.black)
                        .frame(width: 10, height: 1)
                }
                .frame(height: 105)
            }
            Spacer()
        }
        .background(Color(nsColor: .controlColor))
    }
}
