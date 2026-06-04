// Firebase web client for phone auth. The config values are public client
// identifiers (they ship in the bundle by design), matching the iOS app's
// GoogleService-Info.plist project (slide-b4c50).
import { initializeApp, getApps, type FirebaseApp } from "firebase/app";
import { getAuth, type Auth } from "firebase/auth";

const firebaseConfig = {
  apiKey: "AIzaSyDczWcSPLK2CrW0mtRIlFo8jWT-u-B90_o",
  authDomain: "slide-b4c50.firebaseapp.com",
  projectId: "slide-b4c50",
  storageBucket: "slide-b4c50.firebasestorage.app",
  messagingSenderId: "561354442144",
  appId: "1:561354442144:web:262e773743ebd2ffc650c5",
};

let app: FirebaseApp | null = null;

export function firebaseApp(): FirebaseApp {
  if (!app) {
    app = getApps().length ? getApps()[0] : initializeApp(firebaseConfig);
  }
  return app;
}

export function firebaseAuth(): Auth {
  return getAuth(firebaseApp());
}
