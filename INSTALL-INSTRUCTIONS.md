# Strength Tracker PWA - Installation Guide

Your Strength Training Tracker is now a Progressive Web App (PWA)! This means you can install it on your phone and use it like a native app.

## Files Included

1. **strength-tracker.html** - Main HTML file with PWA support
2. **strength-tracker.jsx** - The React app (same as before)
3. **manifest.json** - PWA manifest with app metadata
4. **service-worker.js** - Enables offline functionality

## How to Deploy & Install

### Option A: Using a Simple Web Server

1. **Upload all 4 files to a web hosting service:**
   - Any web host (Netlify, Vercel, GitHub Pages, etc.)
   - Keep all files in the same directory
   - Make sure HTTPS is enabled (required for PWA)

2. **Access the URL in your phone's browser**
   - iOS: Open in Safari
   - Android: Open in Chrome

3. **Install the app:**
   
   **iOS (iPhone/iPad):**
   - Tap the Share button (square with arrow up)
   - Scroll down and tap "Add to Home Screen"
   - Name it "Strength Tracker" and tap "Add"
   
   **Android:**
   - Chrome will show an "Install" banner automatically
   - OR tap the three-dot menu → "Install app"
   - Confirm installation

### Option B: Testing Locally (For Development)

1. Install a simple web server:
   ```bash
   # Using Python
   python3 -m http.server 8000
   
   # OR using Node.js
   npx serve
   ```

2. Open `http://localhost:8000/strength-tracker.html` in your browser

3. For phone testing on local network:
   - Find your computer's IP address
   - Access `http://YOUR_IP:8000/strength-tracker.html` from your phone
   - Note: Service worker requires HTTPS in production

## Features You Get

✅ **Offline Access** - Works without internet after first load
✅ **App Icon** - Custom dumbbell icon on your home screen
✅ **Full Screen** - No browser UI when running
✅ **Fast Loading** - Cached for instant startup
✅ **Native Feel** - Smooth, app-like experience
✅ **Data Persistence** - All workout data saved locally

## Troubleshooting

**App won't install:**
- Make sure you're using HTTPS (not HTTP)
- Clear browser cache and try again
- On iOS, must use Safari browser
- On Android, must use Chrome browser

**Data not saving:**
- Check browser storage permissions
- Ensure you have sufficient storage space
- Don't use private/incognito mode

**App won't work offline:**
- Open the app online at least once first
- Service worker needs initial cache
- Check if service worker registered (browser dev tools)

## Recommended Free Hosting

- **Netlify**: Drop files and get instant HTTPS
- **Vercel**: Same as Netlify, very easy
- **GitHub Pages**: Free HTTPS hosting via GitHub
- **Cloudflare Pages**: Fast and free

All of these provide free HTTPS hosting which is required for PWA features to work properly.
