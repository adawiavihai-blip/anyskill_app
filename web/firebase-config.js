const firebaseConfig = {
  apiKey: "AIzaSyDybWlbmpqTG-cvqxTQrirtDsqv17LBHzk",
  projectId: "anyskill-6fdf3",
  messagingSenderId: "1056580918501",
  appId: "1:1056580918501:web:4f0d36c57f7396c4d35eb7"
};

if (!firebase.apps.length) {
    firebase.initializeApp(firebaseConfig);
    firebase.functions(); // אתחול שירותי ענן לתשלומים
    console.log("✅ AnySkill Services: Firestore, Auth & Functions Connected");
}