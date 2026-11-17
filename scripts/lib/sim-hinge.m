// Sets or reads the hinge of a foldable iPhone simulator (iPhone Duo). It runs inside the
// simulator through `simctl spawn`, and scripts/sim-fold builds and runs it.
//
//   sim-hinge set <degrees>   0 is closed, 180 is open
//   sim-hinge read            prints the hinge angle in degrees
//
// simctl and Xcode have no command for the hinge. The HID event and the CoreMotion read follow
// agent-device's fold helper (github.com/callstack/agent-device, MIT), which found them.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <objc/message.h>

extern CFDataRef IOCFSerialize(CFTypeRef object, CFOptionFlags options);
extern CFTypeRef IOHIDEventCreateVendorDefinedEvent(CFAllocatorRef allocator, uint64_t timestamp,
    uint32_t usagePage, uint32_t usage, uint32_t version, const uint8_t *data, CFIndex length,
    uint32_t options);
extern CFTypeRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern void IOHIDEventSystemClientDispatchEvent(CFTypeRef client, CFTypeRef event);

static int setAngle(double degrees) {
  NSDictionary *payload = @{
    @"provider": @"com.apple.Virtualization.VirtualMachines",
    @"source": @"hinge-slider-control", @"type": @"range", @"value": @(degrees),
  };
  CFDataRef data = IOCFSerialize((__bridge CFTypeRef)payload, 1);
  CFTypeRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
  CFTypeRef event = data ? IOHIDEventCreateVendorDefinedEvent(kCFAllocatorDefault, mach_absolute_time(),
      0xff61, 0x5b, 0, CFDataGetBytePtr(data), CFDataGetLength(data), 0) : NULL;
  if (client && event) IOHIDEventSystemClientDispatchEvent(client, event);
  BOOL sent = client && event;
  if (event) CFRelease(event);
  if (client) CFRelease(client);
  if (data) CFRelease(data);
  if (!sent) fprintf(stderr, "Could not send the hinge event\n");
  return sent ? 0 : 1;
}

static int readAngle(void) {
  dlopen("/System/Library/Frameworks/CoreMotion.framework/CoreMotion", RTLD_NOW);
  Class managerClass = NSClassFromString(@"CMAngleManager");
  SEL start = @selector(startAngleUpdatesToQueue:handler:);
  if (![managerClass respondsToSelector:@selector(isAvailable)] ||
      !((BOOL (*)(id, SEL))objc_msgSend)(managerClass, @selector(isAvailable)) ||
      ![managerClass instancesRespondToSelector:start]) {
    fprintf(stderr, "This simulator has no hinge\n");
    return 3;
  }
  id manager = [managerClass new];
  NSOperationQueue *queue = [NSOperationQueue new];
  dispatch_semaphore_t sampled = dispatch_semaphore_create(0);
  __block float angle = NAN;
  void (^handler)(id) = ^(id sample) {
    if (![sample respondsToSelector:@selector(angleDegrees)] || !isnan(angle)) return;
    angle = ((float (*)(id, SEL))objc_msgSend)(sample, @selector(angleDegrees));
    dispatch_semaphore_signal(sampled);
  };
  ((void (*)(id, SEL, NSOperationQueue *, id))objc_msgSend)(manager, start, queue, handler);
  long timedOut = dispatch_semaphore_wait(sampled, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
  ((void (*)(id, SEL))objc_msgSend)(manager, @selector(stopAngleUpdates));
  [queue waitUntilAllOperationsAreFinished];
  if (timedOut) {
    fprintf(stderr, "The hinge reported no angle within 3 seconds\n");
    return 4;
  }
  printf("%.1f\n", angle);
  return 0;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc == 3 && strcmp(argv[1], "set") == 0) {
      double degrees = atof(argv[2]);
      if (degrees >= 0 && degrees <= 180) return setAngle(degrees);
    }
    if (argc == 2 && strcmp(argv[1], "read") == 0) return readAngle();
    fprintf(stderr, "usage: sim-hinge set <0-180> | read\n");
    return 64;
  }
}
