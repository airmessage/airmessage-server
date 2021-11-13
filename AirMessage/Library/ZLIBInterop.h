#include <zlib.h>

/**
 * Helper function for initializing a zlib stream
 * @param stream A pointer to the stream to initialize
 * @return The return code of deflateInit
 */
int zlibInitializeDeflate(z_stream* stream);