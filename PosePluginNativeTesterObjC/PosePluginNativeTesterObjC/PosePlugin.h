//  Copyright (C) 2024 Immersal - Part of Hexagon. All Rights Reserved.

#pragma once

typedef void (*LOGCALLBACK)(const char* msg);

struct CaptureInfo {
	int captureSize;
	int connected;
};

struct LocalizeInfo {
    int handle;
    float px, py, pz;
    float r00, r01, r02, r10, r11, r12, r20, r21, r22;
    int confidence;
};

#ifdef __cplusplus
extern "C" {
#endif
    struct CaptureInfo icvCaptureImage(void *capture, int captureSizeMax, void *pixels, int width, int height, int channels, int useMatching);

    int icvMapAddImage(void *pixels, int width, int height, int channels, float *intrinsics, float *pos, float *rot);
    int icvMapImageGetCount();
    int icvMapPrepare(const char* path);
    int icvMapGet(void *map);
    int icvMapPointsGetCount();
    int icvMapPointsGet(float *p, int countMax);
    int icvMapResourcesFree();

    int icvLoadMap(const char *);
    int icvFreeMap(int mapHandle);

    struct LocalizeInfo icvLocalize(int n, int *handles, int width, int height, float *intrinsics, void *pixels, int solverType, float *rot);
    struct LocalizeInfo icvLocalizeExt(int n, int *handles, int width, int height, float *intrinsics, float *distortion, void *pixels);

    int icvMapToEcefGet(double *mapToEcef, int handle);
    int icvPosMapToEcef(double *ecef, float *map, double *mapToEcef);
    int icvPosEcefToWgs84(double *wgs84, double *ecef);
    int icvPosWgs84ToEcef(double *ecef, double *wgs84);
    int icvPosEcefToMap(float *map, double *ecef, double *mapToecef);
    int icvRotMapToEcef(float *ecef, float *map, double *mapToecef);
    int icvRotEcefToMap(float *map, float *ecef, double *mapToecef);

    int icvPointsGet(int mapHandle, float *p, int countMax);
    int icvPointsGetCount(int mapId);

    int icvGetInteger(const char* param);
    int icvSetInteger(const char* param, int value);
    int icvValidateUser(const char* token);

    void PP_RegisterLogCallback(LOGCALLBACK callback);
#ifdef __cplusplus
}
#endif
