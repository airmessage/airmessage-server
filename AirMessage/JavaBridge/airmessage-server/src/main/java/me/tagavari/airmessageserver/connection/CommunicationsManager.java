package me.tagavari.airmessageserver.connection;

import io.sentry.Breadcrumb;
import io.sentry.Sentry;
import me.tagavari.airmessageserver.common.AirPacker;
import me.tagavari.airmessageserver.common.AirUnpacker;
import me.tagavari.airmessageserver.common.Blocks;
import me.tagavari.airmessageserver.exception.LargeAllocationException;
import me.tagavari.airmessageserver.jni.JNIPreferences;
import me.tagavari.airmessageserver.jni.JNIUserInterface;
import me.tagavari.airmessageserver.request.*;
import me.tagavari.airmessageserver.server.*;
import org.jooq.impl.DSL;

import java.nio.BufferOverflowException;
import java.nio.BufferUnderflowException;
import java.security.GeneralSecurityException;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.logging.Level;

public class CommunicationsManager implements DataProxyListener<ClientRegistration> {
	//Creating the communications values
	protected final DataProxy<ClientRegistration> dataProxy;
	
	//Creating the state values
	private final Timer keepAliveTimer = new Timer();
	
	public CommunicationsManager(DataProxy<ClientRegistration> dataProxy) {
		this.dataProxy = dataProxy;
	}
	
	public DataProxy<ClientRegistration> getDataProxy() {
		return dataProxy;
	}
	
	private final AtomicBoolean isRunning = new AtomicBoolean(false);
	
	public void start() {
		//Returning if the server is already running
		if(isRunning.get()) return;
		
		//Setting the server as running
		isRunning.set(true);
		
		//Registering a listener
		dataProxy.addMessageListener(this);
		
		//Starting the proxy
		dataProxy.startServer();
	}
	
	public void stop() {
		//Returning if the server isn't running
		if(!isRunning.get()) return;
		
		//Disconnecting the proxy
		dataProxy.stopServer();
		
		//Unregistering the listener
		dataProxy.removeMessageListener(this);
		
		//Calling the stop procedure
		onStop(ServerState.STOPPED);
	}
	
	public boolean isRunning() {
		return isRunning.get();
	}
	
	@Override
	public void onStart() {
		//Updating the state
		Main.postMainThread(() -> Main.setServerState(ServerState.RUNNING));
		
		//Starting the keepalive timer
		if(dataProxy.requiresPersistence()) {
			keepAliveTimer.scheduleAtFixedRate(new TimerTask() {
				@Override
				public void run() {
					//Sending a ping to all connected clients
					boolean result = sendMessageHeaderOnly(null, CommConst.nhtPing, false);
					
					//Starting ping response timers
					if(result) {
						for(ClientRegistration connection : dataProxy.getConnections()) {
							connection.startPingExpiryTimer(CommConst.pingTimeout, () -> initiateClose(connection));
						}
					}
				}
			}, CommConst.keepAliveMillis, CommConst.keepAliveMillis);
		}
		
		Main.getLogger().info("Server started");
	}
	
	@Override
	public void onPause(ServerState code) {
		//Updating the state
		Main.postMainThread(() -> Main.setServerState(code));
		
		//Cancelling the keepalive timer
		if(dataProxy.requiresPersistence()) {
			keepAliveTimer.cancel();
		}
		
		Main.getLogger().info("Server paused");
	}
	
	@Override
	public void onStop(ServerState code) {
		//Updating the state
		Main.postMainThread(() -> Main.setServerState(code));
		
		//Setting the server as not running
		isRunning.set(false);
		
		//Cancelling the keepalive timer
		if(dataProxy.requiresPersistence()) {
			keepAliveTimer.cancel();
		}
		
		Main.getLogger().info("Server stopped");
	}
	
