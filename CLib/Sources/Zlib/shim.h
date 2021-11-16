#include <zlib.h>

/**
 * Helper function for initializing a zlib stream
 * @param stream A pointer to the stream to initialize
 * @return The return code of deflateInit
 */
int zlibInitializeDeflate(z_stream *stream) {
	stream->zalloc = Z_NULL;
	stream->zfree = Z_NULL;
	stream->opaque = Z_NULL;

	return deflateInit(stream, Z_DEFAULT_COMPRESSION);
}
