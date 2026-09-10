#ifndef MM_INPUT_H
#define MM_INPUT_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
bool mm_scroll_bridge_available(void);
bool mm_scroll_reverse_event(CGEventRef event);
#endif
