package me.tagavari.airmessageserver.common;

import java.nio.BufferOverflowException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

public class AirPacker implements AutoCloseable {
	//50 MiB
	private static final int bufferSize = 50 * 1024 * 1024;
	//Shared instance for write operations
	private static final AirPacker instance = new AirPacker(ByteBuffer.allocate(bufferSize));
	
	public static AirPacker get() {
		return instance;
	}
	
	private final ByteBuffer byteBuffer;
	
	private AirPacker(ByteBuffer byteBuffer) {
		this.byteBuffer = byteBuffer;
		byteBuffer.mark();
	}
	
	public AirPacker(int capacity) {
		this(ByteBuffer.allocate(capacity));
	}
	
	public void packBoolean(boolean value) throws BufferOverflowException {
		byteBuffer.put((byte) (value ? 1 : 0));
	}
	
	public void packShort(short value) throws BufferOverflowException {
		byteBuffer.putShort(value);
	}
	
	public void packInt(int value) throws BufferOverflowException {
		byteBuffer.putInt(value);
	}
	
	public void packArrayHeader(int value) throws BufferOverflowException {
		packInt(value);
	}
	
	public void packLong(long value) throws BufferOverflowException {
		byteBuffer.putLong(value);
	}
	
	public void packDouble(double value) throws BufferOverflowException {
		byteBuffer.putDouble(value);
	}
	
	public void packString(String value) throws BufferOverflowException {
		packPayload(value.getBytes(StandardCharsets.UTF_8));
	}
	
	public void packNullableString(String value) throws BufferOverflowException {
		if(value == null) {
			packBoolean(false);
		} else {
			packBoolean(true);
			packPayload(value.getBytes(StandardCharsets.UTF_8));
		}
	}
	
	public void packPayload(byte[] bytes) throws BufferOverflowException {
		packPayload(bytes, bytes.length);
	}
	
	public void packPayload(byte[] bytes, int length) throws BufferOverflowException {
		packInt(length);
		byteBuffer.put(bytes, 0, length);
	}
	
	public void packNullablePayload(byte[] bytes) throws BufferOverflowException {
		if(bytes == null) {
			packBoolean(false);
		} else {
			packBoolean(true);
			packPayload(bytes);
		}
	}
	
	public byte[] toByteArray() {
		return Arrays.copyOfRange(byteBuffer.array(), 0, byteBuffer.position());
	}
	
	public void reset() {
		byteBuffer.reset();
	}
	
	@Override
	public void close() {
		reset();
	}
}