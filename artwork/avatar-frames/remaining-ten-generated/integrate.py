from pathlib import Path
import json,subprocess
root=Path('/tmp/paeonia-avatar-expansion-remaining');g=json.loads((root/'geometry.json').read_text());names=list(g)
p=Path('ios/PaeoniaApp/Shared/Components/AvatarDecoration.swift');s=p.read_text();s=s.replace('    /// The largest frame','    case '+', '.join(names)+'\n\n    /// The largest frame',1)
s=s.replace('case .winter: .avatarDecorationWinter','case .winter: .avatarDecorationWinter\n'+ '\n'.join('        case .'+n+': .avatarDecoration'+n.title() for n in names))
s=s.replace('case .winter: .avatarFrameWinter','case .winter: .avatarFrameWinter\n'+ '\n'.join('        case .'+n+': .avatarFrame'+n.title() for n in names))
s=s.replace('case .winter: 1.62578','case .winter: 1.62578\n'+ '\n'.join(f'        case .{n}: {g[n]["artworkScale"]:.5f}' for n in names))
s=s.replace('case .winter: 0.13','case .winter: 0.13\n'+ '\n'.join(f'        case .{n}: {g[n]["outset"]:.2f}' for n in names));p.write_text(s)
p=Path('backend/convex/lib/validators.ts');s=p.read_text().replace('"christmas", "winter");','"christmas", "winter",\n  '+', '.join('"'+n+'"' for n in names)+');');p.write_text(s)
p=Path('backend/convex/avatarDecorations.test.ts');s=p.read_text().replace('"christmas", "winter"] as const','"christmas", "winter",\n    '+', '.join('"'+n+'"' for n in names)+'] as const');p.write_text(s)
titles=[('Rope','Tau'),('Paint','Maling'),('Jelly','Gelé'),('Racing','Racing'),('Hearts','Hjerter'),('Easter','Påske'),('17 May','17. mai'),('Wildflowers','Markblomster'),('New Year','Nyttår'),('Pride','Pride')]
for n,(en,nb) in zip(names,titles):
 subprocess.run(['scripts/xcstrings-set','ios/PaeoniaApp/Resources/Localization/Localizable.xcstrings','avatarDecoration.'+n,'--comment','Name of the selectable '+en+' illustrated portrait frame. Available all year.','--en',en,'--nb',nb],check=True)
