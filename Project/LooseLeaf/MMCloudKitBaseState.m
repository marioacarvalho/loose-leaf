//
//  MMCloudKitBaseState.m
//  LooseLeaf
//
//  Created by Adam Wulf on 8/25/14.
//  Copyright (c) 2014 Milestone Made, LLC. All rights reserved.
//

#import "MMCloudKitBaseState.h"
#import "MMReachabilityManager.h"
#import "MMCloudKitManager.h"
#import "MMCloudKitOfflineState.h"
#import "MMCloudKitAccountMissingState.h"
#import "MMCloudKitDeclinedPermissionState.h"
#import "MMCloudKitFetchingAccountInfoState.h"
#import "MMCloudKitWaitingForLoginState.h"
#import <SimpleCloudKitManager/SPRSimpleCloudKitManager.h>
#import "Constants.h"

//
// this is the first state of the state machine,
// and attempts to login to CloudKit. if login fails,
// then it will transition to an ErrorState for the
// appropriate reason
@implementation MMCloudKitBaseState {
    BOOL isCheckingStatus;
    NSArray* cachedFriendListIfAny;
}


- (id)initWithCachedFriendList:(NSArray*)_friendList {
    if (self = [super init]) {
        cachedFriendListIfAny = _friendList;
    }
    return self;
}


- (NSArray*)friendList {
    return cachedFriendListIfAny;
}


+ (NSString*)statusPlistPath {
    return [[MMCloudKitManager cloudKitFilesPath] stringByAppendingPathComponent:@"status.plist"];
}

+ (void)clearCache {
    [[NSFileManager defaultManager] removeItemAtPath:[MMCloudKitBaseState statusPlistPath] error:nil];
}

- (void)runState {
    if ([MMReachabilityManager sharedManager].currentReachabilityStatus == NotReachable) {
        // we can't connect to cloudkit, so move to an error state
        [[MMCloudKitManager sharedManager] changeToState:[[MMCloudKitOfflineState alloc] init]];
    } else {
        @synchronized(self) {
            if (isCheckingStatus) {
                return;
            }
            isCheckingStatus = YES;
        }
        // i should cache the results, and changing states based on errors:
        // SPRSimpleCloudMessengerErroriCloudAccount, or
        // SPRSimpleCloudMessengerErrorMissingDiscoveryPermissions
        // should reset my cache and restart this state.

        NSDictionary* status = [NSDictionary dictionaryWithContentsOfFile:[MMCloudKitBaseState statusPlistPath]];
        if (status) {
            //            DebugLog(@"using cached account and permission status %@", status);
            SCKMAccountStatus accountStatus = (SCKMAccountStatus)[[status objectForKey:@"accountStatus"] integerValue];
            SCKMApplicationPermissionStatus permissionStatus = (SCKMApplicationPermissionStatus)[[status objectForKey:@"permissionStatus"] integerValue];
            [self switchStateBasedOnAccountStatus:accountStatus andPermissionStatus:permissionStatus];
            @synchronized(self) {
                isCheckingStatus = NO;
            }
            return;
        }

        [[SPRSimpleCloudKitManager sharedManager] silentlyVerifyiCloudAccountStatusOnComplete:^(SCKMAccountStatus accountStatus,
                                                                                                SCKMApplicationPermissionStatus permissionStatus,
                                                                                                NSError* error) {
            @synchronized(self) {
                isCheckingStatus = NO;
            }
            if ([MMCloudKitManager sharedManager].currentState != self) {
                // bail early. the network probably went offline
                // while we were waiting for a reply. if we're not current,
                // then we shouldn't process / change state.
                return;
            }
            if (error) {
                [[MMCloudKitManager sharedManager] changeToStateBasedOnError:error];
            } else {
                [self switchStateBasedOnAccountStatus:accountStatus andPermissionStatus:permissionStatus];
            }
        }];
    }
}

- (void)switchStateBasedOnAccountStatus:(SCKMAccountStatus)accountStatus andPermissionStatus:(SCKMApplicationPermissionStatus)permissionStatus {
    [MMCloudKitBaseState clearCache];
    switch (accountStatus) {
        case SCKMAccountStatusCouldNotDetermine:
            // accountStatus is unknown, so reload it
            [[MMCloudKitManager sharedManager] retryStateAfterDelay:3];
            break;
        case SCKMAccountStatusNoAccount:
        case SCKMAccountStatusRestricted:
            // notify that cloudKit is entirely unavailable
            [[MMCloudKitManager sharedManager] changeToState:[[MMCloudKitAccountMissingState alloc] init]];
            break;
        case SCKMAccountStatusAvailable:
            switch (permissionStatus) {
                case SCKMApplicationPermissionStatusCouldNotComplete:
                    [[MMCloudKitManager sharedManager] retryStateAfterDelay:3];
                    break;
                case SCKMApplicationPermissionStatusDenied:
                    // account exists for iCloud, but the user has
                    // denied us permission to use it
                    [[MMCloudKitManager sharedManager] changeToState:[[MMCloudKitDeclinedPermissionState alloc] init]];
                    break;
                case SCKMApplicationPermissionStatusInitialState:
                    // unknown permission
                    // waiting for manual login
                    [[MMCloudKitManager sharedManager] changeToState:[[MMCloudKitWaitingForLoginState alloc] initWithAccountStatus:accountStatus]];
                    break;
                case SCKMApplicationPermissionStatusGranted:
                    // icloud is available for this user, so we need to
                    // fetch their account info if we don't already have it.
                    {
                        NSDictionary* status = @{ @"accountStatus": @(accountStatus),
                                                  @"permissionStatus": @(permissionStatus) };
                        [status writeToFile:[MMCloudKitBaseState statusPlistPath] atomically:YES];
                        [[MMCloudKitManager sharedManager] changeToState:[[MMCloudKitFetchingAccountInfoState alloc] initWithCachedFriendList:self.friendList]];
                    }
                    break;
            }
            break;
    }
}

- (void)killState {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (BOOL)isLoggedInAndReadyForAnything {
    return NO;
}

#pragma mark - Notifications

- (void)cloudKitInfoDidChange {
    DebugLog(@"%@ cloudKitInfoDidChange", NSStringFromClass([self class]));
    @synchronized(self) {
        [self runState];
    }
}

- (void)reachabilityDidChange {
    DebugLog(@"%@ reachabilityDidChange", NSStringFromClass([self class]));
    @synchronized(self) {
        [self runState];
    }
}

- (void)cloudKitDidRecievePush {
    // noop
}

- (void)cloudKitDidCheckForNotifications {
    // noop
}

@end
