#include <Cocoa/Cocoa.h>

#include <stdint.h>
#include <stdio.h>

#define internal        static
#define local_persist   static
#define global_variable static

typedef int8_t  i8;
typedef int16_t i16;
typedef int32_t i32;
typedef int64_t i64;
typedef i32     b32;

#define true  1
#define false 0

typedef uint8_t     u8;
typedef uint16_t    u16;
typedef uint32_t    u32;
typedef uint64_t    u64;

typedef float       f32;
typedef double      f64;

global_variable b32 GlobalRunning = true;

// clang-format off
@interface HandmadeApplicationDelegate : 
    NSObject<NSApplicationDelegate, NSWindowDelegate>
@end
// clang-format on
@implementation HandmadeApplicationDelegate

- (void)applicationDidFinishLaunching:(id)sender
{
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{

    return YES;
}

- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)frameSize
{

    NSRect WindowRect  = [window frame];
    NSRect ContentRect = [window contentRectForFrameRect:WindowRect];

    f32    WindowMinusContentWidth  = (WindowRect.size.width -
                                       ContentRect.size.width);
    f32    WindowMinusContentHeight = (WindowRect.size.height -
                                       ContentRect.size.height);

    f32    NewContentHeight = (9.0f *
                               (frameSize.width - WindowMinusContentWidth)) /
                              16.0f;

    frameSize.height        = NewContentHeight + WindowMinusContentHeight;

    return frameSize;
}

- (void)windowWillClose:(id)sender
{
    GlobalRunning = false;
}

@end

i32
main(i32 argc, const char *argv[])
{

    @autoreleasepool
    {
        NSString      *ApplicationName = @"Handmade Game";
        f32            WindowWidth     = 960.0f;
        f32            WindowHeight    = 540.0f;

        NSApplication *application     = [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        HandmadeApplicationDelegate *ApplicationDelegate;

        ApplicationDelegate = [[HandmadeApplicationDelegate alloc] init];
        [application setDelegate:ApplicationDelegate];

        [NSApp finishLaunching];

        NSRect ScreenRect   = [[NSScreen mainScreen] frame];

        NSRect InitialFrame = NSMakeRect(
            (ScreenRect.size.width - WindowWidth) * 0.5f,
            (ScreenRect.size.height - WindowHeight) * 0.5f, WindowWidth,
            WindowHeight);

        NSWindow *Window = [[NSWindow alloc]
            initWithContentRect:InitialFrame
                      styleMask:NSWindowStyleMaskTitled |
                                NSWindowStyleMaskClosable |
                                NSWindowStyleMaskMiniaturizable |
                                NSWindowStyleMaskResizable
                        backing:NSBackingStoreBuffered
                          defer:NO];

        [Window setBackgroundColor:NSColor.redColor];
        [Window setDelegate:ApplicationDelegate];

        NSView *ContentView = [Window contentView];
        [ContentView
            setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        [Window setMinSize:NSMakeSize(160, 90)];
        [Window setTitle:ApplicationName];
        [Window makeKeyAndOrderFront:nil];

        while(GlobalRunning)
        {
            NSEvent *Event;

            do
            {
                Event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                           untilDate:nil
                                              inMode:NSDefaultRunLoopMode
                                             dequeue:YES];

                [NSApp sendEvent:Event];

            } while(Event != nil);
        }

        printf("Handmade Game finished running\n");
    }
}