package me.tagavari.airmessageserver.connection.direct;

import java.util.Collection;
import java.util.Iterator;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;

class WriterThread extends Thread {
	//Creating the queue
	private final BlockingQueue<PacketStruct> uploadQueue = new LinkedBlockingQueue<>();
	
	private final Collection<ClientSocket> clientList;
	
	public WriterThread(Collection<ClientSocket> clientList) {
		this.clientList = clientList;
	}
	
	@Override
	public void run() {
		try {
			while(!isInterrupted()) {
				PacketStruct packet = uploadQueue.take();
				if(packet.target == null) {
					synchronized(clientList) {
						for(ClientSocket client : clientList) {
							if(!client.isClientRegistered()) continue;
							client.sendDataSync(packet.content, packet.isEncrypted);
						}
					}
				} else {
					packet.target.sendDataSync(packet.content, packet.isEncrypted);
				}
				if(packet.sentRunnable != null) packet.sentRunnable.run();
			}
		} catch(InterruptedException exception) {
			return;
		}
	}
	
	void sendPacket(PacketStruct packet) {
		uploadQueue.add(packet);
	}
	
	static class PacketStruct {
		final ClientSocket target;
		private final byte[] content;
		final boolean isEncrypted;
		Runnable sentRunnable = null;
		
		PacketStruct(ClientSocket target, byte[] content, boolean isEncrypted) {
			this.target = target;
			this.isEncrypted = isEncrypted;
			this.content = content;
		}
		
		PacketStruct(ClientSocket target, byte[] content, boolean isEncrypted, Runnable sentRunnable) {
			this(target, content, isEncrypted);
			this.sentRunnable = sentRunnable;
		}
	}
}