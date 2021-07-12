package me.tagavari.airmessageserver.server;

import io.sentry.Sentry;
import me.tagavari.airmessageserver.common.Blocks;
import me.tagavari.airmessageserver.connection.CommConst;
import me.tagavari.airmessageserver.connection.ConnectionManager;
import me.tagavari.airmessageserver.helper.CompressionHelper;
import me.tagavari.airmessageserver.helper.LookAheadStreamIterator;
import me.tagavari.airmessageserver.request.*;
import org.jooq.Record;
import org.jooq.*;
import org.jooq.exception.DataAccessException;
import org.jooq.impl.DSL;

import java.io.*;
import java.nio.file.Files;
import java.security.DigestInputStream;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.*;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;
import java.util.logging.Level;
import java.util.stream.Collectors;
import java.util.zip.DeflaterInputStream;

import static org.jooq.impl.DSL.*;

public class DatabaseManager {
	//Creating the reference variables
	//private static final long checkTime = 5 * 1000;
	//private static final long pollTime = 100;
	private static final String databaseLocation = "jdbc:sqlite:" + System.getProperty("user.home") + "/Library/Messages/chat.db";
	/* private static final ArrayList<String> validServices = new ArrayList<String>() {{
		add("iMessage");
		add("SMS");
	}}; */
	
	//Creating the instance value
	private static DatabaseManager instance;
	
	//Creating the schema support values
	private final boolean dbSupportsSendStyle;
	private final boolean dbSupportsAssociation;
	private final boolean dbSupportsHiddenAttachments;
	
	//Creating the thread values
	ScannerThread scannerThread;
	RequestThread requestThread;
	
	//Creating the other values
	private final HashMap<String, MessageState> messageStates = new HashMap<>();
	
	private static final long creationTargetingAvailabilityUpdateInterval = 60 * 60 * 1000; //1 hour
	private long lastCreationTargetingAvailabilityUpdate;
	private boolean creationTargetingUpdateRequired = true;
	private final AtomicReference<HashMap<String, CreationTargetingChat>> creationTargetingAvailabilityList = new AtomicReference<>(new HashMap<>());
	
	public static boolean start(long scanFrequency) {
		//Checking if there is already an instance
		if(instance != null) {
			//Logging the exception
			//Main.getLogger().severe("Instance of database manager already exists");
			
			//Returning true
			return true;
		}
		
		//Creating the database connections
		Connection[] connections = new Connection[2];
		int connectionsEstablished = 0;
		try {
			for(; connectionsEstablished < connections.length; connectionsEstablished++) connections[connectionsEstablished] = DriverManager.getConnection(databaseLocation);
		} catch(SQLException exception) {
			//Logging a message
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			
			//Closing the connections
			for(int i = 0; i < connectionsEstablished; i++) {
				try {
					connections[i].close();
				} catch(SQLException exception2) {
					Main.getLogger().log(Level.WARNING, exception2.getMessage(), exception2);
				}
			}
			
			//Main.getLogger().severe("No incoming messages will be received");
			
			//Returning false
			return false;
		}
		
		//Creating the instance
		instance = new DatabaseManager(connections, scanFrequency);
		
		//Getting the time variables
		//connectFetchTime = Main.getTimeHelper().toDatabaseTime(System.currentTimeMillis());
		
		//Returning true
		return true;
	}
	
	public static void stop() {
		//Validating the instance
		if(instance == null) return;
		
		//Interrupting the thread
		instance.requestThread.interrupt();
		instance.scannerThread.interrupt();
		
		//Invalidating the instance
		instance = null;
	}
	
	private DatabaseManager(Connection[] connections, long scanFrequency) {
		//Setting up the capability values
		dbSupportsSendStyle = dbSupportsAssociation = dbSupportsHiddenAttachments = Constants.compareVersions(Constants.getSystemVersion(), Constants.macOSSierraVersion) >= 0;
		
		/* //Reading the schema
		Connection connection = connections[0];
		
		try {
			//Checking if the DB supports send styles
			ResultSet resultSet = connection.getMetaData().getColumns(null, null, "message", "expressive_send_style_id");
			dbSupportsSendStyle = resultSet.next();
			resultSet.close();
			
			//Checking if the DB supports association (tapback & stickers)
			resultSet = connection.getMetaData().getColumns(null, null, "message", "associated_message_guid");
			dbSupportsAssociation = resultSet.next();
			resultSet.close();
		} catch(SQLException exception) {
			Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
			Sentry.captureException(exception);
		} */
		
		//Creating the threads
		scannerThread = new ScannerThread(connections[0], scanFrequency);
		scannerThread.start();
		requestThread = new RequestThread(connections[1]);
		requestThread.start();
	}
	
	public static DatabaseManager getInstance() {
		return instance;
	}
	
	public HashMap<String, CreationTargetingChat> getCreationTargetingAvailabilityList() {
		return creationTargetingAvailabilityList.get();
	}
	
	public long getLatestEntryID() {
		return scannerThread.latestEntryID;
	}
	
	public void requestCreationTargetingAvailabilityUpdate() {
		creationTargetingUpdateRequired = true;
	}
	
	//The thread that actively scans the database for new messages
	class ScannerThread extends Thread {
		//Creating the connection variables
		private final Connection connection;
		
		//Creating the time values
		private volatile long latestEntryID = -1;
		private final long creationTime;
		//private long lastCheckTime;
		
		//Creating the lock values
		private final Lock scanFrequencyLock = new ReentrantLock();
		private final java.util.concurrent.locks.Condition scanFrequencyCondition = scanFrequencyLock.newCondition();
		private long scanFrequency;
		
		private ScannerThread(Connection connection, long scanFrequency) {
			//Setting the values
			this.connection = connection;
			
			creationTime = Main.getTimeHelper().toDatabaseTime(System.currentTimeMillis());
			
			this.scanFrequency = scanFrequency;
		}
		
