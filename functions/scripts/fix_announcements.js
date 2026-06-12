const fs = require("fs");
const path = require("path");

// Read Firebase token from config
const configPath = path.join(process.env.HOME || "", ".config", "configstore", "firebase-tools.json");
if (!fs.existsSync(configPath)) {
  console.error("Firebase config not found at", configPath);
  process.exit(1);
}

const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
const accessToken = config.tokens && config.tokens.access_token;

if (!accessToken) {
  console.error("Access token not found in config");
  process.exit(1);
}

const schoolId = "school_1781281587355_301879429";

async function fixAnnouncements() {
  try {
    const listUrl = `https://firestore.googleapis.com/v1/projects/attendanceapp-e76e1/databases/(default)/documents/schools/${schoolId}/announcements?pageSize=100`;
    
    const listResp = await fetch(listUrl, {
      headers: {
        "Authorization": `Bearer ${accessToken}`
      }
    });

    if (!listResp.ok) {
      throw new Error(`Failed to list announcements: ${listResp.statusText} - ${await listResp.text()}`);
    }

    const data = await listResp.json();
    const documents = data.documents || [];
    
    console.log(`Found ${documents.length} announcements. Checking for audience mapping updates...`);

    for (const doc of documents) {
      const docPath = doc.name; // Full resource name e.g. projects/attendanceapp-e76e1/databases/(default)/documents/schools/school_xxx/announcements/ann_yyy
      const docId = path.basename(docPath);
      const fields = doc.fields || {};
      const audience = fields.audience && fields.audience.stringValue;

      let newAudience = null;
      if (audience === "Everyone") {
        newAudience = "all";
      } else if (audience === "All Staff") {
        newAudience = "teachers";
      } else if (audience === "All Guardians") {
        newAudience = "guardians";
      }

      if (newAudience) {
        console.log(`Updating announcement ${docId}: "${fields.title ? fields.title.stringValue : 'No Title'}" audience from "${audience}" to "${newAudience}"...`);
        
        const updateUrl = `https://firestore.googleapis.com/v1/${docPath}?updateMask.fieldPaths=audience`;
        const updateBody = {
          fields: {
            audience: { stringValue: newAudience }
          }
        };

        const updateResp = await fetch(updateUrl, {
          method: "PATCH",
          headers: {
            "Authorization": `Bearer ${accessToken}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify(updateBody)
        });

        if (!updateResp.ok) {
          console.error(`Failed to update ${docId}: ${updateResp.statusText} - ${await updateResp.text()}`);
        } else {
          console.log(`Successfully updated ${docId}`);
        }
      } else {
        console.log(`Announcement ${docId}: "${fields.title ? fields.title.stringValue : 'No Title'}" already has correct/unmodified audience: "${audience}"`);
      }
    }
  } catch (e) {
    console.error("Error:", e);
  }
}

fixAnnouncements();
