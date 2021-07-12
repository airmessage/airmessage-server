package me.tagavari.airmessageserver.server;

import io.sentry.Sentry;
import me.tagavari.airmessageserver.connection.ClientRegistration;
import me.tagavari.airmessageserver.connection.CommConst;
import me.tagavari.airmessageserver.connection.ConnectionManager;

import java.io.*;
import java.util.*;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.logging.Level;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.InflaterOutputStream;

public class AppleScriptManager {
	//macOS 10
	//ARGS: Chat GUID / Message
	private static final String[] ASTextExisting = {
			"tell application \"Messages\"",
			
			//Getting target chat
			"set targetChat to text chat id \"%1$s\"",
			
			//Sending the message
			"send \"%2$s\" to targetChat",
			
			"end tell"
	};
	//macOS 11+
	//ARGS: Chat GUID / Message
	private static final String[] ASTextExisting11 = {
		"tell application \"Messages\"",
		
		//Getting target chat
		"set targetChat to chat id \"%1$s\"",
		
		//Sending the message
		"send \"%2$s\" to targetChat",
		
		"end tell"
	};
	//ARGS: Recipients / Message / Service
	private static final String[] ASTextNew = {
		"tell application \"Messages\"",
		
		//Getting the iMessage service
		"if \"%3$s\" is \"iMessage\" then",
		"set targetService to 1st service whose service type = iMessage",
		"else",
		"set targetService to service \"%3$s\"",
		"end if",
		
		//Splitting the recipient list
		/* "set oldDelimiters to AppleScript's text item delimiters",
		"set AppleScript's text item delimiters to \"" + appleScriptDelimiter + "\"",
		"set recipientList to every text item of \"%1$s\"",
		"set AppleScript's text item delimiters to oldDelimiters",
		"set recipientList to {%1$s}", */
		
		//Converting the recipients to iMessage buddies
		/* "set buddyList to {}",
		"repeat with currentRecipient in recipientList",
		"set currentBuddy to buddy currentRecipient of targetService",
		"copy currentBuddy to the end of buddyList",
		"end repeat", */
		
		//Creating the chat
		"set targetChat to make new text chat with properties {participants:{%1$s}}",
		
		//Sending the messages
		"send \"%2$s\" to targetChat",
		
		//Getting the chat info
		//"get targetChat",
		
		"end tell"
	};
	//macOS 11+ (single participant)
	//ARGS: Recipient / Message / Service
	private static final String[] ASTextNewSingle11 = {
		"tell application \"Messages\"",
		
		//Getting the service
		"set targetAccount to 1st account whose service type = %3$s",
		
		//Creating the chat
		"set targetParticipant to participant \"%1$s\" of targetAccount",
		
		//Sending the message
		"send \"%2$s\" to targetParticipant",
		
		"end tell"
	};
	//macOS 10
	//ARGS: Chat GUID / File
	private static final String[] ASFileExisting = {
			//Getting the file
			"set message to POSIX file \"%2$s\"",
			
			"tell application \"Messages\"",
			
			//Getting target chat
			"set targetChat to text chat id \"%1$s\"",
			
			//Sending the message
			"send message to targetChat",
			
			"end tell"
	};
	//macOS 11+
	//ARGS: Chat GUID / File
	private static final String[] ASFileExisting11 = {
			//Getting the file
			"set message to POSIX file \"%2$s\"",
	
			"tell application \"Messages\"",
	
			//Getting target chat
			"set targetChat to chat id \"%1$s\"",
	
			//Sending the message
			"send message to targetChat",
	
			"end tell"
	};
	//ARGS: Recipients / File / Service
	private static final String[] ASFileNew = {
			//Getting the file
			"set message to POSIX file \"%2$s\"",
			
			"tell application \"Messages\"",
			
			//Getting the iMessage service
			"if \"%3$s\" is \"iMessage\" then",
			"set targetService to 1st service whose service type = iMessage",
			"else",
			"set targetService to service \"%3$s\"",
			"end if",
			
			//Splitting the recipient list
			/* "set oldDelimiters to AppleScript's text item delimiters",
			"set AppleScript's text item delimiters to \"" + appleScriptDelimiter + "\"",
			"set recipientList to every text item of \"%1$s\"",
			"set AppleScript's text item delimiters to oldDelimiters",
			"set recipientList to {%1$s}", */
			
			//Converting the recipients to iMessage buddies
			/* "set buddyList to {}",
			"repeat with currentRecipient in recipientList",
			"set currentBuddy to buddy currentRecipient of targetService",
			"copy currentBuddy to the end of buddyList",
			"end repeat", */
			
			//Creating the chat
			"set targetChat to make new text chat with properties {participants:{%1$s}}",
			
			//Sending the messages
			"send message to targetChat",
			
			//Getting the chat info
			//"get targetChat",
			
			"end tell"
	};
	//ARGS: Recipients / Service
	private static final String[] ASCreateChat = {
			"tell application \"Messages\"",
			
			//Getting the service
			"if \"%2$s\" is \"iMessage\" then",
			"set targetService to 1st service whose service type = iMessage",
			"else",
			"set targetService to service \"%2$s\"",
			"end if",
			
			//Creating the chat
			"set targetChat to make new text chat with properties {participants:{%1$s}}",
			
			//Getting the chat info
			"get targetChat",
			
			"end tell"
	};
	private static final String[] ASAutomationTest = {
			"tell application \"Messages\"",
			"get first text chat",
			"end tell"
	};
	//ARGS: Message / Positive button / Negative button
	private static final String[] ASShowAutomationWarning = {
			"display dialog \"%1$s\" buttons {\"%2$s\", \"%3$s\"} cancel button \"%2$s\" default button \"%3$s\" with icon caution",
			
			"if button returned of result = \"%3$s\" then",
			"tell application \"System Preferences\"",
			"activate",
			"reveal anchor \"Privacy\" of pane id \"com.apple.preference.security\"",
			"end tell",
			"end if"
	};
	//ARGS: Message / Positive button / Negative button
	private static final String[] ASShowDiskAccessWarning = {
			"display dialog \"%1$s\" buttons {\"%2$s\", \"%3$s\"} cancel button \"%2$s\" default button \"%3$s\" with icon caution",
			
			"if button returned of result = \"%3$s\" then",
			"tell application \"System Preferences\"",
			"activate",
			"reveal anchor \"Privacy_AllFiles\" of pane id \"com.apple.preference.security\"",
			"end tell",
			"end if"
	};
	