	@Override
	public void onOpen(ClientRegistration client) {
		if(dataProxy.requiresAuthentication()) {
			//Generating the transmission check
			byte[] transmissionCheck = new byte[CommConst.transmissionCheckLength];
			Main.getSecureRandom().nextBytes(transmissionCheck);
			client.setTransmissionCheck(transmissionCheck);
			
			//Sending this server's information with the transmission check
			try(AirPacker packer = AirPacker.get()) {
				packer.packInt(CommConst.nhtInformation);
				
				packer.packInt(CommConst.mmCommunicationsVersion);
				packer.packInt(CommConst.mmCommunicationsSubVersion);
				
				packer.packBoolean(true); //Transmission check required
				packer.packPayload(transmissionCheck);
				
				byte[] data = packer.toByteArray();
				dataProxy.sendMessage(client, data, false);
			} catch(BufferOverflowException exception) {
				exception.printStackTrace();
			}
		} else {
			//Sending this server's information without the transmission check
			try(AirPacker packer = AirPacker.get()) {
				packer.packInt(CommConst.nhtInformation);
				
				packer.packInt(CommConst.mmCommunicationsVersion);
				packer.packInt(CommConst.mmCommunicationsSubVersion);
				
				packer.packBoolean(false); //Transmission check not required
				
				dataProxy.sendMessage(client, packer.toByteArray(), false);
			} catch(BufferOverflowException exception) {
				exception.printStackTrace();
			}
		}
		
		//Starting the handshake expiry timer
		client.startHandshakeExpiryTimer(CommConst.handshakeTimeout, () -> initiateClose(client));
		
		//Updating the displayed connection count
		Main.postMainThread(() -> JNIUserInterface.updateConnectionCount(ConnectionManager.getConnectionCount()));
	}
	
	@Override
	public void onClose(ClientRegistration client) {
		//Updating the UI
		Main.postMainThread(() -> JNIUserInterface.updateConnectionCount(ConnectionManager.getConnectionCount()));
	}
	
	@Override
	public void onMessage(ClientRegistration client, byte[] data, boolean wasEncrypted) {
		//Resetting the ping timer
		client.cancelPingExpiryTimer();
		
		//Wrapping the data in an unpacker
		AirUnpacker unpacker = new AirUnpacker(data);
		try {
			//Reading the message type
			int messageType = unpacker.unpackInt();
			
			//Logging the event
			{
				int contentLength = data.length;
				
				//Adding a breadcrumb
				Breadcrumb breadcrumb = new Breadcrumb();
				breadcrumb.setCategory(Constants.sentryBCatPacket);
				breadcrumb.setMessage("New packet received");
				breadcrumb.setData("Message type", messageType);
				breadcrumb.setData("Content length", contentLength);
				Sentry.addBreadcrumb(breadcrumb);
				
				Main.getLogger().log(Level.FINEST, "New message received: " + messageType + " / " + contentLength);
			}
			
			if(wasEncrypted) processMessageSecure(client, messageType, unpacker);
			else processMessageInsecure(client, messageType, unpacker);
		} catch(BufferUnderflowException | LargeAllocationException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
		}
	}
	
	private boolean processMessageInsecure(ClientRegistration client, int messageType, AirUnpacker unpacker) throws BufferUnderflowException, LargeAllocationException {
		//Responding to standard requests
		switch(messageType) {
			case CommConst.nhtClose -> dataProxy.disconnectClient(client);
			case CommConst.nhtPing -> sendMessageHeaderOnly(client, CommConst.nhtPong, false);
			case CommConst.nhtAuthentication -> handleMessageAuthentication(client, unpacker);
			default -> {
				return false;
			}
		}
		
		return true;
	}
	
	private boolean processMessageSecure(ClientRegistration client, int messageType, AirUnpacker unpacker) throws BufferUnderflowException, LargeAllocationException {
		if(processMessageInsecure(client, messageType, unpacker)) return true;
		
		//The client can't perform any sensitive tasks unless they are authenticated
		if(!client.isClientRegistered()) return false;
		
		switch(messageType) {
			case CommConst.nhtTimeRetrieval -> handleMessageTimeRetrieval(client, unpacker);
			case CommConst.nhtIDRetrieval -> handleMessageIDRetrieval(client, unpacker);
			case CommConst.nhtMassRetrieval -> handleMessageMassRetrieval(client, unpacker);
			case CommConst.nhtConversationUpdate -> handleMessageConversationUpdate(client, unpacker);
			case CommConst.nhtAttachmentReq -> handleMessageAttachmentRequest(client, unpacker);
			
			case CommConst.nhtLiteConversationRetrieval -> handleMessageLiteConversationRetrieval(client, unpacker);
			case CommConst.nhtLiteThreadRetrieval -> handleMessageLiteThreadRetrieval(client, unpacker);
			
			case CommConst.nhtCreateChat -> handleMessageCreateChat(client, unpacker);
			case CommConst.nhtSendTextExisting -> handleMessageSendTextExisting(client, unpacker);
			case CommConst.nhtSendTextNew -> handleMessageSendTextNew(client, unpacker);
			case CommConst.nhtSendFileExisting -> handleMessageSendFileExisting(client, unpacker);
			case CommConst.nhtSendFileNew -> handleMessageSendFileNew(client, unpacker);
			default -> {
				return false;
			}
		}
		
		return true;
	}
	
