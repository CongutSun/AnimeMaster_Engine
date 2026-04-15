#ifndef ANIMEMASTER_H
#define ANIMEMASTER_H

#include <stdint.h>
#include <stdbool.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

FFI_PLUGIN_EXPORT bool InitializeEngineCore();
FFI_PLUGIN_EXPORT const char* GetEngineVersion();
FFI_PLUGIN_EXPORT const char* ParseMagnetLink(const char* magnetUri);
FFI_PLUGIN_EXPORT const char* ScanLocalDirectory(const char* path);

#ifdef __cplusplus
}
#endif

#endif