	//private static final Pattern createChatResultPattern = Pattern.compile("\\Atext chat id \"(\\S+)\" of application \"Messages\"\\Z"); //text chat id "iMessage;+;chat175084451468489158" of application "Messages" <- ONLY FROM SCRIPTER OUTPUT
	private static final Pattern createChatResultPattern = Pattern.compile("\\Atext chat id (\\S+)\\Z"); //text chat id iMessage;+;chat428490767995230252 <- ACTUAL OUTPUT
	
	//Returns: result code, chat GUID (if successful) OR error message (if unsuccessful)
	public static Constants.Tuple<Integer, String> createChat(String[] chatMembers, String service) {
		//Returning false if there are no members
		if(chatMembers.length == 0) {
			Exception exception = new IllegalArgumentException("Bad request: no target members provided (send new file)");
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			return new Constants.Tuple<>(CommConst.nstCreateChatBadRequest, Constants.exceptionToString(exception));
		}
		
		//Formatting the chat members
		StringBuilder delimitedChatMembers = new StringBuilder("buddy \"" + escapeAppleScriptString(chatMembers[0]) + "\" of targetService");
		
		//Adding the remaining members
		for(int i = 1; i < chatMembers.length; i++) delimitedChatMembers.append(',').append("buddy \"").append(escapeAppleScriptString(chatMembers[i])).append("\" of targetService");
		
		//Building the command
		ArrayList<String> command = new ArrayList<>();
		command.add("osascript");
		for(String line : ASCreateChat) {
			command.add("-e");
			command.add(String.format(line, delimitedChatMembers.toString(), escapeAppleScriptString(service)));
		}
		
		//Running the command
		try {
			Process process = Runtime.getRuntime().exec(command.toArray(new String[0]));
			
			//Recording any errors
			{
				BufferedReader errorReader = new BufferedReader(new InputStreamReader(process.getErrorStream()));
				List<String> lineList = new ArrayList<>(1);
				String lsString;
				while((lsString = errorReader.readLine()) != null) {
					Main.getLogger().severe(lsString);
					lineList.add(lsString);
				}
				
				//Identifying the error
				if(!lineList.isEmpty()) {
					String errorDesc = String.join("\n", lineList);
					
					if(lineList.size() == 1) {
						String errorLine = lineList.get(0);
						if(errorLine.endsWith("(" + Constants.asErrorCodeMessagesUnauthorized + ")")) {
							return new Constants.Tuple<>(CommConst.nstCreateChatUnauthorized, errorDesc);
						}
					}
					
					return new Constants.Tuple<>(CommConst.nstCreateChatScriptError, errorDesc);
				}
			}
			
			{
				//Reading the message
				BufferedReader messageReader = new BufferedReader(new InputStreamReader(process.getInputStream()));
				List<String> lineList = new ArrayList<>(1);
				String lsString;
				while((lsString = messageReader.readLine()) != null) {
					//Main.getLogger().info(lsString);
					lineList.add(lsString);
				}
				
				if(lineList.isEmpty()) {
					Main.getLogger().log(Level.WARNING, "Failed to create new chat: received no output from chat creation script");
					return new Constants.Tuple<>(CommConst.nstCreateChatScriptError, "Received no output from chat creation script");
				}
				
				//OUTPUT FORMAT: text chat id iMessage;+;chat428490767995230252
				
				String outputLine = lineList.get(0);
				Matcher matcher = createChatResultPattern.matcher(outputLine);
				boolean result = matcher.find();
				if(!result) {
					Main.getLogger().log(Level.WARNING, "Failed to create new chat: couldn't match regex to \"" + outputLine + "\"");
					return new Constants.Tuple<>(CommConst.nstCreateChatScriptError, "Couldn't match regex to \"" + outputLine + "\"");
				}
				String chatGUID = matcher.group(1);
				
				return new Constants.Tuple<>(CommConst.nstCreateChatOK, chatGUID);
			}
		} catch(IOException exception) {
			//Printing the stack trace
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			
			//Returning the error
			return new Constants.Tuple<>(CommConst.nstCreateChatScriptError, Constants.exceptionToString(exception));
		}
	}
	
