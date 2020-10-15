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
