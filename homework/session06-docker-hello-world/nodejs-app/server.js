// Plain Node.js HTTP server (no Express) that serves a Hello World page.
const http = require("http");

const PORT = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end("<h1>Hello World from Node.js in Docker!</h1>\n");
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Node.js server listening on port ${PORT}`);
});