	public static Constants.Tuple<Integer, String> sendExistingMessage(String chatGUID, String message) {
		//Building the command
		ArrayList<String> command = new ArrayList<>();
		command.add("osascript");
		for(String line : Constants.compareVersions(Constants.getSystemVersion(), Constants.macOSBigSurVersion) >= 0 ? ASTextExisting11 : ASTextExisting) {
			command.add("-e");
			command.add(String.format(line, chatGUID, escapeAppleScriptString(message)));
		}
		
		//Running the command
		Constants.Tuple<Integer, String> result = runCommandProcessResult(command.toArray(new String[0]));
		
		//Attempting a fallback request if the request failed
		if(result.item1 == CommConst.nstSendResultNoConversation) {
			//Checking if the conversation has been indexed as a one-on-one chat
			DatabaseManager.CreationTargetingChat targetChat = DatabaseManager.getInstance().getCreationTargetingAvailabilityList().get(chatGUID);
			if(targetChat != null) {
				//Attempting to send the message as a new conversation
				return sendNewMessage(new String[]{targetChat.getAddress()}, message, targetChat.getService());
			}
		}
		
		//Returning the result
		return result;
	}
	
	public static Constants.Tuple<Integer, String> sendNewMessage(String[] chatMembers, String message, String service) {
		//Returning false if there are no members
		if(chatMembers.length == 0) return new Constants.Tuple<>(CommConst.nstSendResultBadRequest, Constants.exceptionToString(new IllegalArgumentException("Bad request: no target members provided (send new file)")));
		
		ArrayList<String> command = new ArrayList<>();
		
		//If there's only one member and we're on macOS 11, use our hacky workaround
		if(chatMembers.length == 1 && Constants.compareVersions(Constants.getSystemVersion(), Constants.macOSBigSurVersion) >= 0) {
			//Building the command
			command.add("osascript");
			for(String line : ASTextNewSingle11) {
				command.add("-e");
				command.add(String.format(line, escapeAppleScriptString(chatMembers[0]), escapeAppleScriptString(message), escapeAppleScriptString(service)));
			}
		} else {
			//Formatting the chat members
			StringBuilder delimitedChatMembers = new StringBuilder("buddy \"" + escapeAppleScriptString(chatMembers[0]) + "\" of targetService");
			
			//Adding the remaining members
			for(int i = 1; i < chatMembers.length; i++) delimitedChatMembers.append(',').append("buddy \"").append(escapeAppleScriptString(chatMembers[i])).append("\" of targetService");
			
			//Building the command
			command.add("osascript");
			for(String line : ASTextNew) {
				command.add("-e");
				command.add(String.format(line, delimitedChatMembers.toString(), escapeAppleScriptString(message), escapeAppleScriptString(service)));
			}
		}
		
		//Running the command
		Constants.Tuple<Integer, String> result = runCommandProcessResult(command.toArray(new String[0]));
		
		//Reindexing the creation targeting index
		DatabaseManager.getInstance().requestCreationTargetingAvailabilityUpdate();
		
		//Returning the result
		return result;
	}
	
