# Klassivo Marketing Website & Interactive Simulator

This folder contains the official static marketing website for the **Klassivo** school management and attendance application.

## Directory Structure
- `index.html` — The main structure of the page, optimized for search engines (SEO) and modern browsers.
- `styles.css` — Modern design system styled around the Klassivo branding (Teal-green primary `#003D33` and Sea-green accent `#2E8B74`).
- `app.js` — Interactive simulator code that models the actual screens of the 4 key roles (Teacher, Coordinator, Principal, Guardian).

## How to Run Locally

Since this is a fully client-side application built with HTML, CSS, and JS, you don't need any complex build pipelines. You can launch it using any of the following methods:

### Method 1: Double Click
Simply open [index.html](file:///Users/upendrapandey/school_app/website/index.html) in your favorite web browser (Chrome, Safari, Firefox).

### Method 2: Python HTTP Server (Recommended)
If you want to run a local server:
1. Open a terminal in the `/website` directory.
2. Run:
   ```bash
   python3 -m http.server 8000
   ```
3. Open your browser to `http://localhost:8000`.

### Method 3: Node `http-server`
If you have Node.js installed:
```bash
npx http-server ./
```

## How to Deploy to Firebase Hosting

To host this website on your existing Firebase project (`attendanceapp-e76e1`):

1. Initialize Firebase Hosting in the root of the project:
   ```bash
   npx firebase init hosting
   ```
2. Select your project `attendanceapp-e76e1`.
3. Set your public directory to `website`.
4. Run deploy:
   ```bash
   npx firebase deploy --only hosting
   ```
