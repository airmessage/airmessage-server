package me.tagavari.airmessageserver.exception;

//When the system tries to allocate more memory than a hardcoded limit
public class LargeAllocationException extends Exception {
	public LargeAllocationException(long size, long limit) {
		super("Tried to allocate " + size + ", but limit is " + limit);
	}
	
	public LargeAllocationException(long size, long limit, Throwable cause) {
		super("Tried to allocate " + size + ", but limit is " + limit, cause);
	}
}