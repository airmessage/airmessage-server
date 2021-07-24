package me.tagavari.airmessageserver.server;

import io.sentry.Sentry;
import me.tagavari.airmessageserver.connection.ClientRegistration;
import me.tagavari.airmessageserver.connection.CommConst;
import me.tagavari.airmessageserver.connection.ConnectionManager;
import me.tagavari.airmessageserver.exception.AppleScriptException;
import me.tagavari.airmessageserver.jni.JNIMessage;

import java.io.*;
import java.util.*;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.logging.Level;
import java.util.zip.InflaterOutputStream;

public class UploadHelper {
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
		
		private FileUploadRequest.AttachmentWriter writerThread = null;
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
		
		void addFileFragment(FileUploadRequest.FileFragment fileFragment) {
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
				writerThread = new FileUploadRequest.AttachmentWriter(fileName);
				
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
			try {
				if(chatGUID != null) {
					JNIMessage.sendExistingFile(chatGUID, file.getAbsolutePath());
				} else {
					JNIMessage.sendNewFile(chatMembers, service, file.getAbsolutePath());
				}
				
				//Sending the response
				ConnectionManager.getCommunicationsManager().sendMessageRequestResponse(connection, CommConst.nhtSendResult, requestID, CommConst.nstSendResultOK, null);
			} catch(AppleScriptException exception) {
				var details = exception.getSendErrorDetails();
				ConnectionManager.getCommunicationsManager().sendMessageRequestResponse(connection, CommConst.nhtSendResult, requestID, details.item1, details.item2);
			}
		}
		
		private class AttachmentWriter extends Thread {
			//Creating the queue
			private final BlockingQueue<FileUploadRequest.FileFragment> dataQueue = new LinkedBlockingQueue<>();
			
			//Creating the request values
			private final String fileName;
			
			//Creating the process values
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
				File targetDir = Constants.findFreeFile(Constants.uploadDir, Long.toString(System.currentTimeMillis()));
				targetDir.mkdir();
				File targetFile = new File(targetDir, fileName);
				
				try(OutputStream out = new InflaterOutputStream(new BufferedOutputStream(new FileOutputStream(targetFile)))) {
					while(!requestKill.get()) {
						//Getting the data struct
						FileUploadRequest.FileFragment fileFragment = dataQueue.poll(timeout, TimeUnit.MILLISECONDS);
						
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
		
		static record FileFragment(int index, byte[] compressedData, boolean isLast) {}
	}
}