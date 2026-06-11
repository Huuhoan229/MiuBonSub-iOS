const fs = require('fs');
let html = fs.readFileSync('index.html', 'utf8');

// 1. Clean up login-wall inline styles
html = html.replace(/<div id="login-wall"[^>]*>/, '<div id="login-wall">');

// 2. Clean up main-app-content inline styles
html = html.replace(/<div id="main-app-content"[^>]*>/, '<div id="main-app-content">');

// 3. Clean up the card inside login-wall
html = html.replace(/<div class="card" style="width:100%; max-width:400px; text-align:center; position:relative; z-index:10;">/, '<div class="card" style="width:100%; max-width:400px; text-align:center; position:relative; z-index:10; border-radius: 24px;">');

// 4. Update the "MiuBon Tool" title gradient to use Outfit font
html = html.replace(/<h2 style="margin-bottom:5px; font-size:1.8rem; background:linear-gradient\(90deg, #fff, var\(--primary\)\); -webkit-background-clip:text; -webkit-text-fill-color:transparent;">MiuBon Tool<\/h2>/, '<h2 style="margin-bottom:5px; font-size:2rem; font-weight:800; background:linear-gradient(135deg, var(--primary), var(--accent)); -webkit-background-clip:text; -webkit-text-fill-color:transparent; justify-content:center;">MiuBon Tool</h2>');

fs.writeFileSync('index.html', html);
console.log('index.html patched');
