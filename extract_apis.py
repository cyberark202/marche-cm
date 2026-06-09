import os
import re

frontend_apis = set()
pattern = re.compile(r"['\"](/api/[^\?\'\"]+)['\"\?]")

app_calls = {}

for root, _, files in os.walk('frontend'):
    if 'build' in root or '.dart_tool' in root:
        continue
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
                matches = pattern.findall(content)
                for match in matches:
                    cleaned = re.sub(r'\$\{?[^\}]+\}?', '{param}', match)
                    cleaned = re.sub(r'\$[a-zA-Z0-9_]+', '{param}', cleaned)
                    if cleaned not in app_calls:
                        app_calls[cleaned] = []
                    app_calls[cleaned].append(filepath)

print('--- Unique Frontend APIs ---')
for api in sorted(app_calls.keys()):
    print(f"{api} (used in: {', '.join(set([p.split(os.sep)[1] for p in app_calls[api]]))})")
