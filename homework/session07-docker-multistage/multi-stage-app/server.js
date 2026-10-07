// Adapted from session6-7-docker/multi-stage-dockerfile/server.js
// Changes vs the course version: port 3000 -> 8080 and the exact message
// required by the homework spec.
const express = require("express");

const app = express();
const PORT = process.env.PORT || 8080;

app.get("/", (req, res) => {
  res.send("<h1>Hello World from Docker multi-stage build</h1>\n");
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server running on port ${PORT}`);
});
