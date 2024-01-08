//
//  main.m
//  PosePluginNativeTesterObjC
//
//  Created by Mikko Karvonen on 14.9.2022.
//  Copyright (C) 2024 Immersal - Part of Hexagon. All Rights Reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
