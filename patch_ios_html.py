import re

path = r'E:\MiuBonVSub\MiuBonSub-iOS\www\index.html'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Replace <div class="app"> with a button for backend config at the top right
button_html = """
<div class="app">
  <button onclick="changeBackendUrl()" style="position: absolute; top: 10px; right: 10px; z-index: 9999; background: var(--bg-card); color: var(--text-muted); border: 1px solid var(--border); border-radius: 8px; padding: 6px 12px; cursor: pointer; font-size: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.5);">⚙️ Đổi IP Server</button>
"""

text = text.replace('<div class="app">', button_html)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)