		@Override
		public void run() {
			//Creating the message array variable
			DataFetchResult dataFetchResult;
			boolean latestMessageIDUpdated = false;
			
			//Looping until the thread is interrupted
			while(!isInterrupted()) {
				try {
					//Sleeping for the scan frequency
					scanFrequencyLock.lock();
					try {
						scanFrequencyCondition.await(scanFrequency, TimeUnit.MILLISECONDS);
					} finally {
						scanFrequencyLock.unlock();
					}
					
					//Fetching new messages
					dataFetchResult = fetchData(connection,
							new RetrievalFilter(latestEntryID == -1 ?
									field("message.date").greaterThan(creationTime) :
									field("message.ROWID").greaterThan(latestEntryID), -1, null), null);
					
					//Updating the latest entry ID
					if(latestMessageIDUpdated = dataFetchResult.latestMessageID > latestEntryID) {
						latestEntryID = dataFetchResult.latestMessageID;
					}
					
					//Updating the last check time
					//lastCheckTime = System.currentTimeMillis();
				} catch(IOException | NoSuchAlgorithmException | OutOfMemoryError | SQLException | RuntimeException exception) {
					Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
					Sentry.captureException(exception);
					dataFetchResult = null;
				} catch(InterruptedException exception) {
					//Returning
					return;
				}
				
				//Updating new message items
				if(dataFetchResult != null && !dataFetchResult.conversationItems.isEmpty()) {
					ConnectionManager.getCommunicationsManager().sendMessageUpdate(dataFetchResult.conversationItems);
				}
				
				//Updating the message states
				List<Blocks.ModifierInfo> newModifiers = getUnreadUpdates(connection);
				if(dataFetchResult != null) newModifiers.addAll(dataFetchResult.isolatedModifiers);
				if(!newModifiers.isEmpty()) {
					ConnectionManager.getCommunicationsManager().sendModifierUpdate(null, newModifiers);
				}
				
				//Sending push notifications
				if(dataFetchResult != null) {
					List<Blocks.MessageInfo> pushMessages = dataFetchResult.conversationItems.stream()
						.filter(item -> item instanceof Blocks.MessageInfo)
						.map(item -> (Blocks.MessageInfo) item)
						.filter(item -> item.sender != null)
						.collect(Collectors.toList());
					List<Blocks.ModifierInfo> pushModifiers = dataFetchResult.isolatedModifiers.stream()
						.filter(item -> item instanceof Blocks.TapbackModifierInfo && ((Blocks.TapbackModifierInfo) item).sender != null)
						.collect(Collectors.toList());
					
					if(!pushMessages.isEmpty() || !pushModifiers.isEmpty()) {
						ConnectionManager.getCommunicationsManager().sendPushNotification(pushMessages, pushModifiers);
					}
				}
				
				//Notifying clients of the latest message ID
				if(latestMessageIDUpdated) {
					ConnectionManager.getCommunicationsManager().sendIDUpdate(null, latestEntryID);
				}
				
				{
					//Checking if the targeting availability index needs to be updated
					long currentTime = System.currentTimeMillis();
					if(creationTargetingUpdateRequired || currentTime >= lastCreationTargetingAvailabilityUpdate + creationTargetingAvailabilityUpdateInterval) {
						//Setting the last update time
						lastCreationTargetingAvailabilityUpdate = currentTime;
						creationTargetingUpdateRequired = false;
						
						//Reindexing
						try {
							indexTargetAvailability(connection);
							
							Main.getLogger().log(Level.FINEST, "Updated chat creation target index");
						} catch(SQLException exception) {
							Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
							Sentry.captureException(exception);
						}
					}
				}
			}
		}
		
		void updateScanFrequency(long frequency) {
			//Updating the value
			scanFrequencyLock.lock();
			try {
				if(frequency != scanFrequency) {
					scanFrequency = frequency;
					scanFrequencyCondition.signal();
				}
			} finally {
				scanFrequencyLock.unlock();
			}
		}
	}
	
	//The thread that handles requests from clients such as file downloads
	class RequestThread extends Thread {
		//Creating the connection variables
		private final Connection connection;
		
		//Creating the lock values
		private BlockingQueue<DBRequest> databaseRequests = new LinkedBlockingQueue<>();
		
		private RequestThread(Connection connection) {
			this.connection = connection;
		}
		
		@Override
		public void run() {
			try {
				//Looping while the thread is alive
				while(!isInterrupted()) {
					//Taking the queue item
					Object request = databaseRequests.take();
					
					//Processing the request
					if(request instanceof ConversationInfoRequest) fulfillConversationRequest(connection, (ConversationInfoRequest) request);
					else if(request instanceof FileRequest) fulfillFileRequest(connection, (FileRequest) request);
					else if(request instanceof LiteConversationRequest) fulfillLiteConversationRequest(connection, (LiteConversationRequest) request);
					else if(request instanceof LiteThreadRequest) fulfillLiteThreadRequest(connection, (LiteThreadRequest) request);
					else if(request instanceof CustomRetrievalRequest) fulfillCustomRetrievalRequest(connection, (CustomRetrievalRequest) request);
					else if(request instanceof MassRetrievalRequest) fulfillMassRetrievalRequest(connection, (MassRetrievalRequest) request);
					else if(request instanceof ReadReceiptRequest) fulfillReadReceiptRequest(connection, (ReadReceiptRequest) request);
				}
			} catch(RuntimeException exception) {
				//Logging the message
				Main.getLogger().log(Level.SEVERE, exception.getMessage(), exception);
				
				//Capturing the exception
				Sentry.captureException(exception);
			} catch(InterruptedException exception) {
				//Logging the message
				Main.getLogger().log(Level.INFO, exception.getMessage(), exception);
			}
		}
		
		void addRequest(DBRequest request) {
			databaseRequests.add(request);
			/* //Adding the data struct
			dbRequestsLock.lock();
			try {
				databaseRequests.add(request);
				dbRequestsCondition.signal();
			} finally {
				dbRequestsLock.unlock();
			} */
		}
	}
	
	public void addClientRequest(DBRequest request) {
		requestThread.addRequest(request);
	}
	
	private void fulfillConversationRequest(Connection connection, ConversationInfoRequest request) {
		//Creating the DSL context
		DSLContext create = DSL.using(connection, SQLDialect.SQLITE);
		
		//Creating the conversation info list
		ArrayList<Blocks.ConversationInfo> conversationInfoList = new ArrayList<>();
		
		//Iterating over their conversations
		for(String conversationGUID : request.conversationsGUIDs) {
			//Fetching the conversation information
			String conversationTitle;
			String conversationService;
			{
				//Running the SQL
				Result<org.jooq.Record2<String, String>> results = create.select(field("chat.display_name", String.class), field("chat.service_name", String.class))
						.from(DSL.table("chat"))
						.where(field("chat.guid").equal(conversationGUID))
						.fetch();
				
				//Checking if there are no results
				if(results.isEmpty()) {
					//Adding an unavailable conversation info
					conversationInfoList.add(new Blocks.ConversationInfo(conversationGUID));
					
					//Skipping the remainder of the iteration
					continue;
				}
				
				//Setting the conversation information
				conversationTitle = results.getValue(0, field("chat.display_name", String.class));
				conversationService = results.getValue(0, field("chat.service_name", String.class));
			}
			
			//Fetching the conversation members
			ArrayList<String> conversationMembers = new ArrayList<>();
			{
				//Running the SQL
				Result<org.jooq.Record1<String>> results = create.select(field("handle.id", String.class))
						.from(DSL.table("handle"))
						.innerJoin(DSL.table("chat_handle_join")).on(field("handle.ROWID").equal(field("chat_handle_join.handle_id")))
						.innerJoin(DSL.table("chat")).on(field("chat_handle_join.chat_id").equal(field("chat.ROWID")))
						.where(field("chat.guid").equal(conversationGUID))
						.fetch();
				
				//Checking if there are no results
				if(results.isEmpty()) {
					//Adding an unavailable conversation info
					conversationInfoList.add(new Blocks.ConversationInfo(conversationGUID));
					
					//Skipping the remainder of the iteration
					continue;
				}
				
				//Adding the members
				for(Record1<String> result : results) conversationMembers.add(result.getValue(field("handle.id", String.class)));
			}
			
			//Adding the conversation info
			conversationInfoList.add(new Blocks.ConversationInfo(conversationGUID, conversationService, conversationTitle, conversationMembers.toArray(new String[0])));
		}
		
		//Checking if the connection is registered and is still open
		if(request.connection.isConnected()) {
			//Sending the conversation info
			ConnectionManager.getCommunicationsManager().sendConversationInfo(request.connection, conversationInfoList);
		} else {
			Main.getLogger().log(Level.INFO, "Ignoring file request, connection not available");
		}
	}
	
