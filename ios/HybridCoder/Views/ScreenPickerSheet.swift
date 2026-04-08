import SwiftUI

struct ScreenPickerSheet: View {
    @Bindable var viewModel: RNPreviewViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.screens) { screen in
                    Button {
                        Task {
                            await viewModel.selectScreen(screen)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.portrait")
                                .font(.caption)
                                .foregroundStyle(screen.id == viewModel.activeScreen?.id ? Theme.accent : Theme.dimText)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(screen.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                Text(screen.filePath)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Theme.dimText)
                            }

                            Spacer()

                            if screen.id == viewModel.activeScreen?.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .listRowBackground(Theme.cardBg)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surfaceBg)
            .navigationTitle("Screens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}
