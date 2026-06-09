import os
import re

# Get frontend calls
frontend_calls = set()
pattern = re.compile(r"['\"](/api/[^\?\'\"]+)['\"\?]")

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
                    frontend_calls.add(cleaned)

# I can parse the backend dump here
import subprocess
os.chdir('backend')
os.environ['JWT_SIGNING_KEY'] = 'fake'
os.environ['JWT_VERIFYING_KEY'] = 'fake'
os.environ['NOTCHPAY_PUBLIC_KEY'] = 'fake'
os.environ['NOTCHPAY_PRIVATE_KEY'] = 'fake'
out = subprocess.check_output(['python', 'dump_urls.py']).decode('utf-8')

backend_urls = set()
for line in out.splitlines():
    if line.startswith('GET ') or line.startswith('POST ') or line.startswith('PUT ') or line.startswith('PATCH ') or line.startswith('DELETE '):
        url = line.split(' ')[1]
        url = url.replace('{pk}', '{param}')
        url = url.replace('{external_id}', '{param}')
        url = url.replace('{dispute_id}', '{param}')
        backend_urls.add(url)

print("--- FRONTEND CALLS NOT IN BACKEND ---")
for call in sorted(frontend_calls):
    # exact match
    if call in backend_urls:
        continue
    # try trailing slash
    if not call.endswith('/') and call + '/' in backend_urls:
        continue
    print(f"Missing in backend: {call}")

print("\n--- BACKEND ROUTES NOT IN FRONTEND ---")
for call in sorted(backend_urls):
    if call in frontend_calls:
        continue
    if call.rstrip('/') in frontend_calls:
        continue
    print(f"Unused by frontend: {call}")