	private void fulfillFileRequest(Connection connection, FileRequest request) {
		//Creating the DSL context
		DSLContext create = DSL.using(connection, SQLDialect.SQLITE);
		
		//Fetching information from the database
		Result<org.jooq.Record1<String>> results = create.select(field("filename", String.class))
				.from(DSL.table("attachment"))
				.where(field("guid").equal(request.fileGuid))
				.fetch();
		
		//Creating the result variables
		File file = null;
		boolean succeeded = true;
		int errorCode = -1;
		
		//Setting the succeeded variable to false if there are no results
		if(results.isEmpty()) {
			succeeded = false;
			errorCode = CommConst.nstAttachmentReqNotFound;
		} else {
			//Getting the file
			String filePath = results.getValue(0, field("filename", String.class));
			
			//Failing the file check if the path is invalid
			if(filePath == null) {
				succeeded = false;
				errorCode = CommConst.nstAttachmentReqNotSaved;
			} else {
				if(filePath.startsWith("~")) filePath = filePath.replaceFirst("~", System.getProperty("user.home"));
				file = new File(filePath);
				
				//Failing the file check if the file doesn't exist
				if(!file.exists()) {
					succeeded = false;
					errorCode = CommConst.nstAttachmentReqNotSaved;
				} else if(!file.canRead()) {
					succeeded = false;
					errorCode = CommConst.nstAttachmentReqUnreadable;
				}
			}
		}
		
		//Checking if there have been no errors so far
		if(succeeded) {
			//Preparing to read the data
			int requestIndex = 0;
			long fileLength = file.length();
			
			//Streaming the file
			try(InputStream inputStream = new DeflaterInputStream(new BufferedInputStream(new FileInputStream(file)))) {
				for(LookAheadStreamIterator iterator = new LookAheadStreamIterator(request.chunkSize, inputStream); iterator.hasNext();) {
					LookAheadStreamIterator.ForwardsStreamData data = iterator.next();
					
					//Sending the data
					if(request.connection.isConnected()) {
						ConnectionManager.getCommunicationsManager().sendFileChunk(request.connection, request.requestID, requestIndex, fileLength, data.isLast(), request.fileGuid, data.getData(), data.getLength());
					} else {
						Main.getLogger().log(Level.INFO, "Ignoring file request, connection not available");
						break;
					}
					
					//Adding to the request index
					requestIndex++;
				}
			} catch(IOException exception) {
				//Logging the error
				Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
				//Sentry.captureException(exception);
				
				//Updating the state
				succeeded = false;
				errorCode = CommConst.nstAttachmentReqIO;
			}
		}
		
		//Checking if the attempt was a failure
		if(!succeeded) {
			//Sending a reply
			if(request.connection.isConnected()) {
				ConnectionManager.getCommunicationsManager().sendMessageRequestResponse(request.connection, CommConst.nhtAttachmentReqFail, request.requestID, errorCode, null);
			}
		}
	}
	
	private void fulfillLiteConversationRequest(Connection connection, LiteConversationRequest request) {
		//Creating the result list
		Collection<Blocks.LiteConversationInfo> resultList = new ArrayList<>();
		
		try {
			Collection<Field<?>> fields = new ArrayList<>(Arrays.asList(field("chat.guid", String.class), field("chat.display_name", String.class), field("chat.service_name", String.class), field("message.text", String.class), field("message.date", Long.class), field("handle.id", String.class), field("sub2.participant_list", String.class).as("participant_list"), field("GROUP_CONCAT(attachment.mime_type)", String.class).as("attachment_list")));
			if(dbSupportsSendStyle) fields.add(field("message.expressive_send_style_id", String.class));
			
			//Querying the database
			DSLContext create = DSL.using(connection, SQLDialect.SQLITE);
			Result<Record> results = create.select(fields)
				.from(select(field("sub1.*"), field("GROUP_CONCAT(handle.id)", String.class).as("participant_list"))
					.from(select(field("chat.ROWID", Long.class).as("chat_id"), field("message.ROWID", Long.class).as("message_id"), field("MAX(message.date)", Long.class))
						.from(table("chat"))
						.leftJoin(table("chat_message_join")).on(field("chat_message_join.chat_id").eq(field("chat.ROWID")))
						.leftJoin(table("message")).on(field("chat_message_join.message_id").eq(field("message.ROWID")))
						.where(field("message.item_type", Integer.class).eq(0))
						.groupBy(field("chat.ROWID"))
						.asTable("sub1")
					)
					.leftJoin(table("chat_handle_join")).on(field("chat_handle_join.chat_id", Long.class).eq(field("sub1.chat_id", Long.class)))
					.leftJoin(table("handle")).on(field("chat_handle_join.handle_id", Long.class).eq(field("handle.ROWID", Long.class)))
					.groupBy(field("sub1.chat_id"))
					.asTable("sub2")
				)
				.leftJoin(table("chat")).on(field("chat.ROWID", Long.class).eq(field("sub2.chat_id", Long.class)))
				.leftJoin(table("message")).on(field("message.ROWID", Long.class).eq(field("sub2.message_id", Long.class)))
				.leftJoin(table("message_attachment_join")).on(field("message_attachment_join.message_id", Long.class).eq(field("sub2.message_id", Long.class)))
				.leftJoin(table("attachment")).on(field("message_attachment_join.attachment_id", Long.class).eq(field("attachment.ROWID", Long.class)))
				.leftJoin(table("handle")).on(field("message.handle_id", Long.class).eq(field("handle.ROWID", Long.class)))
				.groupBy(field("chat.ROWID", Long.class))
				.orderBy(field("message.date", Long.class).desc())
				.fetch();
			
			for(Record result : results) {
				String guid = result.get("chat.guid", String.class);
				String service = result.get("chat.service_name", String.class);
				String name = result.get("chat.display_name", String.class);
				String membersRaw = result.get("participant_list", String.class);
				String[] members = membersRaw == null ? new String[0] : membersRaw.split(",");
				Long date = result.get("message.date", Long.class);
				String text = result.get("message.text", String.class);
				if(text != null) {
					text = text.replace(Character.toString('\uFFFC'), "");
					text = text.replace(Character.toString('\uFFFD'), "");
					if(text.isEmpty()) text = null;
				}
				String sendStyle = dbSupportsSendStyle ? result.get("message.expressive_send_style_id", String.class) : null;
				String sender = result.get("handle.id", String.class);
				String attachmentListRaw = result.get("attachment_list", String.class);
				String[] attachmentList = attachmentListRaw == null ? null : attachmentListRaw.split(",");
				
				resultList.add(new Blocks.LiteConversationInfo(guid, service, name, members, date != null ? Main.getTimeHelper().toUnixTime(date) : -1, sender, text, sendStyle, attachmentList));
			}
			
			//Checking if the connection is registered and is still open
			if(request.connection.isConnected()) {
				Main.getLogger().log(Level.INFO, "Fulfilled lite conversation request, returning " + resultList.size() + " conversations");
				
				//Sending the conversation info
				ConnectionManager.getCommunicationsManager().sendLiteConversationInfo(request.connection, resultList);
			} else {
				Main.getLogger().log(Level.INFO, "Ignoring lite conversation request, connection not available");
			}
		} catch(DataAccessException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
		}
	}
	
	private void fulfillLiteThreadRequest(Connection connection, LiteThreadRequest request) {
		try {
			Condition condition = field("chat.guid").eq(request.conversationGUID);
			if(request.firstMessageID != -1) condition = condition.and(field("message.ROWID").lessThan(request.firstMessageID));
			DataFetchResult result = fetchData(connection, new RetrievalFilter(condition, 24, DSL.field("message.ROWID", Long.class).desc()), null, true);
			if(request.connection.isConnected()) {
				ConnectionManager.getCommunicationsManager().sendLiteThreadInfo(request.connection, request.conversationGUID, request.firstMessageID, result.conversationItems);
			}
		} catch(IOException | GeneralSecurityException | SQLException | OutOfMemoryError | RuntimeException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			Sentry.captureException(exception);
		}
	}
	
