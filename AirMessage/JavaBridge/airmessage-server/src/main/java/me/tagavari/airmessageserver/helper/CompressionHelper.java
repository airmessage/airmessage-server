package me.tagavari.airmessageserver.helper;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.util.zip.DeflaterOutputStream;
import java.util.zip.InflaterOutputStream;

public class CompressionHelper {
	/**
	 * Deflates a byte array
	 * @param data The data to compress
	 * @param length The length of the data to read and compress
	 * @return The compressed data
	 * @throws IOException If an I/O error has occurred
	 */
	public static byte[] compressDeflate(byte[] data, int length) throws IOException {
		try(ByteArrayOutputStream fin = new ByteArrayOutputStream(); OutputStream out = new DeflaterOutputStream(fin)) {
			out.write(data, 0, length);
			out.close();
			return fin.toByteArray();
		}
	}
	
	/**
	 * Inflates a byte array
	 * @param data The data to decompress
	 * @param length The length of the data to read and decompress
	 * @return The decompressed data
	 * @throws IOException If an I/O error has occurred
	 */
	public static byte[] decompressInflate(byte[] data, int length) throws IOException {
		try(ByteArrayOutputStream fin = new ByteArrayOutputStream(); OutputStream out = new InflaterOutputStream(fin)) {
			out.write(data, 0, length);
			out.close();
			return fin.toByteArray();
		}
	}
}