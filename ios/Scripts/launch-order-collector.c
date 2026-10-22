// Records which functions run during a cold launch, in order of first call.
// ios/Scripts/generate-launch-order-file.sh links this into an instrumented
// Release build. The Swift and C compilers insert a call to
// __sanitizer_cov_trace_pc_guard at the start of every function. The app code
// itself never includes this file.
//
// A timer thread writes the symbols to $TMPDIR/launch-order-symbols.txt, one
// per line with the leading underscore the linker expects in an order file.
// LAUNCH_ORDER_SECONDS (default 15) sets the delay after process start. The
// lookups take a while, so the thread writes a .tmp file and renames it when
// done. The file exists only when it is complete.

#include <dlfcn.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define MAX_CALLS (1u << 21)

static void *calls[MAX_CALLS];
static atomic_uint call_count;
static uint32_t next_guard;

// Every object file in the image runs this with the same section range, so the
// first call numbers the guards and later calls return early.
void __sanitizer_cov_trace_pc_guard_init(uint32_t *start, uint32_t *stop) {
  if (start == stop || *start != 0) return;
  for (uint32_t *guard = start; guard < stop; guard++) *guard = ++next_guard;
}

void __sanitizer_cov_trace_pc_guard(uint32_t *guard) {
  if (*guard == 0) return;
  *guard = 0;
  unsigned index = atomic_fetch_add(&call_count, 1);
  if (index < MAX_CALLS) calls[index] = __builtin_return_address(0);
}

static void *dump_after_delay(void *seconds) {
  sleep((unsigned)(uintptr_t)seconds);
  unsigned count = atomic_load(&call_count);
  if (count > MAX_CALLS) count = MAX_CALLS;

  const char *tmp = getenv("TMPDIR");
  char path[1024], partial[1040];
  snprintf(path, sizeof path, "%s/launch-order-symbols.txt", tmp ? tmp : "/tmp");
  snprintf(partial, sizeof partial, "%s.tmp", path);
  FILE *out = fopen(partial, "w");
  if (!out) return NULL;
  for (unsigned i = 0; i < count; i++) {
    Dl_info info;
    if (calls[i] && dladdr(calls[i], &info) && info.dli_sname) {
      fprintf(out, "_%s\n", info.dli_sname);
    }
  }
  fclose(out);
  rename(partial, path);
  return NULL;
}

__attribute__((constructor)) static void start_dump_timer(void) {
  const char *value = getenv("LAUNCH_ORDER_SECONDS");
  unsigned seconds = value ? (unsigned)atoi(value) : 15;
  pthread_t thread;
  pthread_create(&thread, NULL, dump_after_delay, (void *)(uintptr_t)seconds);
  pthread_detach(thread);
}