	private void fulfillCustomRetrievalRequest(Connection connection, CustomRetrievalRequest request) {
		try {
			//Returning the data
			DataFetchResult result = fetchData(connection, request.filter, null);
			if(request.connection.isConnected()) {
				ConnectionManager.getCommunicationsManager().sendMessageUpdate(request.connection, CommConst.nhtMessageUpdate, result.conversationItems);
				if(!result.isolatedModifiers.isEmpty()) {
					ConnectionManager.getCommunicationsManager().sendModifierUpdate(request.connection, result.isolatedModifiers);
				}
			}
		} catch(IOException | GeneralSecurityException | SQLException | OutOfMemoryError | RuntimeException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			Sentry.captureException(exception);
		}
	}
	
	private void fulfillMassRetrievalRequest(Connection connection, MassRetrievalRequest request) {
		//Converting the request times
		long lTimeSinceMessages = Main.getTimeHelper().toDatabaseTime(request.timeSinceMessages);
		long lTimeSinceAttachments = Main.getTimeHelper().toDatabaseTime(request.timeSinceAttachments);
		
		try {
			//Creating the DSL context
			DSLContext create = DSL.using(connection, SQLDialect.SQLITE);
			
			//Fetching the conversation information
			List<Blocks.ConversationInfo> conversationInfoList = new ArrayList<>();
			
			//Fetching the chat info
			Result<org.jooq.Record3<String, String, String>> conversationResults;
			if(request.restrictMessages) {
				conversationResults = create.select(field("chat.guid", String.class), field("chat.display_name", String.class), field("chat.service_name", String.class))
											.from(DSL.table("chat"))
											.join(DSL.table("chat_message_join")).on(field("chat.ROWID").eq(field("chat_message_join.chat_id")))
											.join(DSL.table("message")).on(field("chat_message_join.message_id").eq(field("message.ROWID")))
											.where(field("message.date").greaterOrEqual(lTimeSinceMessages))
											.groupBy(field("chat.ROWID"))
											.fetch();
			} else {
				conversationResults = create.select(field("chat.guid", String.class), field("chat.display_name", String.class), field("chat.service_name", String.class))
											.from(DSL.table("chat"))
											.fetch();
			}
			
			//Iterating over the results
			for(int i = 0; i < conversationResults.size(); i++) {
				//Setting the conversation information
				String conversationGUID = conversationResults.getValue(i, field("chat.guid", String.class));
				String conversationTitle = conversationResults.getValue(i, field("chat.display_name", String.class));
				String conversationService = conversationResults.getValue(i, field("chat.service_name", String.class));
				
				//Fetching the conversation members
				ArrayList<String> conversationMembers = new ArrayList<>();
				{
					//Running the SQL
					Result<org.jooq.Record1<String>> results = create.select(field("handle.id", String.class))
							.from(DSL.table("handle"))
							.innerJoin(DSL.table("chat_handle_join")).on(field("handle.ROWID").equal(field("chat_handle_join.handle_id")))
							.innerJoin(DSL.table("chat")).on(field("chat_handle_join.chat_id").equal(field("chat.ROWID")))
							.where(field("chat.guid").equal(conversationGUID))
							.fetch();
					
					//Adding the members
					for(Record1<String> result : results) conversationMembers.add(result.getValue(field("handle.id", String.class)));
				}
				
				//Adding the conversation info
				conversationInfoList.add(new Blocks.ConversationInfo(conversationGUID, conversationService, conversationTitle, conversationMembers.toArray(new String[0])));
			}
			
			//Finding the amount of message entries in the database (roughly, because not all entries are messages)
			int messagesCount;
			if(request.restrictMessages) messagesCount = create.selectCount().from(DSL.table("message")).where(field("date").greaterOrEqual(lTimeSinceMessages)).fetchOne(0, int.class);
			else messagesCount = create.selectCount().from(DSL.table("message")).fetchOne(0, int.class);
			
			//Returning if the connection is no longer open
			if(!request.connection.isConnected()) return;
			
			//Sending the conversations and message count
			ConnectionManager.getCommunicationsManager().sendMassRetrievalInitial(request.connection, request.requestID, conversationInfoList, messagesCount);
			
			//Reading the message data
			fetchData(connection, request.restrictMessages ? new RetrievalFilter(field("message.date").greaterOrEqual(lTimeSinceMessages), -1, null) : null, new DataFetchListener(request.downloadAttachments) {
				//Creating the packet index value
				int packetIndex = 1;
				
				@Override
				void onChunkLoaded(List<Blocks.ConversationItem> conversationItems, List<Blocks.ModifierInfo> isolatedModifiers) {
					//Checking if the connection is no longer open
					if(!request.connection.isConnected()) {
						//Cancelling the fetch and returning
						cancel();
						return;
					}
					
					//Sending the message group
					boolean result = ConnectionManager.getCommunicationsManager().sendMassRetrievalMessages(request.connection, request.requestID, packetIndex++, conversationItems);
					if(!result) cancel(); //Cancelling the fetch if the message couldn't be sent
				}
				
				@Override
				void onAttachmentChunkLoaded(List<TransientAttachmentInfo> attachmentList) {
					for(TransientAttachmentInfo attachment : attachmentList) {
						//Filtering out attachments
						if(!attachment.file.exists() || attachment.fileType == null) return; //Invalid attachments
						if(request.restrictAttachments && attachment.messageDate < lTimeSinceAttachments) return; //Attachment date
						if(request.restrictAttachmentsSizes && attachment.fileSize > request.attachmentSizeLimit) return; //Attachment size
						if(!compareMIMEArray(request.attachmentFilterWhitelist, attachment.fileType) && (compareMIMEArray(request.attachmentFilterBlacklist, attachment.fileType) || !request.attachmentFilterDLOutside)) return; //Attachment type
						
						//Streaming the file
						try(InputStream inputStream = new DeflaterInputStream(new BufferedInputStream(new FileInputStream(attachment.file)))) {
							int requestIndex = 0;
							for(LookAheadStreamIterator iterator = new LookAheadStreamIterator(1024 * 1024, inputStream); iterator.hasNext();) {
								LookAheadStreamIterator.ForwardsStreamData data = iterator.next();
								
								//Checking if the connection is ready
								if(request.connection.isConnected()) {
									//Sending the data
									ConnectionManager.getCommunicationsManager().sendMassRetrievalFileChunk(request.connection, request.requestID, requestIndex, attachment.fileName, data.isLast(), attachment.guid, data.getData(), data.getLength());
								} else {
									Main.getLogger().log(Level.INFO, "Ignoring file request, connection not available");
									break;
								}
								
								//Adding to the request index
								requestIndex++;
							}
						} catch(IOException exception) {
							Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
							Sentry.captureException(exception);
						}
					}
				}
				
				private boolean compareMIMEArray(String[] array, String target) {
					for(String item : array) if(Constants.compareMimeTypes(item, target)) return true;
					return false;
				}
				
				@Override
				void onFinished() {
					//Returning if the connection is no longer open
					if(!request.connection.isConnected()) return;
					
					//Sending the finish message
					ConnectionManager.getCommunicationsManager().sendMessageHeaderOnly(request.connection, CommConst.nhtMassRetrievalFinish, true);
				}
			});
		} catch(IOException | OutOfMemoryError | RuntimeException | SQLException | GeneralSecurityException exception) {
			Main.getLogger().log(Level.WARNING, exception.getMessage(), exception);
			Sentry.captureException(exception);
		}
	}
	
