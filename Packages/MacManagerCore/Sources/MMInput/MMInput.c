// Adapted from Scroll Reverser, Copyright 2011 Nicholas Moore, Apache-2.0.
// Changes: runtime SPI resolution, validation and a narrow read/transform interface.
// See MacManager/Resources/ThirdPartyNotices.txt.
#include "MMInput.h"
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stdint.h>

typedef CFTypeRef (*CopyHIDEvent)(CGEventRef);
typedef double (*GetHIDFloat)(CFTypeRef, uint32_t);
typedef void (*SetHIDFloat)(CFTypeRef, uint32_t, double);
static CopyHIDEvent copy_hid;
static GetHIDFloat get_float;
static SetHIDFloat set_float;
static pthread_once_t once = PTHREAD_ONCE_INIT;

static void resolve_bridge(void) {
    // Optional private symbols are isolated here. Never guess another ABI if unavailable.
    copy_hid = (CopyHIDEvent)dlsym(RTLD_DEFAULT, "CGEventCopyIOHIDEvent");
    get_float = (GetHIDFloat)dlsym(RTLD_DEFAULT, "IOHIDEventGetFloatValue");
    set_float = (SetHIDFloat)dlsym(RTLD_DEFAULT, "IOHIDEventSetFloatValue");
}
bool mm_scroll_bridge_available(void) {
    pthread_once(&once, resolve_bridge);
    return copy_hid && get_float && set_float;
}

bool mm_scroll_reverse_event(CGEventRef event) {
    if (!event || CGEventGetType(event) != kCGEventScrollWheel || !mm_scroll_bridge_available()) return false;
    const CGEventField line_fields[] = {kCGScrollWheelEventDeltaAxis1, kCGScrollWheelEventDeltaAxis2};
    const CGEventField point_fields[] = {kCGScrollWheelEventPointDeltaAxis1, kCGScrollWheelEventPointDeltaAxis2};
    const CGEventField fixed_fields[] = {kCGScrollWheelEventFixedPtDeltaAxis1, kCGScrollWheelEventFixedPtDeltaAxis2};
    const uint32_t hid_fields[] = {(6u << 16) | 1u, (6u << 16) | 0u}; // scroll Y, X
    int64_t lines[2], points[2];
    double fixed[2], hid_values[2] = {0, 0};
    // Read every representation before writing: a line setter also changes point/fixed fields.
    for (int i = 0; i < 2; i++) {
        lines[i] = CGEventGetIntegerValueField(event, line_fields[i]);
        points[i] = CGEventGetIntegerValueField(event, point_fields[i]);
        fixed[i] = CGEventGetDoubleValueField(event, fixed_fields[i]);
        if (lines[i] <= INT32_MIN || lines[i] > INT32_MAX || points[i] <= INT32_MIN || points[i] > INT32_MAX
            || !isfinite(fixed[i]) || fabs(fixed[i]) >= 32768) return false;
    }
    CFTypeRef hid = copy_hid(event);
    if (hid) {
        for (int i = 0; i < 2; i++) {
            hid_values[i] = get_float(hid, hid_fields[i]);
            if (!isfinite(hid_values[i])) { CFRelease(hid); return false; }
        }
    }
    for (int i = 0; i < 2; i++) {
        CGEventSetIntegerValueField(event, line_fields[i], -lines[i]);
        CGEventSetDoubleValueField(event, fixed_fields[i], -fixed[i]);
        CGEventSetIntegerValueField(event, point_fields[i], -points[i]);
        if (hid) set_float(hid, hid_fields[i], -hid_values[i]);
    }
    if (hid) CFRelease(hid);
    return true;
}
