import i18n from "i18next";
import LanguageDetector from "i18next-browser-languagedetector";

i18n.use(LanguageDetector).init({
  resources: {
    en: {
      translations: {
        "Dashboard": "Dashboard",
        "Order History": "Order History",
        "Help": "Help",
        "Profile": "Profile",
        "Hello": "Hello",
        "Users": "Users",
        "Logout": "Logout",
        "Signup &amp; Login": "Signup & Login",
        "Already have an account?": "Already have an account?",
        "Login here": "Login here",
        "Signup": "Signup",
      }
    },
    ur: {
      translations: {
        "Dashboard": "ڈیش بورڈ",
        "Order History": "آرڈر کی تاریخ",
        "Help": "مدد",
        "Profile": "پروفائل",
        "Hello": "ہیلو",
        "Logout": "لاگ آوٹ",
        "Users": "صارف",
        "Signup &amp; Login": "سائن اپ اور لاگ ان",
        "Already have an account?": "پہلے سے ہی ایک اکاؤنٹ ہے؟",
        "Login here": "یہاں لاگ ان کریں",
        "Signup": "سائن اپ",
      }
    }
  },
  fallbackLng: "en",

  // uncomment below line to debuging translations
  // debug: true,

  // have a common namespace used around the full app
  ns: ["translations"],
  defaultNS: "translations",
  keySeparator: false, // we use content as keys
  interpolation: {
    escapeValue: false, // not needed for react!!
    formatSeparator: ","
  },
  react: {
    wait: true
  }
});

export default i18n;

