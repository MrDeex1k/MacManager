#ifndef MM_INPUT_H
#define MM_INPUT_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>
typedef struct {
    bool hid_inspection_available;
    bool has_hid;
    uint64_t sender_id;
    int64_t source_pid;
} MMScrollEventOrigin;
typedef enum {
    MMScrollDeviceUnknown = 0,
    MMScrollDeviceMouse = 1,
    MMScrollDeviceTrackpad = 2
} MMScrollDeviceKind;
MMScrollEventOrigin mm_scroll_event_origin(CGEventRef event);
// May access IORegistry; call on the device-lookup queue, never inside an event tap.
MMScrollDeviceKind mm_scroll_local_device_kind(uint64_t sender_id);
bool mm_scroll_bridge_available(void);
bool mm_scroll_reverse_event(CGEventRef event);
bool mm_scroll_reverse_axes(CGEventRef event, bool vertical, bool horizontal);
#endif
