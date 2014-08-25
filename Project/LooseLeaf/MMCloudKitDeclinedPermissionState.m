//
//  MMCloudKitDeclinedPermissionState.m
//  LooseLeaf
//
//  Created by Adam Wulf on 8/25/14.
//  Copyright (c) 2014 Milestone Made, LLC. All rights reserved.
//

#import "MMCloudKitDeclinedPermissionState.h"
#import "MMReachabilityManager.h"
#import "MMCloudKitOfflineState.h"
#import "MMCloudKitManager.h"

@implementation MMCloudKitDeclinedPermissionState

-(void) runState{
    NSLog(@"Running state %@", NSStringFromClass([self class]));
    
    if([MMReachabilityManager sharedManager].currentReachabilityStatus == NotReachable){
        // we can't connect to cloudkit, so move to an error state
        [[MMCloudKitManager sharedManager] changeToState:[[MMCloudKitOfflineState alloc] init]];
    }else{
        
        // noop
    }
}

@end