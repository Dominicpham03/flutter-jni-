/* android_pthread_compat.h - Android pthread compatibility shims */
#ifndef ANDROID_PTHREAD_COMPAT_H
#define ANDROID_PTHREAD_COMPAT_H

#ifdef __ANDROID__

#include <pthread.h>
#include <errno.h>

/* Android doesn't support pthread cancellation, so we provide no-op stubs */

/* Cancellation type values */
#ifndef PTHREAD_CANCEL_ASYNCHRONOUS
#define PTHREAD_CANCEL_ASYNCHRONOUS 0
#endif

#ifndef PTHREAD_CANCEL_DEFERRED
#define PTHREAD_CANCEL_DEFERRED 1
#endif

/* Cancellation state values */
#ifndef PTHREAD_CANCEL_ENABLE
#define PTHREAD_CANCEL_ENABLE 0
#endif

#ifndef PTHREAD_CANCEL_DISABLE
#define PTHREAD_CANCEL_DISABLE 1
#endif

/* Mutex types */
#ifndef PTHREAD_MUTEX_ERRORCHECK
#define PTHREAD_MUTEX_ERRORCHECK PTHREAD_MUTEX_ERRORCHECK_NP
#endif

/* Stub implementations for unsupported pthread cancellation functions */
static inline int pthread_cancel(pthread_t thread) {
    /* Android doesn't support pthread_cancel - return success as no-op */
    (void)thread;
    return 0;
}

static inline int pthread_setcanceltype(int type, int *oldtype) {
    /* Android doesn't support pthread cancellation - return success as no-op */
    if (oldtype) {
        *oldtype = PTHREAD_CANCEL_DEFERRED;
    }
    (void)type;
    return 0;
}

static inline int pthread_setcancelstate(int state, int *oldstate) {
    /* Android doesn't support pthread cancellation - return success as no-op */
    if (oldstate) {
        *oldstate = PTHREAD_CANCEL_ENABLE;
    }
    (void)state;
    return 0;
}

#endif /* __ANDROID__ */

#endif /* ANDROID_PTHREAD_COMPAT_H */
