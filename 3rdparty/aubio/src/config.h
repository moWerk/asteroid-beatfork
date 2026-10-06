/* Hand-written configuration for building aubio 0.4.9 inside BeatFork on
 * SailfishOS: plain C99 with libm, no fftw (aubio's bundled ooura FFT),
 * no sndfile or other I/O libraries (the app feeds audio itself). */
#ifndef AUBIO_SFOS_CONFIG_H
#define AUBIO_SFOS_CONFIG_H
#define HAVE_STDLIB_H 1
#define HAVE_STDIO_H 1
#define HAVE_MATH_H 1
#define HAVE_STRING_H 1
#define HAVE_ERRNO_H 1
#define HAVE_LIMITS_H 1
#define HAVE_STDARG_H 1
#define HAVE_C99_VARARGS_MACROS 1
#define HAVE_MEMCPY_HACKS 1
#endif