	public static Constants.Tuple<Integer, String> sendExistingFile(String chatGUID, File file) {
		//Building the command
		ArrayList<String> command = new ArrayList<>();
		command.add("osascript");
		for(String line : Constants.compareVersions(Constants.getSystemVersion(), Constants.macOSBigSurVersion) >= 0 ? ASFileExisting11 : ASFileExisting) {
			command.add("-e");
			command.add(String.format(line, chatGUID, escapeAppleScriptString(file.getAbsolutePath())));
		}
		
		//Running the command
		Constants.Tuple<Integer, String> result = runCommandProcessResult(command.toArray(new String[0]));
		
		//Attempting a fallback request if the request failed
		if(result.item1 == CommConst.nstSendResultNoConversation) {
			//Checking if the conversation has been indexed as a one-on-one chat
			DatabaseManager.CreationTargetingChat targetChat = DatabaseManager.getInstance().getCreationTargetingAvailabilityList().get(chatGUID);
			if(targetChat != null) {
				//Attempting to send the message as a new conversation
				sendNewFile(new String[]{targetChat.getAddress()}, file, targetChat.getService());
			}
		}
		
		//Returning the result
		return result;
	}
	
	public static Constants.Tuple<Integer, String> sendNewFile(String[] chatMembers, File file, String service) {
		//Returning false if there are no members
		if(chatMembers.length == 0) return new Constants.Tuple<>(CommConst.nstSendResultBadRequest, Constants.exceptionToString(new IllegalArgumentException("Bad request: no target members provided (send new file)")));
		
		//Formatting the chat members
		StringBuilder delimitedChatMembers = new StringBuilder("buddy \"" + escapeAppleScriptString(chatMembers[0]) + "\" of targetService");
		
		//Adding the remaining members
		for(int i = 1; i < chatMembers.length; i++) delimitedChatMembers.append(',').append("buddy \"").append(escapeAppleScriptString(chatMembers[i])).append("\" of targetService");
		
		//Building the command
		ArrayList<String> command = new ArrayList<>();
		command.add("osascript");
		for(String line : ASFileNew) {
			command.add("-e");
			command.add(String.format(line, delimitedChatMembers.toString(), escapeAppleScriptString(file.getAbsolutePath()), escapeAppleScriptString(service)));
		}
		
		//Running the command
		Constants.Tuple<Integer, String> result = runCommandProcessResult(command.toArray(new String[0]));
		
		//Reindexing the creation targeting index
		DatabaseManager.getInstance().requestCreationTargetingAvailabilityUpdate();
		
		//Returning the result
		return result;
	}
	
