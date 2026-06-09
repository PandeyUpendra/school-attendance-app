# Firestore security-rules tests (#76)

Real emulator tests for `../firestore.rules`. These were the **first** automated
coverage of the rules — the security boundary previously had none.

## Run

```bash
cd test_rules && npm install        # once
# from the REPO ROOT (where firebase.json lives):
firebase emulators:exec --only firestore --project school-app-rules-test \
  "cd test_rules && node --test"
```

### JDK note
Firebase CLI ≥ 15 requires **JDK 21+**. If only JDK 17 is installed, run the
emulator via an older CLI that supports 17:

```bash
npx -y firebase-tools@13.35.1 emulators:exec --only firestore \
  --project school-app-rules-test "cd test_rules && node --test"
```

## Coverage
- `notifications.test.mjs` — guardian audience scoping (legacy `guardian:{class}:{roll}`
  **and** the stable `guardian_adm:{admissionId}` variant, #39), broadcast/group
  audiences, multi-tenant isolation, and anti-phishing create restrictions.
