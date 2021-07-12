package me.tagavari.airmessageserver.connection;

import me.tagavari.airmessageserver.jni.JNIPreferences;
import me.tagavari.airmessageserver.server.Main;

import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.security.spec.KeySpec;
import java.util.Arrays;

public class EncryptionHelper {
	//Creating the reference values
	private static final int saltLen = 8; //8 bytes
	private static final int ivLen = 12; //12 bytes (instead of 16 because of GCM)
	private static final String keyFactoryAlgorithm = "PBKDF2WithHmacSHA256";
	private static final String keyAlgorithm = "AES";
	private static final String cipherTransformation = "AES/GCM/NoPadding";
	private static final int keyIterationCount = 10000;
	private static final int keyLength = 128; //128 bits
	
	private static String getKey() {
		return JNIPreferences.getPassword();
	}
	
	public static byte[] encrypt(byte[] inData) throws GeneralSecurityException {
		SecureRandom random = Main.getSecureRandom();
		
		//Generating a salt
		byte[] salt = new byte[saltLen];
		random.nextBytes(salt);
		
		//Creating the key
		SecretKeyFactory secretKeyFactory = SecretKeyFactory.getInstance(keyFactoryAlgorithm);
		KeySpec keySpec = new PBEKeySpec(getKey().toCharArray(), salt, keyIterationCount, keyLength);
		SecretKey secretKey = secretKeyFactory.generateSecret(keySpec);
		SecretKeySpec secretKeySpec = new SecretKeySpec(secretKey.getEncoded(), keyAlgorithm);
		
		//Generating the IV
		byte[] iv = new byte[ivLen];
		random.nextBytes(iv);
		GCMParameterSpec gcmSpec = new GCMParameterSpec(keyLength, iv);
		
		Cipher cipher = Cipher.getInstance(cipherTransformation);
		cipher.init(Cipher.ENCRYPT_MODE, secretKeySpec, gcmSpec);
		
		//Encrypting the data
		byte[] data = cipher.doFinal(inData);
		
		//Combining the salt, IV, and data
		byte[] allByteArray = new byte[saltLen + ivLen + data.length];
		ByteBuffer byteBuffer = ByteBuffer.wrap(allByteArray);
		byteBuffer.put(salt);
		byteBuffer.put(iv);
		byteBuffer.put(data);
		return byteBuffer.array();
	}
	
	public static byte[] decrypt(byte[] inData) throws GeneralSecurityException {
		//Reading the data
		byte[] salt = Arrays.copyOfRange(inData, 0, saltLen);
		byte[] iv = Arrays.copyOfRange(inData, saltLen, saltLen + ivLen);
		byte[] data = Arrays.copyOfRange(inData, saltLen + ivLen, inData.length);
		
		//Creating the key
		SecretKeyFactory secretKeyFactory = SecretKeyFactory.getInstance(keyFactoryAlgorithm);
		KeySpec keySpec = new PBEKeySpec(getKey().toCharArray(), salt, keyIterationCount, keyLength);
		SecretKey secretKey = secretKeyFactory.generateSecret(keySpec);
		SecretKeySpec secretKeySpec = new SecretKeySpec(secretKey.getEncoded(), keyAlgorithm);
		
		//Creating the IV
		GCMParameterSpec gcmSpec = new GCMParameterSpec(keyLength, iv);
		
		//Creating the cipher
		Cipher cipher = Cipher.getInstance(cipherTransformation);
		cipher.init(Cipher.DECRYPT_MODE, secretKeySpec, gcmSpec);
		
		//Deciphering the data
		return cipher.doFinal(data);
	}
}