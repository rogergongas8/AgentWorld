import SwiftUI

/// Detail sheet for one skill, opened by tapping it in the roster.
struct SkillDetailView: View {
    let skill: Skill

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(skill.name, systemImage: "sparkles")
                    .font(.title3.bold())
                Spacer()
                Button("Cerrar", action: dismiss.callAsFunction)
            }

            if let description = skill.description {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ScrollView {
                Text(skill.source)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(width: 380, height: 440)
    }
}
