import Foundation

enum TemplateScaffoldBuilder {
    static func buildProject(from spec: NewProjectSpec) -> SandboxProject {
        let template = TemplateCatalog.template(for: spec.templateID)
        let files: [SandboxFile]

        if let template {
            files = template.files.map {
                SandboxFile(name: $0.name, content: $0.content, language: $0.language)
            }
        } else {
            files = BlankExpoTSFiles.files.map {
                SandboxFile(name: $0.name, content: $0.content, language: $0.language)
            }
        }

        return SandboxProject(
            name: spec.effectiveName,
            templateType: template?.templateType ?? .blank,
            files: files
        )
    }

    static func buildProject(from template: StudioTemplate, name: String) -> SandboxProject {
        let files = template.files.map {
            SandboxFile(name: $0.name, content: $0.content, language: $0.language)
        }
        return SandboxProject(
            name: name.isEmpty ? template.name : name,
            templateType: template.templateType,
            files: files
        )
    }
}
