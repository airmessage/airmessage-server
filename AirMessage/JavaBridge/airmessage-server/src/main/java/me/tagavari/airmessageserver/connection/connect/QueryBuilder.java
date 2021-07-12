package me.tagavari.airmessageserver.connection.connect;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

class QueryBuilder {
	private final StringBuilder stringBuilder = new StringBuilder();
	private boolean itemAdded = false;
	
	QueryBuilder with(String key, boolean value) {
		return with(key, Boolean.toString(value));
	}
	
	QueryBuilder with(String key, short value) {
		return with(key, Short.toString(value));
	}
	
	QueryBuilder with(String key, float value) {
		return with(key, Float.toString(value));
	}
	
	QueryBuilder with(String key, int value) {
		return with(key, Integer.toString(value));
	}
	
	QueryBuilder with(String key, double value) {
		return with(key, Double.toString(value));
	}
	
	QueryBuilder with(String key, long value) {
		return with(key, Long.toString(value));
	}
	
	QueryBuilder with(String key, String value) {
		if(itemAdded) stringBuilder.append("&");
		else itemAdded = true;
		
		stringBuilder.append(key).append('=').append(URLEncoder.encode(value, StandardCharsets.UTF_8));
		
		return this;
	}
	
	@Override
	public String toString() {
		return stringBuilder.toString();
	}
}