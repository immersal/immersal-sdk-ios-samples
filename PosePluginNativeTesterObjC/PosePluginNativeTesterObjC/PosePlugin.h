// Copyright (C) 2022 Immersal Ltd. All Rights Reserved.

#pragma once

typedef void (*LOGCALLBACK)(const char* msg);

struct PPVector3 {
	float x;
	float y;
	float z;
	inline static float Dot(const PPVector3& a, const PPVector3& b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
};

struct PPQuaternion {
	float x;
	float y;
	float z;
	float w;
	inline static float Dot(const PPQuaternion& a, const PPQuaternion& b) { return a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w; }
};

struct CaptureInfo {
	int captureSize;
	int connected;
};

extern "C" {
	struct CaptureInfo icvCaptureImage(void *capture, int captureSizeMax, void *pixels, int width, int height, int channels, int useMatching);
	int icvLoadMap(const char *);
	int icvFreeMap(int mapHandle);
	int icvLocalize(float *pos, float *rot, int n, int *handles, int width, int height, float *intrinsics, void *pixels, int matchingBudget, int minimumMatchCount, float distanceRatio, float motionThreshold, int method);
	int icvLocalizeExt(float *pos, float *rot, int n, int *handles, int width, int height, float *intrinsics, float *distortion, void *pixels, int matchingBudget, int minimumMatchCount, float distanceRatio, float motionThreshold, int method);
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

	void PP_RegisterLogCallback(LOGCALLBACK callback);
}
