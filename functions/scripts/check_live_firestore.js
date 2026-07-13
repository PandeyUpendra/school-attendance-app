const http = require("https");

const idToken = "eyJhbGciOiJSUzI1NiIsImtpZCI6IjY1Y2IzZjAyMGNhZjdiMmE5ZTg2ZWFkOTAxZDg5ZjQ4MTJjYmFjYmMiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL3NlY3VyZXRva2VuLmdvb2dsZS5jb20vYXR0ZW5kYW5jZWFwcC1lNzZlMSIsImF1ZCI6ImF0dGVuZGFuY2VhcHAtZTc2ZTEiLCJhdXRoX3RpbWUiOjE3ODM2NDk4MjMsInVzZXJfaWQiOiJnMHVEUDcwd08xTzQ4OFcxbDRWc2htVG1vZ24yIiwic3ViIjoiZzB1RFA3MHdPMU80ODhXMWw0VnNobVRtb2duMiIsImlhdCI6MTc4MzY0OTgyMywiZXhwIjoxNzgzNjUzNDIzLCJlbWFpbCI6InBhbmVlcmJhY2h1QGdtYWlsLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJmaXJlYmFzZSI6eyJpZGVudGl0aWVzIjp7ImVtYWlsIjpbInBhbmVlcmJhY2h1QGdtYWlsLmNvbSJdfSwic2lnbl9pbl9wcm92aWRlciI6InBhc3N3b3JkIn19.dL8Jd_BIbZ6zVyqo1IEGYESqjfJAISpRg2I9IQsqEYL1WkHEjqifhTsRUHyhHGGRsfgLGbElgijesRsxVuRPn6mmOFfQZOTLmHa8Q5oRSs43GYCrPZL1n5V7_NmCbPs5H6tpW3---x0FL3JF-XI_kZvWu2gw9p_Gmy1HbjbMa-AOUmzfmwVK48J27804ZykPI-2J8MJc0vX7KMgl1SN1NAjntedbAxboU0iAsyUUWtFee2koW0jyHzwJxONR8HofVG7tLviPB-p7Y4RxEjaYSNjWlESMV8xhIRI8o8wHqXqBo_eDDdlIEDLR3ryuW15CVybqMwVAly4oI70EUu5DOQ";
const email = "paneerbachu@gmail.com";

console.log(`=== Fetching live Firestore document for: ${email} ===`);

const options = {
  hostname: "firestore.googleapis.com",
  port: 443,
  path: `/v1/projects/attendanceapp-e76e1/databases/(default)/documents/allowed_users/${email}`,
  method: "GET",
  headers: {
    "Authorization": `Bearer ${idToken}`
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
      console.log("Firestore Document:", JSON.stringify(parsed, null, 2));
    } catch (e) {
      console.log("Raw Response:", body);
    }
  });
});

req.on("error", (error) => {
  console.error("Request Error:", error);
});

req.end();