	private void fulfillReadReceiptRequest(Connection connection, ReadReceiptRequest request) {
		//Converting the request time
		long timeSince = Main.getTimeHelper().toDatabaseTime(request.timeSince);
		
		//Creating the DSL context
		DSLContext create = DSL.using(connection, SQLDialect.SQLITE);
		
		//Fetching the data
		Result<Record6<Long, String, Boolean, Boolean, Boolean, Long>> results = create.select(DSL.max(field("message.ROWID", Long.class)), field("message.guid", String.class), field("message.is_sent", Boolean.class), field("message.is_delivered", Boolean.class), field("message.is_read", Boolean.class), field("message.date_read", Long.class))
			.from(DSL.table("message"))
			.join(DSL.table("chat_message_join")).on(field("message.ROWID").eq(field("chat_message_join.message_id")))
			.join(DSL.table("chat")).on(field("chat_message_join.chat_id").eq(field("chat.ROWID")))
			.where(field("message.is_from_me").isTrue()).and(or(field("message.date_delivered").greaterThan(timeSince), field("message.date_read").greaterThan(timeSince)))
			.groupBy(field("chat.ROWID")).fetch();
		
		//Iterating over the results
		List<Blocks.ModifierInfo> list = new ArrayList<>();
		for(int i = 0; i < results.size(); i++) {
			//Getting the result information
			String resultGuid = results.getValue(i, field("message.guid", String.class));
			int resultState = determineMessageState(results.getValue(i, field("message.is_sent", Boolean.class)),
				results.getValue(i, field("message.is_delivered", Boolean.class)),
				results.getValue(i, field("message.is_read", Boolean.class)));
			
			//Adding the modifier to the list
			list.add(new Blocks.ActivityStatusModifierInfo(resultGuid, resultState, Main.getTimeHelper().toUnixTime(results.getValue(i, field("message.date_read", Long.class)))));
			
			//Checking if the connection is registered and is still open
			if(request.connection.isConnected()) {
				//Sending the conversation info
				ConnectionManager.getCommunicationsManager().sendModifierUpdate(request.connection, list);
			} else {
				Main.getLogger().log(Level.INFO, "Ignoring read receipt request, connection not available");
			}
		}
	}
	
	private abstract class DataFetchListener {
		final boolean acceptFileData;
		private boolean cancelRequested = false;

		DataFetchListener(boolean acceptFileData) {
			this.acceptFileData = acceptFileData;
		}

		abstract void onChunkLoaded(List<Blocks.ConversationItem> conversationItems, List<Blocks.ModifierInfo> isolatedModifiers);
		void onAttachmentChunkLoaded(List<TransientAttachmentInfo> attachmentList) {}
		abstract void onFinished();
		
		void cancel() {
			cancelRequested = true;
		}
	}
	
	private DataFetchResult fetchData(Connection connection, RetrievalFilter filter, DataFetchListener streamingListener) throws IOException, NoSuchAlgorithmException, SQLException {
		return fetchData(connection, filter, streamingListener, false);
	}
	
	private DataFetchResult fetchData(Connection connection, RetrievalFilter filter, DataFetchListener streamingListener, boolean reverseProcess) throws IOException, NoSuchAlgorithmException, SQLException {
		//Creating the DSL context
		DSLContext context = DSL.using(connection, SQLDialect.SQLITE);
		
		//Building the base query
		List<SelectField<?>> fields = new ArrayList<>(Arrays.asList(field("message.ROWID", Long.class), field("message.guid", String.class), field("message.date", Long.class), field("message.item_type", Integer.class), field("message.group_action_type", Integer.class), field("message.text", String.class), field("message.subject", String.class), field("message.error", Integer.class), field("message.date_read", Long.class), field("message.is_from_me", Boolean.class), field("message.group_title", String.class),
				field("message.is_sent", Boolean.class), field("message.is_read", Boolean.class), field("message.is_delivered", Boolean.class),
				field("sender_handle.id", String.class), field("other_handle.id", String.class),
				field("chat.guid", String.class)));
		
		//Adding the extras (if applicable)
		if(dbSupportsSendStyle) fields.add(field("message.expressive_send_style_id", String.class));
		if(dbSupportsAssociation) {
			fields.add(field("message.associated_message_guid", String.class));
			fields.add(field("message.associated_message_type", Integer.class));
			fields.add(field("message.associated_message_range_location", Integer.class));
		}
		
		//Compiling the selection into a build step
		SelectWhereStep<?> buildStep
				= context.select(fields)
				.from(DSL.table("message"))
				.innerJoin(DSL.table("chat_message_join")).on(field("message.ROWID").eq(field("chat_message_join.message_id")))
				.innerJoin(DSL.table("chat")).on(field("chat_message_join.chat_id").eq(field("chat.ROWID")))
				.leftJoin(DSL.table("handle").as("sender_handle")).on(field("message.handle_id").eq(field("sender_handle.ROWID")))
				.leftJoin(DSL.table("handle").as("other_handle")).on(field("message.other_handle").eq(field("other_handle.ROWID")));
		
		//Fetching the basic message info
		/* SelectOnConditionStep<Record16<Long, String, Long, Integer, Integer, String, String, Integer, Boolean, String, Boolean, Boolean, Boolean, String, String, String>> buildStep
				= create.select(DSL.field("message.ROWID", Long.class), DSL.field("message.guid", String.class), DSL.field("message.date", Long.class), DSL.field("message.item_type", Integer.class), DSL.field("message.group_action_type", Integer.class), DSL.field("message.text", String.class), DSL.field("message.expressive_send_style_id", String.class), DSL.field("message.error", Integer.class), DSL.field("message.is_from_me", Boolean.class), DSL.field("message.group_title", String.class),
				DSL.field("message.is_sent", Boolean.class), DSL.field("message.is_read", Boolean.class), DSL.field("message.is_delivered", Boolean.class),
				DSL.field("sender_handle.id", String.class), DSL.field("other_handle.id", String.class),
				DSL.field("chat.guid", String.class))
				.from(DSL.table("message"))
				.innerJoin(DSL.table("chat_message_join")).on(DSL.field("message.ROWID").eq(DSL.field("chat_message_join.message_id")))
				.innerJoin(DSL.table("chat")).on(DSL.field("chat_message_join.chat_id").eq(DSL.field("chat.ROWID")))
				.leftJoin(DSL.table("handle").as("sender_handle")).on(DSL.field("message.handle_id").eq(DSL.field("sender_handle.ROWID")))
				.leftJoin(DSL.table("handle").as("other_handle")).on(DSL.field("message.other_handle").eq(DSL.field("other_handle.ROWID")));
		Result<Record16<Long, String, Long, Integer, Integer, String, String, Integer, Boolean, String, Boolean, Boolean, Boolean, String, String, String>> generalMessageRecords = filter != null ? buildStep.where(filter.filter()).fetch() : buildStep.fetch(); */
		
		//Creating the result list
		ArrayList<Blocks.ConversationItem> conversationItems = new ArrayList<>();
		ArrayList<Blocks.ModifierInfo> isolatedModifiers = new ArrayList<>();
		
		//Completing the query
		ResultQuery<?> resultQuery;
		if(filter != null) {
			//Applying the condition (must be given)
			SelectConditionStep<?> selectConditionStep = buildStep.where(filter.condition);
			
			if(filter.limit != -1 && filter.orderField != null) resultQuery = selectConditionStep.orderBy(filter.orderField).limit(filter.limit);
			else if(filter.limit != -1) resultQuery = buildStep.limit(filter.limit);
			else if(filter.orderField != null) resultQuery = buildStep.orderBy(filter.orderField);
			else resultQuery = buildStep;
		} else {
			resultQuery = buildStep;
		}
		
		//Checking if the data should be streamed
		if(streamingListener != null) {
			Cursor<?> cursor = resultQuery.fetchLazy();
			Result<?> records;
			
			while(cursor.hasNext()) {
				//Clearing the lists
				conversationItems.clear();
				isolatedModifiers.clear();
				
				//Fetching the next records
				records = cursor.fetchNext(20);
				
				//Processing the data
				List<TransientAttachmentInfo> attachmentFiles = streamingListener.acceptFileData ? new ArrayList<>() : null;
				processFetchDataResult(context, records, conversationItems, isolatedModifiers, attachmentFiles, reverseProcess);
				
				//Sending the data
				streamingListener.onChunkLoaded(conversationItems, isolatedModifiers);
				if(streamingListener.acceptFileData) streamingListener.onAttachmentChunkLoaded(attachmentFiles);
				//Breaking from the loop if a cancel has been requested
				if(streamingListener.cancelRequested) break;
			}
			
			//Logging a message
			Main.getLogger().finest("Fulfilled a mass retrieval request");
			
			//Calling the finished method
			if(!streamingListener.cancelRequested) streamingListener.onFinished();
			
			//Returning
			return null;
		}
		
		//Completing the query
		Result<?> records = resultQuery.fetch();
		
		//Processing the data
		long latestMessageID = processFetchDataResult(context, records, conversationItems, isolatedModifiers, null, reverseProcess);
		
		//Returning null if the item list is empty
		//if(conversationItems.isEmpty()) return null;
		
		//Adding applicable isolated modifiers to their messages
		/* for(Iterator<Blocks.ModifierInfo> iterator = isolatedModifiers.iterator(); iterator.hasNext();) {
			//Getting the modifier
			Blocks.ModifierInfo modifier = iterator.next();
			
			//Checking if the modifier is a sticker
			if(modifier instanceof Blocks.StickerModifierInfo || modifier instanceof Blocks.TapbackModifierInfo) {
				//Iterating over all the items
				for(Blocks.ConversationItem allItems : conversationItems) {
					//Skipping the remainder of the iteration if the item doesn't match
					if(!modifier.message.equals(allItems.guid) || !(allItems instanceof Blocks.MessageInfo)) continue;
					
					//Getting the message info
					Blocks.MessageInfo matchingItem = (Blocks.MessageInfo) allItems;
					
					//Adding the modifier
					if(modifier instanceof Blocks.StickerModifierInfo) matchingItem.stickers.add((Blocks.StickerModifierInfo) modifier);
					else if(modifier instanceof Blocks.TapbackModifierInfo) matchingItem.tapbacks.add((Blocks.TapbackModifierInfo) modifier);
					
					//Removing the item from the isolated modifier list
					iterator.remove();
					
					//Breaking from the loop
					break;
				}
			}
		} */
		
		//Logging a debug message
		if(!conversationItems.isEmpty()) Main.getLogger().finest("Found " + conversationItems.size() + " new item(s) from latest scan");
		
		//Returning the result
		return new DataFetchResult(conversationItems, isolatedModifiers, latestMessageID);
	}
	
