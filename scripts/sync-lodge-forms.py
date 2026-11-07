from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
data=json.loads((root/'packages/flutter_core/lodge-forms.json').read_text(encoding='utf8'))
(root/'packages/flutter_core/lib/lodge_forms.dart').write_text('// Generated from lodge-forms.json by scripts/sync-lodge-forms.py.\nconst Map<String, dynamic> lodgeDefinitions = '+json.dumps(data,ensure_ascii=True,indent=2)+';\n',encoding='utf8')
