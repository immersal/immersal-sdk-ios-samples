//
//  wrapper.cpp
//  PosePluginTester
//
//  Created by Mikko Karvonen on 4.9.2020.
//  Copyright © 2020 Mikko Karvonen. All rights reserved.
//

#include "PosePlugin.h"

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

    int icvGetInteger(const char* param);
    int icvSetInteger(const char* param, int value);

    void PP_RegisterLogCallback(LOGCALLBACK callback);
}
