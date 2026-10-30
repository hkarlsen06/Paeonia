from pathlib import Path
names=['mischief','flame','rose','woodland','cosy','silver','halloween','christmas','winter']
p=Path('ios/PaeoniaApp/Shared/Components/AvatarDecoration.swift')
s=p.read_text().replace('case none, peony, ribbon, moon, candy','case none, peony, ribbon, moon, candy\n    case '+', '.join(names))
s=s.replace('case .candy: .avatarDecorationCandy','case .candy: .avatarDecorationCandy\n'+ '\n'.join(f'        case .{n}: .avatarDecoration{n.title()}' for n in names))
s=s.replace('case .candy: .avatarFrameCandy','case .candy: .avatarFrameCandy\n'+'\n'.join(f'        case .{n}: .avatarFrame{n.title()}' for n in names))
s=s.replace('case .candy: 1_024 / 740','case .candy: 1_024 / 740\n'+ '\n'.join(f'        case .{n}: 1' for n in names))
p.write_text(s)
p=Path('backend/convex/lib/validators.ts');s=p.read_text().replace('"moon", "candy");','"moon", "candy",\n  '+', '.join('"'+n+'"' for n in names)+');');p.write_text(s)
p=Path('backend/convex/avatarDecorations.test.ts');s=p.read_text().replace('["peony", "ribbon", "moon", "candy"]','["peony", "ribbon", "moon", "candy",\n    '+', '.join('"'+n+'"' for n in names)+']');p.write_text(s)
p=Path('ios/PaeoniaApp/App/DeveloperScenarios/DeveloperLocalFlowServices.swift');s=p.read_text().replace('avatarScenario ? .peony : .none','avatarScenario ? DeveloperAvatarFixture.decoration(for: "own", default: .peony) : .none').replace('avatarScenario ? .moon : nil','avatarScenario ? DeveloperAvatarFixture.decoration(for: "partner", default: .moon) : nil');p.write_text(s)
p=Path('ios/PaeoniaApp/App/DeveloperScenarios/DeveloperAvatarScenarios.swift');s=p.read_text().replace('enum DeveloperAvatarFixture {','''enum DeveloperAvatarFixture {
    nonisolated static func decoration(for person: String, default fallback: AvatarDecoration) -> AvatarDecoration {
        let value = UserDefaults.standard.string(forKey: "avatar-frame-\\(person)") ?? ""
        return AvatarDecoration(rawValue: value) ?? fallback
    }
''');p.write_text(s)
