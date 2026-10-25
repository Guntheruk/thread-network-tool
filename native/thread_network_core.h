#ifndef THREAD_NETWORK_CORE_H
#define THREAD_NETWORK_CORE_H
#include <stddef.h>
#if defined(_WIN32)
# if defined(TNT_BUILDING_CORE)
#  define TNT_API __declspec(dllexport)
# else
#  define TNT_API __declspec(dllimport)
# endif
#else
# define TNT_API __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
TNT_API const char* tnt_version(void);
TNT_API int tnt_inspect_dataset(const char* hex, char* output, size_t output_capacity);
#ifdef __cplusplus
}
#endif
#endif