	private static Constants.Tuple<Integer, String> runCommandProcessResult(String[] command) {
		//Running the command
		try {
			Process process = Runtime.getRuntime().exec(command);
			
			//Recording any errors
			BufferedReader errorReader = new BufferedReader(new InputStreamReader(process.getErrorStream()));
			List<String> lineList = new ArrayList<>(1);
			String lsString;
			while((lsString = errorReader.readLine()) != null) {
				Main.getLogger().log(Level.SEVERE, lsString);
				lineList.add(lsString);
			}
			
			//Identifying the error
			if(!lineList.isEmpty()) {
				String errorDesc = String.join("\n", lineList);
				
				if(lineList.size() == 1) {
					String errorLine = lineList.get(0);
					if(errorLine.endsWith("(" + Constants.asErrorCodeMessagesUnauthorized + ")")) return new Constants.Tuple<>(CommConst.nstSendResultUnauthorized, errorDesc);
					else if(errorLine.endsWith("(" + Constants.asErrorCodeMessagesNoChat + ")")) return new Constants.Tuple<>(CommConst.nstSendResultNoConversation, errorDesc);
				}
				
				return new Constants.Tuple<>(CommConst.nstSendResultScriptError, errorDesc);
			}
		} catch(IOException exception) {
			//Printing the stack trace
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			
			//Returning the error
			return new Constants.Tuple<>(CommConst.nstSendResultScriptError, Constants.exceptionToString(exception));
		}
		
		//Returning true
		return new Constants.Tuple<>(CommConst.nstSendResultOK, null);
	}
	
	public static boolean testAutomation() {
		//Building the command
		ArrayList<String> command = new ArrayList<>();
		command.add("osascript");
		for(String line : ASAutomationTest) {
			command.add("-e");
			command.add(line);
		}
		
		//Running the command
		try {
			Process process = Runtime.getRuntime().exec(command.toArray(new String[0]));
			
			//Returning false if there was any error
			BufferedReader errorReader = new BufferedReader(new InputStreamReader(process.getErrorStream()));
			boolean linesRead = false;
			String lsString;
			while ((lsString = errorReader.readLine()) != null) {
				if(!lsString.endsWith("(" + Constants.asErrorCodeMessagesUnauthorized + ")")) continue; //Error code for unauthorized. Sometimes, the executed command may return an error anyways if there are no messages.
				Main.getLogger().severe(lsString);
				linesRead = true;
			}
			
			if(linesRead) return false;
		} catch(IOException exception) {
			//Printing the stack trace
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			
			//Returning false
			return false;
		}
		
		//Returning true
		return true;
	}
	
	public static void showAutomationWarning() {
		runBasicAS(ASShowAutomationWarning, Main.resources().getString("message.automation_error"), Main.resources().getString("action.ignore"), Main.resources().getString("action.system_preferences"));
	}
	
	public static void showDiskAccessWarning() {
		runBasicAS(ASShowDiskAccessWarning, Main.resources().getString("message.disk_access_error"), Main.resources().getString("action.ignore"), Main.resources().getString("action.system_preferences"));
	}
	
	private static final List<FileUploadRequest> fileUploadRequests = Collections.synchronizedList(new ArrayList<>());
	public static void addFileFragment(ClientRegistration connection, short requestID, String chatGUID, String fileName, int index, byte[] compressedBytes, boolean isLast) {
		//Attempting to find a matching request
		FileUploadRequest request = null;
		for(FileUploadRequest allRequests : fileUploadRequests) {
			if(allRequests.connection != connection || allRequests.requestID != requestID || allRequests.chatGUID == null || !allRequests.chatGUID.equals(chatGUID)) continue;
			request = allRequests;
			break;
		}
		
		//Checking if the request is invalid (there is no request currently in the list)
		if(request == null) {
			//Checking if this isn't the first request (meaning that the request failed, and shouldn't continue)
			if(index != 0) {
				//Sending a negative response
				ConnectionManager.getCommunicationsManager().sendMessageRequestResponse(connection, CommConst.nhtSendResult, requestID, CommConst.nstSendResultBadRequest, "Bad request: index mismatch\nFirst index check failed, received " + index);
				
				//Returning
				return;
			}
			
			//Creating and adding a new request
			request = new FileUploadRequest(connection, requestID, chatGUID, fileName);
			fileUploadRequests.add(request);
			
			//Starting the timer
			request.startTimer();
		}
		//Otherwise restarting the timer
		else request.stopTimer(true);
		
		//Adding the file fragment
		request.addFileFragment(new FileUploadRequest.FileFragment(index, compressedBytes, isLast));
	}
	
