package me.tagavari.airmessageserver.helper;

import java.io.IOException;
import java.io.InputStream;

public class LookAheadStreamIterator {
	//Creating the current and future buffer
	private byte[] bufferCurrent, bufferFuture, bufferSwap;
	private final InputStream inputStream;
	
	private int lengthCurrent;
	
	public LookAheadStreamIterator(int bufferLength, InputStream inputStream) throws IOException {
		//Initializing the buffers
		bufferCurrent = new byte[bufferLength];
		bufferFuture = new byte[bufferLength];
		
		//Setting the input stream
		this.inputStream = inputStream;
		
		//Read the initial current data
		lengthCurrent = inputStream.read(bufferCurrent);
	}
	
	public boolean hasNext() {
		return lengthCurrent != -1;
	}
	
	public ForwardsStreamData next() throws IOException {
		//Read the future data
		int lengthFuture = inputStream.read(bufferFuture);
		
		//Create the stream data
		ForwardsStreamData data = new ForwardsStreamData(bufferCurrent, lengthCurrent, lengthFuture == -1);
		
		//Swap the current and future buffers (so that the current buffer will be returned, and the future buffer will be overwritten)
		bufferSwap = bufferCurrent;
		bufferCurrent = bufferFuture;
		bufferFuture = bufferSwap;
		
		//Update the length
		lengthCurrent = lengthFuture;
		
		//Return the stream data
		return data;
	}
	
	public static class ForwardsStreamData {
		private final byte[] data;
		private final int length;
		private final boolean isLast;
		
		public ForwardsStreamData(byte[] data, int length, boolean isLast) {
			this.data = data;
			this.length = length;
			this.isLast = isLast;
		}
		
		public byte[] getData() {
			return data;
		}
		
		public int getLength() {
			return length;
		}
		
		public boolean isLast() {
			return isLast;
		}
	}
}