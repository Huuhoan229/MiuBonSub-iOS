import re

path = r'E:\MiuBonVSub\MiuBonSub-iOS\www\static\js\app.js'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

new_api_code = """let API = localStorage.getItem('MIUBON_API_BASE') || '';
if (!API && !window.location.href.includes('localhost:5000') && !window.location.href.includes('localhost:5051') && !window.location.href.includes('127.0.0.1')) {
    setTimeout(() => {
        let input = prompt("Welcome to MiuBon Vietsub iOS App!\\n\\nPlease enter your Backend PC IP Address and Port (e.g. http://192.168.1.10:5060):", "http://");
        if (input) {
            API = input.replace(/\\/+$/, '');
            localStorage.setItem('MIUBON_API_BASE', API);
            window.location.reload();
        }
    }, 500);
}

window.changeBackendUrl = function() {
    let current = localStorage.getItem('MIUBON_API_BASE') || 'http://';
    let input = prompt("Change Backend PC IP Address:", current);
    if (input !== null) {
        localStorage.setItem('MIUBON_API_BASE', input.replace(/\\/+$/, ''));
        window.location.reload();
    }
};
"""

text = text.replace("const API = '';", new_api_code)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)
