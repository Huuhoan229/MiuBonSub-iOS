import re

path = r'E:\MiuBonVSub\MiuBonSub-iOS\www\index.html'
VERSION = '20260602-084327'

with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

text = re.sub(
    r'<meta name="viewport" content="[^"]+">',
    '<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">',
    text,
    count=1,
)
text = re.sub(r'style\.css\?v=[^"\']+', f'style.css?v={VERSION}', text)
text = re.sub(r'app\.js\?v=[^"\']+', f'app.js?v={VERSION}', text)

button = '''<div class="app">
  <button class="ios-backend-button" onclick="changeBackendUrl()" title="Đổi Backend PC IP">⚙️ Đổi IP Server</button>
'''
if 'ios-backend-button' not in text:
    text = text.replace('<div class="app">', button, 1)

with open(path, 'w', encoding='utf-8', newline='') as f:
    f.write(text)