	public static void addFileFragment(ClientRegistration connection, short requestID, String[] chatMembers, String service, String fileName, int index, byte[] compressedBytes, boolean isLast) {
		//Attempting to find a matching request
		FileUploadRequest request = null;
		for(FileUploadRequest allRequests : fileUploadRequests) {
			if(allRequests.connection != connection || allRequests.requestID != requestID || allRequests.chatMembers == null || !Arrays.equals(allRequests.chatMembers, chatMembers)) continue;
			request = allRequests;
			break;
		}
		
		//Checking if the request is invalid (there is no request currently in the list)
		if(request == null) {
			//Checking if this isn't the first request (meaning that the request failed, and shouldn't continue)
			if(index != 0) {
				//Sending a negative response
				ConnectionManager.getCommunicationsManager().sendMessageRequestResponse(connection, CommConst.nhtSendResult, requestID, CommConst.nstSendResultBadRequest, "Bad request: index mismatch\nFirst index check failed, received " + index);
				
				//Returning
				return;
			}
			
			//Creating and adding a new request
			request = new FileUploadRequest(connection, requestID, chatMembers, service, fileName);
			fileUploadRequests.add(request);
			
			//Starting the timer
			request.startTimer();
		}
		//Otherwise restarting the timer
		else request.stopTimer(true);
		
		//Adding the file fragment
		request.addFileFragment(new FileUploadRequest.FileFragment(index, compressedBytes, isLast));
	}
	
	private static class FileUploadRequest {
		//Creating the request variables
		final ClientRegistration connection;
		final short requestID;
		final String chatGUID;
		final String[] chatMembers;
		final String service;
		final String fileName;
		
		//Creating the transfer variables
		private Timer timeoutTimer = null;
		private static final int timeout = 10 * 1000; //10 seconds
		
		private AttachmentWriter writerThread = null;
		private int lastIndex = -1;
		
		FileUploadRequest(ClientRegistration connection, short requestID, String chatGUID, String fileName) {
			//Setting the variables
			this.connection = connection;
			this.requestID = requestID;
			this.chatGUID = chatGUID;
			this.chatMembers = null;
			this.service = null;
			this.fileName = fileName;
		}
		
		FileUploadRequest(ClientRegistration connection, short requestID, String[] chatMembers, String service, String fileName) {
			//Setting the variables
			this.connection = connection;
			this.requestID = requestID;
			this.chatGUID = null;
			this.chatMembers = chatMembers;
			this.service = service;
			this.fileName = fileName;
		}
		
		void addFileFragment(FileFragment fileFragment) {
			//Failing the request if the index doesn't line up
			if(lastIndex + 1 != fileFragment.index) {
				failRequest(CommConst.nstSendResultBadRequest, Constants.exceptionToString(new IllegalArgumentException("Bad request: index mismatch\nLast index: " + lastIndex + "\nReceived index: " + fileFragment.index)));
				return;
			}
			
			//Checking if this is the last fragment
			if(fileFragment.isLast) {
				//Stopping the timer
				stopTimer(false);
			}
			
			//Updating the index
			lastIndex = fileFragment.index;
			
			//Checking if there is no writer thread
			if(writerThread == null) {
				//Creating the attachment writer thread
				writerThread = new AttachmentWriter(fileName);
				
				//Starting the thread
				writerThread.start();
			}
			
			//Adding the file fragment
			writerThread.dataQueue.add(fileFragment);
		}
		
		void startTimer() {
			timeoutTimer = new Timer();
			timeoutTimer.schedule(new TimerTask() {
				@Override
				public void run() {
					//Failing the request
					failRequest(CommConst.nstSendResultRequestTimeout, null);
				}
			}, timeout);
		}
		
		void stopTimer(boolean restart) {
			if(timeoutTimer != null) timeoutTimer.cancel();
			if(restart) startTimer();
			else timeoutTimer = null;
		}
		
