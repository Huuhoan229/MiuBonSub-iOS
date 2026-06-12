const fs = require('fs');
const html = fs.readFileSync('index.html', 'utf8');
console.log('main-app-content starts at:', html.indexOf('<div id="main-app-content">'));
console.log('bottom-tabs starts at:', html.indexOf('<nav class="bottom-tabs'));
console.log('script app.js starts at:', html.indexOf('<script src="/static/js/app.js'));
