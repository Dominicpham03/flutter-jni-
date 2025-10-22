#ifndef IPERF_CONFIG_H
#define IPERF_CONFIG_H

#define PACKAGE_NAME "iperf"
#define PACKAGE_VERSION "3.19"
#define IPERF_VERSION "3.19"
#define PACKAGE_STRING "iperf 3.19"

// Platform detection
#ifdef __APPLE__
// iOS/macOS specific configurations
#define HAVE_CONFIG_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_ARPA_INET_H 1
#define HAVE_NETDB_H 1
#define HAVE_UNISTD_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_PTHREAD_H 1
#define HAVE_SELECT 1
#define HAVE_GETTIMEOFDAY 1

// macOS/iOS has machine/endian.h and libkern/OSByteOrder.h
#define HAVE_LIBKERN_OSBYTEORDER_H 1

// iOS has stdatomic.h
#define HAVE_STDATOMIC_H 1

// Disable SCTP for iOS
#undef HAVE_SCTP_H

#else
// Android specific configurations
#define HAVE_CONFIG_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_ARPA_INET_H 1
#define HAVE_NETDB_H 1
#define HAVE_UNISTD_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_PTHREAD_H 1
#define HAVE_SELECT 1
#define HAVE_GETTIMEOFDAY 1

// Android has sys/endian.h
#define HAVE_SYS_ENDIAN_H 1
#define HAVE_ENDIAN_H 1

// Android NDK API 24+ has stdatomic.h
#if __ANDROID_API__ >= 24
#define HAVE_STDATOMIC_H 1
#endif

// Disable SCTP for Android
#undef HAVE_SCTP_H

#endif

#endif
