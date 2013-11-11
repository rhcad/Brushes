//
//  WDAppDelegate.m
//  Brushes
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
//  Copyright (c) 2010-2013 Steve Sprang
//

#import "WDAppDelegate.h"
#import "WDBrowserController.h"
#import "WDColor.h"
#import "WDCanvasController.h"
#import "WDPaintingManager.h"
#import "WDPaintingSizeController.h"
#import "WDDocument.h"
#import "WDStylusManager.h"

@implementation WDAppDelegate

@synthesize window;
@synthesize navigationController;
@synthesize browserController;

#pragma mark -
#pragma mark Application lifecycle

- (void) setupDefaults
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *defaultPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Defaults.plist"];
    [defaults registerDefaults:[NSDictionary dictionaryWithContentsOfFile:defaultPath]];
    
    [WDPaintingSizeController registerDefaults];
}

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
    [self setupDefaults];
    
    browserController = [[WDBrowserController alloc] initWithNibName:nil bundle:nil];
    navigationController = [[UINavigationController alloc] initWithRootViewController:browserController];
    
    // set a good background color for the superview so that orientation changes don't look hideous
    window.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];
    
    window.rootViewController = navigationController;
    [window makeKeyAndVisible];
    
    // create the shared stylus manager so it can set things up for the pressure pens
    [WDStylusManager sharedStylusManager];
}

void uncaughtExceptionHandler(NSException *exception) {
#if WD_DEBUG
    NSLog(@"CRASH: %@", exception);
    NSLog(@"Stack Trace: %@", [exception callStackSymbols]);
#endif
}

- (void) startEditingDocument:(id)name
{
    WDDocument *document = [[WDPaintingManager sharedInstance] paintingWithName:name];
    [browserController openDocument:document editing:NO];
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    NSError *error = nil;
    NSString *name = [[WDPaintingManager sharedInstance] installPaintingFromURL:url error:&error];

    if (!name) {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Broken Painting", @"Broken Painting")
                                                            message:NSLocalizedString(@"Brushes could not open the requested painting.", @"Brushes could not open the requested painting.")
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
        [alertView show];
    } else if (navigationController.topViewController == browserController) {
        [browserController dismissViewControllerAnimated:NO completion:nil];
        [self performSelector:@selector(startEditingDocument:) withObject:name afterDelay:0];
    } else {
        WDCanvasController *controller = (WDCanvasController *) navigationController.topViewController;
        WDDocument *doc = [[WDPaintingManager sharedInstance] paintingWithName:name];
        [doc openWithCompletionHandler:^(BOOL success) {
            if (success) {
                controller.document = doc;
            } else {
                [browserController showOpenFailure:doc];
            }
        }];
    }
    
    return (name ? YES : NO);
}

@end
