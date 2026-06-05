#ifndef HCNETSDK_COMPAT_H
#define HCNETSDK_COMPAT_H

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <QDebug>
#include <QTimer>
#include <QImage>
#include <QPainter>
#include <thread>
#include <chrono>

#ifndef PBYTE
#define PBYTE unsigned char*
#endif

#ifndef LPSTR
#define LPSTR char*
#endif

#ifndef RECT
typedef struct tagRECT {
    long left;
    long top;
    long right;
    long bottom;
} RECT;
#endif

#ifndef SYSTEMTIME
typedef struct _SYSTEMTIME {
    unsigned short wYear;
    unsigned short wMonth;
    unsigned short wDayOfWeek;
    unsigned short wDay;
    unsigned short wHour;
    unsigned short wMinute;
    unsigned short wSecond;
    unsigned short wMilliseconds;
} SYSTEMTIME;
#endif

// Include the REAL Hikvision SDK!
#include "hikvision_sdk/inc/HCNetSDK.h"
#include "hikvision_sdk/inc/plaympeg4.h"

#endif // HCNETSDK_COMPAT_H
