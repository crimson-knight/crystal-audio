// trace_helper.c — C-level trace logging for Crystal iOS bridge
// Uses Apple's os_log so messages appear in `xcrun simctl spawn booted log stream`
#include <os/log.h>

static os_log_t crystal_log = NULL;

void crystal_trace(const char *msg) {
    if (!crystal_log) {
        crystal_log = os_log_create("com.crimsonknight.crystal", "trace");
    }
    os_log_error(crystal_log, "CRYSTAL_TRACE: %{public}s", msg);
}