	/**
	 * Processes a cursor from a data fetch
	 * @param context the DSL context to access the database with
	 * @param generalMessageRecords the cursor to pull data from
	 * @param conversationItems the list to add new conversation items to
	 * @param isolatedModifiers the list to add new loose modifiers to
	 * @param attachmentFiles the list to add found attachment files to (null if no attachment files wanted)
	 * @return the latest found message ID
	 */
	private long processFetchDataResult(DSLContext context, Result<?> generalMessageRecords, List<Blocks.ConversationItem> conversationItems, List<Blocks.ModifierInfo> isolatedModifiers, List<TransientAttachmentInfo> attachmentFiles, boolean reverseProcess) throws IOException, NoSuchAlgorithmException {
		long latestMessageID = -1;
		
		//Iterating over the results
		int recordCount = generalMessageRecords.size();
		for(int i2 = 0; i2 < recordCount; i2++) {
			int i = reverseProcess ? (recordCount - 1) - i2 : i2;
			
			//Getting the other parameters
			long rowID = generalMessageRecords.getValue(i, field("message.ROWID", Long.class));
			String guid = generalMessageRecords.getValue(i, field("message.guid", String.class));
			String chatGUID = generalMessageRecords.getValue(i, field("chat.guid", String.class));
			long date = generalMessageRecords.getValue(i, field("message.date", Long.class));
			/* Object dateObject = generalMessageRecords.getValue(i, "message.date");
			if(Long.class.isInstance(dateObject)) date = (long) dateObject;
			else date = (int) dateObject; */
			
			String sender = generalMessageRecords.getValue(i, field("message.is_from_me", Boolean.class)) ? null : generalMessageRecords.getValue(i, field("sender_handle.id", String.class));
			int itemType = generalMessageRecords.getValue(i, field("message.item_type", Integer.class));
			
			//Updating the latest message ID
			if(rowID > latestMessageID) latestMessageID = rowID;
			
			//Checking if the item is a message
			if(itemType == 0) {
				//Checking if the database supports association
				if(dbSupportsAssociation) {
					//Getting the association info
					String associatedMessage = generalMessageRecords.getValue(i, field("message.associated_message_guid", String.class));
					int associationType = generalMessageRecords.getValue(i, field("message.associated_message_type", Integer.class));
					int associationIndex = generalMessageRecords.getValue(i, field("message.associated_message_range_location", Integer.class));
					
					//Checking if there is an association
					if(associationType != 0) {
						//Example association string: p:0/69C164B2-2A14-4462-87FA-3D79094CFD83
						//Splitting the association between the protocol and GUID
						String[] associationData = associatedMessage.split(":");
						String associatedMessageGUID = "";
						
						if(associationData[0].equals("bp")) { //Associated with message extension (content from iMessage apps)
							associatedMessageGUID = associationData[1];
						} else if(associationData[0].equals("p")) { //Standard association
							associatedMessageGUID = associationData[1].split("/")[1];
						}
						
						//Checking if the association is a sticker
						if(associationType >= 1000 && associationType < 2000) {
							//Retrieving the sticker attachment
							Result<Record3<String, String, String>> fileRecord = context.select(field("attachment.guid", String.class), field("attachment.filename", String.class), field("attachment.mime_type", String.class))
									.from(DSL.table("message_attachment_join"))
									.join(DSL.table("attachment")).on(field("message_attachment_join.attachment_id").eq(field("attachment.ROWID")))
									.where(field("message_attachment_join.message_id").eq(rowID))
									.fetch();
							
							//Skipping the remainder of the iteration if there are no records
							if(fileRecord.isEmpty()) continue;
							
							//Getting the file (and skipping the remainder of the iteration if the file is invalid)
							String fileName = fileRecord.getValue(0, field("attachment.filename", String.class));
							if(fileName == null) continue;
							File file = new File(fileName.replaceFirst("~", System.getProperty("user.home")));
							if(!file.exists()) continue;
							String fileType = fileRecord.getValue(0, field("attachment.mime_type", String.class));
							
							//Reading and compressing the file
							byte[] fileBytes = Files.readAllBytes(file.toPath());
							fileBytes = CompressionHelper.compressDeflate(fileBytes, fileBytes.length);
							
							//Getting the file guid
							String fileGuid = fileRecord.getValue(0, field("attachment.guid", String.class));
							
							//Creating the modifier
							Blocks.StickerModifierInfo modifier = new Blocks.StickerModifierInfo(associatedMessageGUID, associationIndex, fileGuid, sender, date, fileBytes, fileType);
							
							//Finding the associated message in memory
							Blocks.MessageInfo matchingItem = null;
							for(Blocks.ConversationItem allItems : conversationItems) {
								if(!associatedMessageGUID.equals(allItems.guid) || !(allItems instanceof Blocks.MessageInfo)) continue;
								matchingItem = (Blocks.MessageInfo) allItems;
								break;
							}
							//Adding the sticker to the message if it was found
							if(matchingItem != null) matchingItem.stickers.add(modifier);
							//Otherwise adding the modifier to the isolated list
							isolatedModifiers.add(modifier);
							
							//Skipping the remainder of the iteration
							continue;
						}
						//Otherwise checking if the association is a tapback response
						else if(associationType < 4000) { //2000 - 2999 = tapback added / 3000 - 3999 = tapback removed
							//Getting the association data
							boolean tapbackAdded = associationType >= 2000 && associationType < 3000;
							int tapbackType = associationType % 1000;
							
							//Creating the modifier
							Blocks.TapbackModifierInfo modifier = new Blocks.TapbackModifierInfo(associatedMessageGUID, associationIndex, sender, tapbackAdded, tapbackType);
							
							//Finding the associated message in memory
							Blocks.MessageInfo matchingItem = null;
							if(associationType < 3000) { //If the message is an added tapback
								for(Blocks.ConversationItem allItems : conversationItems) {
									if(!associatedMessageGUID.equals(allItems.guid) || !(allItems instanceof Blocks.MessageInfo)) continue;
									matchingItem = (Blocks.MessageInfo) allItems;
									break;
								}
							}
							
							//Adding the tapback to the message if it was found
							if(matchingItem != null) matchingItem.tapbacks.add(modifier);
							//Otherwise adding the modifier to the isolated list
							isolatedModifiers.add(modifier);
							
							//Skipping the remainder of the iteration
							continue;
						}
					}
				}
				
				//Getting the detail parameters
				String text = generalMessageRecords.getValue(i, field("message.text", String.class));
				//if(text != null) text = text.replace("", "");
				if(text != null) {
					text = text.replace(Character.toString('\uFFFC'), "");
					text = text.replace(Character.toString('\uFFFD'), "");
					if(text.isEmpty()) text = null;
				}
				String subject = generalMessageRecords.getValue(i, field("message.subject", String.class));
				String sendStyle = dbSupportsSendStyle ? generalMessageRecords.getValue(i, field("message.expressive_send_style_id", String.class)) : null;
				int stateCode = determineMessageState(generalMessageRecords.getValue(i, field("message.is_sent", Boolean.class)),
						generalMessageRecords.getValue(i, field("message.is_delivered", Boolean.class)),
						generalMessageRecords.getValue(i, field("message.is_read", Boolean.class)));
				int errorCode = convertDBErrorCode(generalMessageRecords.getValue(i, field("message.error", Integer.class)));
				long dateRead = generalMessageRecords.getValue(i, field("message.date_read", Long.class));
				
				//Fetching the attachments
				List<SelectField<?>> attachmentFields = new ArrayList<>(Arrays.asList(field("attachment.ROWID", Long.class), field("attachment.guid", String.class), field("attachment.filename", String.class), field("attachment.transfer_name", String.class), field("attachment.mime_type", String.class), field("attachment.total_bytes", Long.class)));
				//if(dbSupportsAssociation) attachmentFields.add(DSL.field("attachment.is_sticker", Boolean.class));
				
				Condition filter = field("message_attachment_join.message_id").eq(rowID);
				if(dbSupportsHiddenAttachments) filter = filter.and(field("attachment.hide_attachment").isFalse());
				Result<?> fileRecords = context.select(attachmentFields)
						.from(DSL.table("message_attachment_join"))
						.join(DSL.table("attachment")).on(field("message_attachment_join.attachment_id").eq(field("attachment.ROWID")))
						.where(filter)
						.fetch();
				
				//Processing the attachments
				ArrayList<Blocks.AttachmentInfo> files = new ArrayList<>();
				for(int f = 0; f < fileRecords.size(); f++) {
					//Skipping the remainder of the iteration if the attachment is a sticker
					//if(dbSupportsAssociation && fileRecords.getValue(f, DSL.field("attachment.is_sticker", Boolean.class))) continue;
					
					//Adding the file
					String fileGUID = fileRecords.getValue(f, field("attachment.guid", String.class));
					String fileType = fileRecords.getValue(f, field("attachment.mime_type", String.class));
					String fileName = fileRecords.getValue(f, field("attachment.transfer_name", String.class));
					String filePath = fileRecords.getValue(f, field("attachment.filename", String.class));
					File file = filePath == null ? null : new File(filePath.replaceFirst("~", System.getProperty("user.home")));
					long fileSize = fileRecords.getValue(f, field("attachment.total_bytes", Long.class));
					long fileRow = fileRecords.getValue(f, field("attachment.ROWID", Long.class));
					
					//Updating the file name
					if(fileName == null) {
						if(filePath == null) continue; //Ignoring invalid files
						fileName = new File(filePath).getName(); //Determining the file name from its path
					}
					
					//Adding the file
					files.add(new Blocks.AttachmentInfo(fileGUID,
						fileName,
						fileType,
						fileSize,
						//The checksum will be calculated if the message is outgoing
						sender == null && file != null ? calculateChecksum(file) : null,
						fileRow));
					
					if(attachmentFiles != null && file != null) attachmentFiles.add(new TransientAttachmentInfo(fileGUID, date, file, fileName, fileType, fileSize));
				}
				
				//Adding the conversation item
				conversationItems.add(new Blocks.MessageInfo(rowID, guid, chatGUID, Main.getTimeHelper().toUnixTime(date), text, subject, sender, files, new ArrayList<>(), new ArrayList<>(), sendStyle, stateCode, errorCode, Main.getTimeHelper().toUnixTime(dateRead)));
			}
			//Otherwise checking if the item is a group action
			else if(itemType == 1) {
				//Getting the detail parameters
				String other = generalMessageRecords.getValue(i, field("other_handle.id", String.class));
				int groupActionType = convertDBGroupSubtype(generalMessageRecords.getValue(i, field("message.group_action_type", Integer.class)));
				
				//Adding the conversation item
				conversationItems.add(new Blocks.GroupActionInfo(rowID, guid, chatGUID, Main.getTimeHelper().toUnixTime(date), sender, other, groupActionType));
			}
			//Otherwise checking if the item is a chat rename
			else if(itemType == 2) {
				//Getting the detail parameters
				String newChatName = generalMessageRecords.getValue(i, field("message.group_title", String.class));
				
				//Adding the conversation item
				conversationItems.add(new Blocks.ChatRenameActionInfo(rowID, guid, chatGUID, Main.getTimeHelper().toUnixTime(date), sender, newChatName));
			}
			//Otherwise checking if the item is a chat leave
			else if(itemType == 3) {
				int dbGroupActionType = generalMessageRecords.getValue(i, field("message.group_action_type", Integer.class));
				//On macOS 11, this represents a chat icon change for some reason. We can't handle this, so just ignore.
				if(dbGroupActionType != 0) continue;
				
				//Getting the detail parameters
				int groupActionType = Blocks.GroupActionInfo.subtypeLeave;
				
				//Adding the conversation item
				conversationItems.add(new Blocks.GroupActionInfo(rowID, guid, chatGUID, Main.getTimeHelper().toUnixTime(date), sender, sender, groupActionType));
			}
		}
		
		//Returning the latest message ID
		return latestMessageID;
	}
	
