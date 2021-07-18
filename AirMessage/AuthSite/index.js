import firebase from "firebase/app";
import "firebase/auth";
import * as firebaseui from "firebaseui";
import {firebaseConfig} from "./secrets";

// Initialize Firebase
firebase.initializeApp(firebaseConfig);

// Initialize the FirebaseUI Widget using Firebase.
const ui = new firebaseui.auth.AuthUI(firebase.auth());

// The start method will wait until the DOM is loaded.
ui.start("#firebaseui-auth-container", {
	callbacks: {
		signInSuccessWithAuthResult: (authResult) => {
			// Send back to Mac app
			window.webkit.messageHandlers.confirmHandler.postMessage({
				refreshToken: authResult.user.refreshToken
			});
			
			// Disable automatic redirect
			return false;
		}
	},
	signInOptions: [
		{
			provider: firebase.auth.GoogleAuthProvider.PROVIDER_ID,
			customParameters: {
				// Forces account selection even when one account is available
				prompt: "select_account"
			}
		}
	]
});