		private void failRequest(int result, String details) {
			//Removing the request from the list
			fileUploadRequests.remove(this);
			
			//Stopping the timer
			stopTimer(false);
			
			//Stopping the thread
			if(writerThread != null) writerThread.stopThread();
			
			//Sending a negative response
			ConnectionManager.getCommunicationsManager().sendMessageRequestResponse(connection, CommConst.nhtSendResult, requestID, result, details);
		}
		
		private void onDownloadSuccessful(File file) {
			//Removing the request from the list
			fileUploadRequests.remove(this);
			
			//Sending the file
			Constants.Tuple<Integer, String> result = chatGUID != null ? sendExistingFile(chatGUID, file) : sendNewFile(chatMembers, file, service);
			
			//Sending the response
			ConnectionManager.getCommunicationsManager().sendMessageRequestResponse(connection, CommConst.nhtSendResult, requestID, result.item1, result.item2);
		}
		
		private class AttachmentWriter extends Thread {
			//Creating the queue
			private final BlockingQueue<FileFragment> dataQueue = new LinkedBlockingQueue<>();
			
			//Creating the request values
			private final String fileName;
			
			//Creating the process values
			private File targetDir;
			private File targetFile;
			private final AtomicBoolean requestKill = new AtomicBoolean(false);
			
			AttachmentWriter(String fileName) {
				this.fileName = fileName;
			}
			
			@Override
			public void run() {
				//Creating the upload directory if it doesn't exist
				if(Constants.uploadDir.isFile()) Constants.uploadDir.delete();
				if(!Constants.uploadDir.exists()) Constants.uploadDir.mkdir();
				
				//Finding the save file
				targetDir = Constants.findFreeFile(Constants.uploadDir, Long.toString(System.currentTimeMillis()));
				targetDir.mkdir();
				targetFile = new File(targetDir, fileName);
				
				try(OutputStream out = new InflaterOutputStream(new BufferedOutputStream(new FileOutputStream(targetFile)))) {
					while(!requestKill.get()) {
						//Getting the data struct
						FileFragment fileFragment = dataQueue.poll(timeout, TimeUnit.MILLISECONDS);
						
						//Skipping the remainder of the iteration if the file fragment is invalid
						if(fileFragment == null) continue;
						
						//Writing the file to disk
						out.write(fileFragment.compressedData);
						
						//Checking if the file is the last one
						if(fileFragment.isLast) {
							//Completing the stream
							out.flush();
							out.close();
							
							//Calling the download successful method
							onDownloadSuccessful(targetFile);
							
							//Returning
							return;
						}
					}
				} catch(IOException | InterruptedException | OutOfMemoryError exception) {
					//Printing the stack trace
					Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
					Sentry.captureException(exception);
					
					//Failing the download
					failRequest(CommConst.nstSendResultBadRequest, Constants.exceptionToString(exception));
					
					//Terminating the thread
					requestKill.set(true);
				}
				
				//Checking if the thread was stopped
				if(requestKill.get()) {
					//Cleaning up
					Constants.recursiveDelete(targetDir);
				}
			}
			
			void stopThread() {
				requestKill.set(true);
			}
		}
		
		static class FileFragment {
			int index;
			byte[] compressedData;
			boolean isLast;
			
			FileFragment(int index, byte[] compressedData, boolean isLast) {
				this.index = index;
				this.compressedData = compressedData;
				this.isLast = isLast;
			}
		}
	}
	
	private static String escapeAppleScriptString(String string) {
		return string.replace("\\", "\\\\").replace("\"", "\\\"");
	}
	
	private static void runBasicAS(String[] commandLines, String... arguments) {
		//Building the command
		ArrayList<String> command = new ArrayList<>();
		command.add("osascript");
		for(String line : commandLines) {
			command.add("-e");
			command.add(String.format(line, (Object[]) arguments));
		}
		
		try {
			Runtime.getRuntime().exec(command.toArray(new String[0]));
		} catch(IOException exception) {
			//Printing the stack trace
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
		}
	}
	
	/* private static boolean isFatalResponse(String line) {
		return line.startsWith("execution error");
	} */
}