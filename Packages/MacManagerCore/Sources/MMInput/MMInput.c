// Adapted from Scroll Reverser, Copyright 2011 Nicholas Moore, Apache-2.0.
// Changes: runtime SPI resolution, validation and a narrow read/transform interface.
// See MacManager/Resources/ThirdPartyNotices.txt.
#include "MMInput.h"
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <IOKit/IOKitLib.h>

typedef CFTypeRef (*CopyHIDEvent)(CGEventRef);
typedef double (*GetHIDFloat)(CFTypeRef, uint32_t);
typedef void (*SetHIDFloat)(CFTypeRef, uint32_t, double);
typedef uint64_t (*GetHIDSender)(CFTypeRef);
static CopyHIDEvent copy_hid;
static GetHIDFloat get_float;
static SetHIDFloat set_float;
static GetHIDSender get_sender;
static pthread_once_t once = PTHREAD_ONCE_INIT;

static void resolve_bridge(void) {
    // Optional private symbols are isolated here. Never guess another ABI if unavailable.
    copy_hid = (CopyHIDEvent)dlsym(RTLD_DEFAULT, "CGEventCopyIOHIDEvent");
    get_float = (GetHIDFloat)dlsym(RTLD_DEFAULT, "IOHIDEventGetFloatValue");
    set_float = (SetHIDFloat)dlsym(RTLD_DEFAULT, "IOHIDEventSetFloatValue");
    get_sender = (GetHIDSender)dlsym(RTLD_DEFAULT, "IOHIDEventGetSenderID");
}

MMScrollEventOrigin mm_scroll_event_origin(CGEventRef event) {
    MMScrollEventOrigin result = {0};
    if (!event || CGEventGetType(event) != kCGEventScrollWheel) return result;
    pthread_once(&once, resolve_bridge);
    result.source_pid = CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
    result.hid_inspection_available = copy_hid != NULL;
    if (!copy_hid) return result;
    CFTypeRef hid = copy_hid(event);
    if (hid) {
        result.has_hid = true;
        if (get_sender) result.sender_id = get_sender(hid);
        CFRelease(hid);
    }
    return result;
}

// Local-device identification inspired by Scroll Reverser 04c167575d (Apache-2.0).
// No product names, serial numbers or persistent identifiers are collected.
MMScrollDeviceKind mm_scroll_local_device_kind(uint64_t sender_id) {
    if (!sender_id) return MMScrollDeviceUnknown;
    io_registry_entry_t entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(sender_id));
    if (!entry) return MMScrollDeviceUnknown;
    bool mouse = false;
    bool trackpad = false;
    // The HID event service can be a child of the multitouch driver.
    // Bound traversal and release every registry object and copied property.
    for (unsigned depth = 0; entry && depth < 8; depth++) {
        if (IOObjectConformsTo(entry, "AppleMultitouchTrackpadHIDEventDriver")) trackpad = true;
        CFTypeRef acceleration = IORegistryEntryCreateCFProperty(entry, CFSTR("HIDScrollAccelerationType"), kCFAllocatorDefault, 0);
        if (acceleration) {
            if (CFGetTypeID(acceleration) == CFStringGetTypeID()) {
                if (CFEqual(acceleration, CFSTR("HIDTrackpadScrollAcceleration"))) trackpad = true;
                if (CFEqual(acceleration, CFSTR("HIDMouseScrollAcceleration"))) mouse = true;
            }
            CFRelease(acceleration);
        }
        io_registry_entry_t parent = IO_OBJECT_NULL;
        if (!trackpad && depth + 1 < 8) IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent);
        IOObjectRelease(entry);
        entry = parent;
        if (trackpad) break;
    }
    // No positive device evidence means fallback, rather than guessing "mouse".
    return trackpad ? MMScrollDeviceTrackpad : mouse ? MMScrollDeviceMouse : MMScrollDeviceUnknown;
}
bool mm_scroll_bridge_available(void) {
    pthread_once(&once, resolve_bridge);
    return copy_hid && get_float && set_float;
}

bool mm_scroll_reverse_event(CGEventRef event) {
    return mm_scroll_reverse_axes(event, true, true);
}

/// Validates every representation of the selected axes before reversing their deltas.
/// Captures the original values before setters can change related fields.
bool mm_scroll_reverse_axes(CGEventRef event, bool vertical, bool horizontal) {
    if ((!vertical && !horizontal) || !event || CGEventGetType(event) != kCGEventScrollWheel || !mm_scroll_bridge_available()) return false;
    const bool reversed[] = {vertical, horizontal};
    const CGEventField line_fields[] = {kCGScrollWheelEventDeltaAxis1, kCGScrollWheelEventDeltaAxis2};
    const CGEventField point_fields[] = {kCGScrollWheelEventPointDeltaAxis1, kCGScrollWheelEventPointDeltaAxis2};
    const CGEventField fixed_fields[] = {kCGScrollWheelEventFixedPtDeltaAxis1, kCGScrollWheelEventFixedPtDeltaAxis2};
    const uint32_t hid_fields[] = {(6u << 16) | 1u, (6u << 16) | 0u}; // scroll Y, X
    int64_t lines[2], points[2];
    double fixed[2], hid_values[2] = {0, 0};
    // Read every selected representation before writing: a line setter also changes point/fixed fields.
    for (int i = 0; i < 2; i++) {
        if (!reversed[i]) continue;
        lines[i] = CGEventGetIntegerValueField(event, line_fields[i]);
        points[i] = CGEventGetIntegerValueField(event, point_fields[i]);
        fixed[i] = CGEventGetDoubleValueField(event, fixed_fields[i]);
        if (lines[i] <= INT32_MIN || lines[i] > INT32_MAX || points[i] <= INT32_MIN || points[i] > INT32_MAX
            || !isfinite(fixed[i]) || fabs(fixed[i]) >= 32768) return false;
    }
    CFTypeRef hid = copy_hid(event);
    if (hid) {
        for (int i = 0; i < 2; i++) {
            if (!reversed[i]) continue;
            hid_values[i] = get_float(hid, hid_fields[i]);
            if (!isfinite(hid_values[i])) { CFRelease(hid); return false; }
        }
    }
    for (int i = 0; i < 2; i++) {
        if (!reversed[i]) continue;
        CGEventSetIntegerValueField(event, line_fields[i], -lines[i]);
        CGEventSetDoubleValueField(event, fixed_fields[i], -fixed[i]);
        CGEventSetIntegerValueField(event, point_fields[i], -points[i]);
        if (hid) set_float(hid, hid_fields[i], -hid_values[i]);
    }
    if (hid) CFRelease(hid);
    return true;
}