	private void handleMessageAuthentication(ClientRegistration client, AirUnpacker unpacker) throws BufferUnderflowException, LargeAllocationException {
		//Stopping the registration timer
		client.cancelHandshakeExpiryTimer();
		
		String installationID;
		String clientName, platformID;
		
		if(dataProxy.requiresAuthentication()) {
			byte[] transmissionCheck;
			try {
				//Decrypting the message
				byte[] secureData = EncryptionHelper.decrypt(unpacker.unpackPayload());
				
				//Reading the data
				AirUnpacker secureUnpacker = new AirUnpacker(secureData);
				transmissionCheck = secureUnpacker.unpackPayload();
				installationID = secureUnpacker.unpackString();
				clientName = secureUnpacker.unpackString();
				platformID = secureUnpacker.unpackString();
			} catch(GeneralSecurityException exception) {
				//Logging the exception
				Main.getLogger().log(Level.INFO, exception.getMessage(), exception);
				
				//Sending a message and closing the connection
				try(AirPacker packer = AirPacker.get()) {
					packer.packInt(CommConst.nhtAuthentication);
					packer.packInt(CommConst.nstAuthenticationUnauthorized);
					dataProxy.sendMessage(client, packer.toByteArray(), false, () -> initiateClose(client));
				}
				
				return;
			} catch(BufferOverflowException | LargeAllocationException exception) {
				//Logging the exception
				Main.getLogger().log(Level.INFO, exception.getMessage(), exception);
				
				//Sending a message and closing the connection
				try(AirPacker packer = AirPacker.get()) {
					packer.packInt(CommConst.nhtAuthentication);
					packer.packInt(CommConst.nstAuthenticationBadRequest);
					dataProxy.sendMessage(client, packer.toByteArray(), false, () -> initiateClose(client));
				}
				
				return;
			}
			
			//Checking if the transmission check fails
			if(!client.checkClearTransmissionCheck(transmissionCheck)) {
				//Sending a message and closing the connection
				try(AirPacker packer = AirPacker.get()) {
					packer.packInt(CommConst.nhtAuthentication);
					packer.packInt(CommConst.nstAuthenticationUnauthorized);
					dataProxy.sendMessage(client, packer.toByteArray(), false, () -> initiateClose(client));
				}
				
				//Returning
				return;
			}
		} else {
			//Reading the data plainly
			installationID = unpacker.unpackString();
			clientName = unpacker.unpackString();
			platformID = unpacker.unpackString();
		}
		
		//Disconnecting clients with the same installation ID
		Collection<ClientRegistration> connections = new HashSet<>(dataProxy.getConnections()); //Avoid concurrent modifications
		for(ClientRegistration connectedClient : connections) {
			if(installationID.equals(connectedClient.getInstallationID())) {
				Main.getLogger().log(Level.INFO, "Closing old connection for " + connectedClient.getClientName());
				initiateClose(connectedClient);
			}
		}
		
		//Marking the client as registered
		client.setClientRegistered(true);
		client.setRegistration(installationID, clientName, platformID);
		
		//Sending a message
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(CommConst.nhtAuthentication);
			packer.packInt(CommConst.nstAuthenticationOK);
			packer.packString(JNIPreferences.getInstallationID()); //Installation ID
			packer.packString(Main.getDeviceName()); //Device name
			packer.packString(System.getProperty("os.version")); //System version
			packer.packString(Constants.SERVER_VERSION); //Software version
			
			dataProxy.sendMessage(client, packer.toByteArray(), true);
		}
		