	private List<Blocks.ModifierInfo> getUnreadUpdates(Connection connection) {
		//Creating the DSL context
		DSLContext context = DSL.using(connection, SQLDialect.SQLITE);
		
		//Fetching the data
		Result<Record6<Long, String, Boolean, Boolean, Boolean, Long>> results = context.select(DSL.max(field("message.ROWID", Long.class)), field("message.guid", String.class), field("message.is_sent", Boolean.class), field("message.is_delivered", Boolean.class), field("message.is_read", Boolean.class), field("message.date_read", Long.class))
			.from(DSL.table("message"))
			.join(DSL.table("chat_message_join")).on(field("message.ROWID").eq(field("chat_message_join.message_id")))
			.join(DSL.table("chat")).on(field("chat_message_join.chat_id").eq(field("chat.ROWID")))
			.where(field("message.is_from_me").isTrue())
			.groupBy(field("chat.ROWID")).fetch();
		
		//Iterating over the results
		List<Blocks.ModifierInfo> list = new ArrayList<>();
		for(int i = 0; i < results.size(); i++) {
			//Getting the result information
			String resultGuid = results.getValue(i, field("message.guid", String.class));
			int resultState = determineMessageState(results.getValue(i, field("message.is_sent", Boolean.class)),
				results.getValue(i, field("message.is_delivered", Boolean.class)),
				results.getValue(i, field("message.is_read", Boolean.class)));
			
			//Getting the item
			MessageState messageState;
			if(messageStates.containsKey(resultGuid)) messageState = messageStates.get(resultGuid);
			else {
				messageStates.put(resultGuid, new MessageState(resultState));
				continue;
			}
			
			//Resetting the item's depth
			messageState.depth = 0;
			
			//Getting the message states
			int cacheState = messageStates.get(resultGuid).state;
			
			//Checking if the states don't match
			if(cacheState != resultState) {
				//Updating the state
				messageState.state = resultState;
				
				//Logging a debug message
				Main.getLogger().finest("New activity status for message " + resultGuid + ": " + cacheState + " -> " + resultState);
				//Main.getLogger().finest("New activity status for message " + results.getValue(i, DSL.field("message.text", String.class)) + ": " + cacheState + " -> " + resultState);
				
				//Adding the modifier to the list
				list.add(new Blocks.ActivityStatusModifierInfo(resultGuid, resultState, Main.getTimeHelper().toUnixTime(results.getValue(i, field("message.date_read", Long.class)))));
			}
		}
		
		//Increasing the depth of the elements in the list, and removing them if they are deeper than 5
		messageStates.entrySet().removeIf(stringMessageStateEntry -> ++stringMessageStateEntry.getValue().depth > 5);
		
		return list;
	}
	
