#ifndef ZlibHelpers_h
#define ZlibHelpers_h

#include <zlib.h>

/**
 * Helper function for initializing a zlib deflate stream
 * @param stream A pointer to the stream to initialize
 * @return The return code of deflateInit
 */
static inline int zlibInitializeDeflate(z_stream *stream) {
	stream->zalloc = Z_NULL;
	stream->zfree = Z_NULL;
	stream->opaque = Z_NULL;

	return deflateInit(stream, Z_DEFAULT_COMPRESSION);
}

/**
 * Helper function for initializing a zlib inflate stream
 * @param stream A pointer to the stream to initialize
 * @return The return code of inflateInit
 */
static inline int zlibInitializeInflate(z_stream *stream) {
	stream->zalloc = Z_NULL;
	stream->zfree = Z_NULL;
	stream->opaque = Z_NULL;
	stream->avail_in = 0;
	stream->next_in = Z_NULL;

	return inflateInit(stream);
}

#endif /* ZlibHelpers_h */
