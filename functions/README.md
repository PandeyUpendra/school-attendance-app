# Cloud Functions — authenticated password emails

This replaces Firebase Auth's built-in password emails (which land in Gmail spam
because the `firebaseapp.com` sender isn't authenticated for you) with email sent
through **SendGrid from a domain you authenticate** — so messages pass
SPF + DKIM + DMARC and reach the inbox.

The app calls the callable function `sendPasswordEmail({ email, type })`:
- `type: "invite"` — sent when an admin/owner/principal/coordinator creates an
  account. Requires the caller to be a signed-in management user.
- `type: "reset"` — self-service "forgot password". Open, but never reveals
  whether an account exists.

The Dart side (`AuthService.sendPasswordEmailViaFunction`) **falls back** to
Firebase's built-in email if the function isn't deployed yet, so the app keeps
working before you finish the steps below — it just won't fix spam until then.

---

## One-time setup

### 1. Authenticate a domain in SendGrid  ← the step that actually fixes spam
1. Create a SendGrid account (free tier is fine).
2. **Settings → Sender Authentication → Authenticate Your Domain.**
3. SendGrid gives you CNAME records — add them at your DNS provider and verify.
4. (Recommended) add a DMARC TXT record at `_dmarc.yourschooldomain.com`:
   ```
   v=DMARC1; p=none; rua=mailto:dmarc@yourschooldomain.com
   ```
> Skipping this step means mail still lacks DKIM alignment and can be filtered.
> SendGrid is only the delivery path — domain authentication is the fix.

### 2. Create a SendGrid API key
**Settings → API Keys → Create API Key** (Restricted → "Mail Send" only). Copy it.

### 3. Configure this project
```bash
cd functions
cp .env.example .env          # set MAIL_FROM (on your authenticated domain) + MAIL_FROM_NAME
npm install

# Store the API key as a secret (not in .env):
firebase functions:secrets:set SENDGRID_API_KEY   # paste the key when prompted
```

### 4. Deploy
```bash
firebase deploy --only functions
```

---

## Notes
- Region is `us-central1`, matching the Flutter `FirebaseFunctions.instance` default.
- The link in the email points to Firebase's standard password-action page; only
  the **sender** changes. That's all that's needed for inbox placement. To also
  brand the link domain, configure a custom action URL in
  Firebase Console → Authentication → Templates.
- Local logs: `firebase functions:log` (or `npm run logs`).
- Swapping providers (Mailgun / Amazon SES): only `index.js`'s send block needs
  to change; the callable contract stays the same.
