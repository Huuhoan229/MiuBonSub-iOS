const fs = require('fs');
const html = fs.readFileSync('index.html', 'utf8');

const loginWallIdx = html.indexOf('<div id="login-wall">');
const mainAppIdx = html.indexOf('<div id="main-app-content">');
console.log(html.substring(loginWallIdx, mainAppIdx + 50));
