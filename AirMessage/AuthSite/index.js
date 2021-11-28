import {initializeApp} from "firebase/app";
import {getAuth, getIdToken, GoogleAuthProvider} from "firebase/auth";
import * as firebaseui from "firebaseui";
import {firebaseConfig} from "./secrets";

//Initialize Firebase
initializeApp(firebaseConfig);

//Initialize the FirebaseUI Widget using Firebase
const ui = new firebaseui.auth.AuthUI(getAuth());

//The start method will wait until the DOM is loaded
ui.start("#firebaseui-auth-container", {
	callbacks: {
		signInSuccessWithAuthResult: (authResult) => {
			document.getElementById("desc").innerHTML = "Return to AirMessage to finish signing in";
			
			const refreshToken = authResult.user.refreshToken;
			
			//Get response method
			const xhr = new XMLHttpRequest();
			xhr.responseType = "text";
			xhr.open("POST", "/method");
			xhr.onload = () => {
				//Send response back to Mac app
				const method = xhr.responseText;
				if(method === "scheme") {
					window.location.href = `airmessageauth:firebase?refreshToken=${refreshToken}`;
				} else if(method === "post") {
					const xhr = new XMLHttpRequest();
					xhr.open("POST", `submit/?refreshToken=${refreshToken}`);
					xhr.send();
				}
			};
			xhr.send();
			
			//Disable automatic redirect
			return false;
		}
	},
	signInOptions: [
		{
			provider: GoogleAuthProvider.PROVIDER_ID,
			customParameters: {
				// Forces account selection even when one account is available
				prompt: "select_account"
			}
		}
	]
});
