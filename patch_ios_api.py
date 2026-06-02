import re

path = r'E:\MiuBonVSub\MiuBonSub-iOS\www\static\js\app.js'

with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

api_block = """const IS_CAPACITOR_APP = window.location.protocol === 'capacitor:' || window.location.protocol === 'ionic:' || window.location.protocol === 'file:' || !!window.Capacitor;
const IS_IOS_REMOTE_MODE = IS_CAPACITOR_APP || window.location.pathname.startsWith('/ios') || window.location.search.includes('ios=1');
let API = IS_IOS_REMOTE_MODE ? (localStorage.getItem('MIUBON_API_BASE') || '') : '';"""

text = re.sub(
    r"const IS_IOS_REMOTE_MODE = window\.location\.pathname\.startsWith\('/ios'\) \|\| window\.location\.search\.includes\('ios=1'\);\s*let API = IS_IOS_REMOTE_MODE \? \(localStorage\.getItem\('MIUBON_API_BASE'\) \|\| ''\) : '';",
    api_block,
    text,
    count=1,
)
text = text.replace(
    'prompt("Change Backend PC IP Address:", current);',
    'prompt("Nhập Backend PC IP/Port (ví dụ http://192.168.1.10:5060):", current);',
)

with open(path, 'w', encoding='utf-8', newline='') as f:
    f.write(text)