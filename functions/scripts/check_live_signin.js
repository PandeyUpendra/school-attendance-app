const http = require("https");

const apiKey = "AIzaSyB9dyjWRfwMeq8-J6juhYdizI-584MCkBE";
const email = "paneerbachu@gmail.com";
const password = "123456";

console.log(`=== Testing Live Firebase Auth Sign-In for: ${email} ===`);

const data = JSON.stringify({
  email: email,
  password: password,
  returnSecureToken: true
});

const options = {
  hostname: "identitytoolkit.googleapis.com",
  port: 443,
  path: `/v1/accounts:signInWithPassword?key=${apiKey}`,
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Content-Length": data.length
  }
};

const req = http.request(options, (res) => {
  let body = "";
  res.on("data", (chunk) => {
    body += chunk;
  });
  
  res.on("end", () => {
    console.log(`HTTP Status: ${res.statusCode}`);
    try {
      const parsed = JSON.parse(body);
      console.log("Response Body:", JSON.stringify(parsed, null, 2));
    } catch (e) {
      console.log("Raw Response Body:", body);
    }
  });
});

req.on("error", (error) => {
  console.error("Request Error:", error);
});

req.write(data);
req.end();