	private void indexTargetAvailability(Connection connection) throws SQLException {
		//Creating the DSL context
		DSLContext context = DSL.using(connection, SQLDialect.SQLITE);
		
		//Building the query
		Result<Record3<String, String, String>> queryResult = context.select(field("chat.guid", String.class), field("chat.service_name", String.class), field("handle.id", String.class))
				.from(DSL.table("chat"))
				.join(DSL.table("chat_handle_join")).on(field("chat.ROWID").eq(field("chat_handle_join.chat_id")))
				.join(DSL.table("handle")).on(field("chat_handle_join.handle_id").eq(field("handle.ROWID")))
				.groupBy(field("chat.guid"))
				.having(DSL.count(field("handle.id")).eq(1))
				.fetch();
		
		//Creating the results
		HashMap<String, CreationTargetingChat> resultList = new HashMap<>();
		for(int i = 0; i < queryResult.size(); i++) {
			String guid = queryResult.getValue(i, field("chat.guid", String.class));
			String service = queryResult.getValue(i, field("chat.service_name", String.class));
			String address = queryResult.getValue(i, field("handle.id", String.class));
			
			resultList.put(guid, new CreationTargetingChat(address, service));
		}
		
		//Setting the list
		creationTargetingAvailabilityList.set(resultList);
	}
	
	private static class MessageState {
		private int state;
		private int depth = 0;
		
		MessageState(int state) {
			this.state = state;
		}
	}
	
	private static int determineMessageState(boolean isSent, boolean isDelivered, boolean isRead) {
		//Determining the state code
		int stateCode = Blocks.MessageInfo.stateCodeIdle;
		if(isSent) stateCode = Blocks.MessageInfo.stateCodeSent;
		if(isDelivered) stateCode = Blocks.MessageInfo.stateCodeDelivered;
		if(isRead) stateCode = Blocks.MessageInfo.stateCodeRead;
		
		//Returning the state code
		return stateCode;
	}
	
	private static int convertDBErrorCode(int code) {
		return switch(code) {
			case 0 -> Blocks.MessageInfo.errorCodeOK;
			case 3 -> Blocks.MessageInfo.errorCodeNetwork;
			case 22 -> Blocks.MessageInfo.errorCodeUnregistered;
			default -> Blocks.MessageInfo.errorCodeUnknown;
		};
	}
	
	private static int convertDBGroupSubtype(int code) {
		return switch(code) {
			default -> Blocks.GroupActionInfo.subtypeUnknown;
			case 0 -> Blocks.GroupActionInfo.subtypeJoin;
			case 1 -> Blocks.GroupActionInfo.subtypeLeave;
		};
	}
	
	private static byte[] calculateChecksum(File file) throws IOException, NoSuchAlgorithmException {
		//Returning null if the file isn't ready
		if(!file.exists() || !file.isFile() || !file.canRead()) return null;
		
		MessageDigest messageDigest = MessageDigest.getInstance(CommConst.hashAlgorithm);
		try(InputStream inputStream = new DigestInputStream(new FileInputStream(file), messageDigest)) {
			byte[] buffer = new byte[1024];
			int lengthRead;
			do {
				lengthRead = inputStream.read(buffer);
			} while(lengthRead != -1);
		}
		
		return messageDigest.digest();
	}
	
	private static class DataFetchResult {
		final ArrayList<Blocks.ConversationItem> conversationItems;
		final ArrayList<Blocks.ModifierInfo> isolatedModifiers;
		final long latestMessageID;
		
		DataFetchResult(ArrayList<Blocks.ConversationItem> conversationItems, ArrayList<Blocks.ModifierInfo> isolatedModifiers, long latestMessageID) {
			this.conversationItems = conversationItems;
			this.isolatedModifiers = isolatedModifiers;
			this.latestMessageID = latestMessageID;
		}
	}
	
	public static class RetrievalFilter {
		final Condition condition;
		final int limit;
		final OrderField<?> orderField;
		
		public RetrievalFilter(Condition condition, int limit, OrderField<?> orderField) {
			this.condition = condition;
			this.limit = limit;
			this.orderField = orderField;
		}
	}
	
	public static class CreationTargetingChat {
		private final String address;
		private final String service;
		
		CreationTargetingChat(String address, String service) {
			this.address = address;
			this.service = service;
		}
		
		String getAddress() {
			return address;
		}
		
		String getService() {
			return service;
		}
	}
	
	private static class TransientAttachmentInfo {
		final String guid;
		final long messageDate;
		final File file;
		final String fileName;
		final String fileType;
		final long fileSize;
		
		TransientAttachmentInfo(String guid, long messageDate, File file, String fileName, String fileType, long fileSize) {
			this.guid = guid;
			this.messageDate = messageDate;
			this.file = file;
			this.fileName = fileName;
			this.fileType = fileType;
			this.fileSize = fileSize;
		}
	}
}