		//Sending the client the latest database entry ID
		long latestEntryID = DatabaseManager.getInstance().getLatestEntryID();
		if(latestEntryID != -1) {
			sendIDUpdate(client, latestEntryID);
		}
	}
	
	private void handleMessageTimeRetrieval(ClientRegistration client, AirUnpacker unpacker) throws BufferUnderflowException {
		//Reading the request data
		long timeLower = unpacker.unpackLong();
		long timeUpper = unpacker.unpackLong();
		
		//Creating a new request and queuing it
		DatabaseManager.getInstance().addClientRequest(new CustomRetrievalRequest(
			client,
			new DatabaseManager.RetrievalFilter(DSL.field("message.date").greaterThan(Main.getTimeHelper().toDatabaseTime(timeLower)).and(DSL.field("message.date").lessThan(Main.getTimeHelper().toDatabaseTime(timeUpper))), -1, null),
			CommConst.nhtTimeRetrieval));
		DatabaseManager.getInstance().addClientRequest(new ReadReceiptRequest(client, timeLower));
	}
	
	private void handleMessageIDRetrieval(ClientRegistration client, AirUnpacker unpacker) throws BufferUnderflowException {
		//Reading the request data
		long idSince = unpacker.unpackLong();
		long timeLower = unpacker.unpackLong();
		long timeUpper = unpacker.unpackLong();
		
		//Creating a new request and queuing it
		DatabaseManager.getInstance().addClientRequest(new CustomRetrievalRequest(
			client,
			new DatabaseManager.RetrievalFilter(DSL.field("message.ROWID").greaterThan(idSince), -1, null),
			CommConst.nhtIDRetrieval));
		DatabaseManager.getInstance().addClientRequest(new ReadReceiptRequest(client, timeLower));
	}
	
	private void handleMessageMassRetrieval(ClientRegistration client, AirUnpacker unpacker) throws BufferUnderflowException, LargeAllocationException {
		//Reading the request data
		short requestID = unpacker.unpackShort(); //The request ID to avoid collisions
		
		boolean restrictMessages = unpacker.unpackBoolean(); //Should we filter messages by date?
		long timeSinceMessages = restrictMessages ? unpacker.unpackLong() : -1; //If so, download messages since when?
		
		boolean downloadAttachments = unpacker.unpackBoolean(); //Should we download attachments
		boolean restrictAttachmentsDate = false; //Should we filter attachments by date?
		long timeSinceAttachments = -1; //If so, download attachments since when?
		boolean restrictAttachmentsSize = false; //Should we filter attachments by size?
		long attachmentsSizeLimit = -1; //If so, download attachments smaller than how many bytes?
		
		String[] attachmentFilterWhitelist = null; //Only download attachment files if they're on this list
		String[] attachmentFilterBlacklist = null; //Don't download attachment files if they're on this list
		boolean attachmentFilterDLOther = false; //Download attachment files if they're not on either list
		
		if(downloadAttachments) {
			restrictAttachmentsDate = unpacker.unpackBoolean();
			if(restrictAttachmentsDate) timeSinceAttachments = unpacker.unpackLong();
			
			restrictAttachmentsSize = unpacker.unpackBoolean();
			if(restrictAttachmentsSize) attachmentsSizeLimit = unpacker.unpackLong();
			
			attachmentFilterWhitelist = new String[unpacker.unpackArrayHeader()];
			for(int i = 0; i < attachmentFilterWhitelist.length; i++) attachmentFilterWhitelist[i] = unpacker.unpackString();
			attachmentFilterBlacklist = new String[unpacker.unpackArrayHeader()];
			for(int i = 0; i < attachmentFilterBlacklist.length; i++) attachmentFilterBlacklist[i] = unpacker.unpackString();
			attachmentFilterDLOther = unpacker.unpackBoolean();
		}
		
		//Creating a new request and queuing it
		DatabaseManager.getInstance().addClientRequest(new MassRetrievalRequest(client, requestID, restrictMessages, timeSinceMessages, downloadAttachments, restrictAttachmentsDate, timeSinceAttachments, restrictAttachmentsSize, attachmentsSizeLimit, attachmentFilterWhitelist, attachmentFilterBlacklist, attachmentFilterDLOther));
	}
	
	private void handleMessageConversationUpdate(ClientRegistration client, AirUnpacker unpacker) throws BufferUnderflowException, LargeAllocationException {
		//Reading the chat GUID list
		String[] chatGUIDs = new String[unpacker.unpackArrayHeader()];
		for(int i = 0; i < chatGUIDs.length; i++) chatGUIDs[i] = unpacker.unpackString();
		
		//Creating a new request and queuing it
		DatabaseManager.getInstance().addClientRequest(new ConversationInfoRequest(client, chatGUIDs));
	}
	
	private void handleMessageAttachmentRequest(ClientRegistration client, AirUnpacker unpacker) throws BufferUnderflowException, LargeAllocationException {
		//Reading the request information
		short requestID = unpacker.unpackShort(); //The request ID to avoid collisions
		int chunkSize = unpacker.unpackInt(); //How many bytes to upload per packet
		String fileGUID = unpacker.unpackString(); //The GUID of the file to download
		
		//Sending a reply
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(CommConst.nhtAttachmentReqConfirm);
			packer.packShort(requestID);
			
			dataProxy.sendMessage(client, packer.toByteArray(), true);
		}
		
		//Adding the request
		DatabaseManager.getInstance().addClientRequest(new FileRequest(client, fileGUID, requestID, chunkSize));
	}
	
	private void handleMessageLiteConversationRetrieval(ClientRegistration client, AirUnpacker unpacker) throws BufferUnderflowException {
		//Adding the request
		DatabaseManager.getInstance().addClientRequest(new LiteConversationRequest(client));
	}
	
	private void handleMessageLiteThreadRetrieval(ClientRegistration client, AirUnpacker unpacker) throws BufferUnderflowException, LargeAllocationException {
		//Reading the request information
		String conversationGUID = unpacker.unpackString();
		long firstMessageID = unpacker.unpackBoolean() ? unpacker.unpackLong() : -1;
		
		//Adding the request
		DatabaseManager.getInstance().addClientRequest(new LiteThreadRequest(client, conversationGUID, firstMessageID));
	}
	
	private void handleMessageCreateChat(ClientRegistration client, AirUnpacker unpacker) throws BufferUnderflowException, LargeAllocationException {
		//Reading the request information
		short requestID = unpacker.unpackShort(); //The request ID to avoid collisions
		String[] chatMembers = new String[unpacker.unpackArrayHeader()]; //The members of this conversation
		for(int i = 0; i < chatMembers.length; i++) chatMembers[i] = unpacker.unpackString();
		String service = unpacker.unpackString(); //The service of this conversation
		
		//Creating the chat
		Constants.Tuple<Integer, String> result = AppleScriptManager.createChat(chatMembers, service);
		
		//Sending a response
		sendMessageRequestResponse(client, CommConst.nhtCreateChat, requestID, result.item1, result.item2);
	}
	
	private void handleMessageSendTextExisting(ClientRegistration client, AirUnpacker unpacker) throws BufferUnderflowException, LargeAllocationException {
		//Reading the request information
		short requestID = unpacker.unpackShort(); //The request ID to avoid collisions
		String chatGUID = unpacker.unpackString(); //The GUID of the chat to send a message to
		String message = unpacker.unpackString(); //The message to send
		
		//Sending the message
		Constants.Tuple<Integer, String> result = AppleScriptManager.sendExistingMessage(chatGUID, message);
		
		//Sending the response
		sendMessageRequestResponse(client, CommConst.nhtSendResult, requestID, result.item1, result.item2);
	}
	
	private void handleMessageSendTextNew(ClientRegistration client, AirUnpacker unpacker) throws BufferUnderflowException, LargeAllocationException {
		//Reading the request information
		short requestID = unpacker.unpackShort(); //The request ID to avoid collisions
		String[] members = new String[unpacker.unpackArrayHeader()]; //The members of the chat to send the message to
		for(int i = 0; i < members.length; i++) members[i] = unpacker.unpackString();
		String service = unpacker.unpackString(); //The service of the chat
		String message = unpacker.unpackString(); //The message to send
		
		//Sending the message
		Constants.Tuple<Integer, String> result = AppleScriptManager.sendNewMessage(members, message, service);
		
		//Sending the response
		sendMessageRequestResponse(client, CommConst.nhtSendResult, requestID, result.item1, result.item2);
	}
	
	private void handleMessageSendFileExisting(ClientRegistration client, AirUnpacker unpacker) throws BufferUnderflowException, LargeAllocationException {
		//Reading the request information
		short requestID = unpacker.unpackShort(); //The request ID to avoid collisions
		int requestIndex = unpacker.unpackInt(); //The index of this request, to ensure that packets are received and written in order
		boolean isLast = unpacker.unpackBoolean(); //Is this the last packet?
		String chatGUID = unpacker.unpackString(); //The GUID of the chat to send the message to
		byte[] compressedBytes = unpacker.unpackPayload(); //The file bytes to append
		String fileName = requestIndex == 0 ? unpacker.unpackString() : null; //The name of the file to send
		
		//Forwarding the data
		AppleScriptManager.addFileFragment(client, requestID, chatGUID, fileName, requestIndex, compressedBytes, isLast);
	}
	
	private void handleMessageSendFileNew(ClientRegistration client, AirUnpacker unpacker) throws BufferUnderflowException, LargeAllocationException {
		//Reading the request information
		short requestID = unpacker.unpackShort(); //The request ID to avoid collisions
		int requestIndex = unpacker.unpackInt(); //The index of this request, to ensure that packets are received and written in order
		boolean isLast = unpacker.unpackBoolean(); //Is this the last packet?
		String[] members = new String[unpacker.unpackArrayHeader()]; //The members of the chat to send the message to
		for(int i = 0; i < members.length; i++) members[i] = unpacker.unpackString();
		byte[] compressedBytes = unpacker.unpackPayload(); //The file bytes to append
		String fileName = null; //The name of the file to send
		String service = null; //The service of the conversation
		if(requestIndex == 0) {
			fileName = unpacker.unpackString();
			service = unpacker.unpackString();
		}
		
		//Forwarding the data
		AppleScriptManager.addFileFragment(client, requestID, members, service, fileName, requestIndex, compressedBytes, isLast);
	}
	
	public void initiateClose(ClientRegistration client) {
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(CommConst.nhtClose);
			
			dataProxy.sendMessage(client, packer.toByteArray(), false, () -> dataProxy.disconnectClient(client));
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			
			//Disconnecting the client anyways
			dataProxy.disconnectClient(client);
		}
	}
	
	//Helper function for sending responses to basic requests with a request ID, result code, and result description (either error message or result details)
	public boolean sendMessageRequestResponse(ClientRegistration client, int header, short requestID, int resultCode, String details) {
		//Returning if the connection is not open
		if(!client.isConnected()) return false;
		
		//Sending a reply
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(header);
			packer.packShort(requestID);
			packer.packInt(resultCode); //Result code
			packer.packNullableString(details);
			
			dataProxy.sendMessage(client, packer.toByteArray(), true);
			
			return true;
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			
			return false;
		}
	}
	
	//Helper function for sending a packet with only a header and an empty body
	public boolean sendMessageHeaderOnly(ClientRegistration client, int header, boolean encrypt) {
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(header);
			
			dataProxy.sendMessage(client, packer.toByteArray(), encrypt);
			
			return true;
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			
			return false;
		}
	}
	
	public boolean sendMessageUpdate(Collection<Blocks.ConversationItem> items) {
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(CommConst.nhtMessageUpdate);
			
			packer.packArrayHeader(items.size());
			for(Blocks.Block item : items) item.writeObject(packer);
			
			dataProxy.sendMessage(null, packer.toByteArray(), true);
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			
			return false;
		}
		
		return true;
	}
	
	public boolean sendMessageUpdate(ClientRegistration client, int header, Collection<Blocks.ConversationItem> items) {
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(header);
			
			packer.packArrayHeader(items.size());
			for(Blocks.Block item : items) item.writeObject(packer);
			
			dataProxy.sendMessage(client, packer.toByteArray(), true);
			
			return true;
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			
			return false;
		}
	}
	
	public boolean sendConversationInfo(ClientRegistration client, Collection<Blocks.ConversationInfo> items) {
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(CommConst.nhtConversationUpdate);
			
			packer.packArrayHeader(items.size());
			for(Blocks.Block item : items) item.writeObject(packer);
			
			dataProxy.sendMessage(client, packer.toByteArray(), true);
			
			return true;
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			
			return false;
		}
	}
	
	public boolean sendLiteConversationInfo(ClientRegistration client, Collection<Blocks.LiteConversationInfo> items) {
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(CommConst.nhtLiteConversationRetrieval);
			
			packer.packArrayHeader(items.size());
			for(Blocks.Block item : items) item.writeObject(packer);
			
			dataProxy.sendMessage(client, packer.toByteArray(), true);
			
			return true;
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			
			return false;
		}
	}
	
	public boolean sendLiteThreadInfo(ClientRegistration client, String conversationGUID, long firstMessageID, Collection<Blocks.ConversationItem> items) {
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(CommConst.nhtLiteThreadRetrieval);
			
			packer.packString(conversationGUID);
			if(firstMessageID != -1) {
				packer.packBoolean(true);
				packer.packLong(firstMessageID);
			} else {
				packer.packBoolean(false);
			}
			packer.packArrayHeader(items.size());
			for(Blocks.Block item : items) item.writeObject(packer);
			
			dataProxy.sendMessage(client, packer.toByteArray(), true);
			
			return true;
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			
			return false;
		}
	}
	
	public boolean sendFileChunk(ClientRegistration client, short requestID, int requestIndex, long fileLength, boolean isLast, String fileGUID, byte[] chunkData, int chunkDataLength) {
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(CommConst.nhtAttachmentReq);
			
			packer.packShort(requestID);
			packer.packInt(requestIndex);
			if(requestIndex == 0) packer.packLong(fileLength);
			packer.packBoolean(isLast);
			
			packer.packString(fileGUID);
			packer.packPayload(chunkData, chunkDataLength);
			
			dataProxy.sendMessage(client, packer.toByteArray(), true);
			
			return true;
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			
			return false;
		}
	}
	
	public boolean sendMassRetrievalInitial(ClientRegistration client, short requestID, Collection<Blocks.ConversationInfo> conversations, int messageCount) {
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(CommConst.nhtMassRetrieval);
			
			packer.packShort(requestID);
			packer.packInt(0); //Request index
			
			packer.packArrayHeader(conversations.size());
			for(Blocks.Block item : conversations) item.writeObject(packer);
			
			packer.packInt(messageCount);
			
			dataProxy.sendMessage(client, packer.toByteArray(), true);
			
			return true;
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			
			return false;
		}
	}
	
	public boolean sendMassRetrievalMessages(ClientRegistration client, short requestID, int packetIndex, Collection<Blocks.ConversationItem> conversationItems) {
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(CommConst.nhtMassRetrieval);
			
			packer.packShort(requestID);
			packer.packInt(packetIndex);
			
			packer.packArrayHeader(conversationItems.size());
			for(Blocks.Block item : conversationItems) item.writeObject(packer);
			
			dataProxy.sendMessage(client, packer.toByteArray(), true);
			
			return true;
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			
			return false;
		}
	}
	
	public boolean sendMassRetrievalFileChunk(ClientRegistration client, short requestID, int requestIndex, String fileName, boolean isLast, String fileGUID, byte[] chunkData, int chunkDataLength) {
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(CommConst.nhtMassRetrievalFile);
			
			packer.packShort(requestID);
			packer.packInt(requestIndex);
			if(requestIndex == 0) packer.packString(fileName);
			packer.packBoolean(isLast);
			
			packer.packString(fileGUID);
			packer.packPayload(chunkData, chunkDataLength);
			
			dataProxy.sendMessage(client, packer.toByteArray(), true);
			
			return true;
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			
			return false;
		}
	}
	
	public boolean sendModifierUpdate(ClientRegistration client, Collection<Blocks.ModifierInfo> items) {
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(CommConst.nhtModifierUpdate);
			
			packer.packArrayHeader(items.size());
			for(Blocks.Block item : items) item.writeObject(packer);
			
			dataProxy.sendMessage(client, packer.toByteArray(), true);
			
			return true;
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			
			return false;
		}
	}
	
	public boolean sendIDUpdate(ClientRegistration client, long id) {
		try(AirPacker packer = AirPacker.get()) {
			packer.packInt(CommConst.nhtIDUpdate);
			
			packer.packLong(id);
			
			dataProxy.sendMessage(client, packer.toByteArray(), true);
			
			return true;
		} catch(BufferOverflowException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
			
			return false;
		}
	}
	
	public void sendPushNotification(List<Blocks.MessageInfo> messages, List<Blocks.ModifierInfo> modifiers) {
		boolean encrypt = !JNIPreferences.getPassword().isBlank();
		
		//Serializing the data
		byte[] data;
		try(AirPacker packer = AirPacker.get()) {
			packer.packArrayHeader(messages.size());
			for(Blocks.MessageInfo item : messages) item.writeObject(packer);
			packer.packArrayHeader(modifiers.size());
			for(Blocks.ModifierInfo item : modifiers) item.writeObject(packer);
			
			if(encrypt) {
				try {
					data = EncryptionHelper.encrypt(packer.toByteArray());
				} catch(GeneralSecurityException exception) {
					Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
					Sentry.captureException(exception);
					return;
				}
			} else {
				data = packer.toByteArray();
			}
		}
		
		try(AirPacker packer = AirPacker.get()) {
			packer.packBoolean(encrypt);
			packer.packPayload(data);
			
			dataProxy.sendPushNotification(2, packer.toByteArray());
		}
	}
}