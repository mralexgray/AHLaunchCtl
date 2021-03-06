//
//  AHServiceManagement.m
//  AHLaunchCtl
//
//  Created by Eldon on 2/16/14.
//  Copyright (c) 2014 Eldon Ahrold. All rights reserved.
//

#import "AHServiceManagement.h"
#import "AHServiceManagement_Private.h"

#import "AHLaunchJob.h"
#import <ServiceManagement/ServiceManagement.h>

BOOL jobIsRunning(NSString *label, AHLaunchDomain domain) {
    NSDictionary *dict = AHJobCopyDictionary(domain, label);
    return dict ? YES : NO;
}

NSDictionary *AHJobCopyDictionary(AHLaunchDomain domain, NSString *label) {
    NSDictionary *dict;
    if (label && domain != 0) {
        dict = CFBridgingRelease(
            SMJobCopyDictionary((__bridge CFStringRef)(SMDomain(domain)),
                                (__bridge CFStringRef)(label)));
        return dict;
    } else {
        return nil;
    }
}

BOOL AHJobSubmit(AHLaunchDomain domain,
                 NSDictionary *dictionary,
                 AuthorizationRef authRef,
                 NSError *__autoreleasing *error) {
    CFErrorRef cfError;
    if (domain == 0) return NO;
    cfError = NULL;

    BOOL rc = SMJobSubmit((__bridge CFStringRef)(SMDomain(domain)),
                          (__bridge CFDictionaryRef)dictionary,
                          authRef,
                          &cfError);

    if (!rc) {
        NSError *err = CFBridgingRelease(cfError);
        if (error) *error = err;
    }

    return rc;
}

BOOL AHJobSubmitCreatingFile(AHLaunchDomain domain,
                             NSDictionary *dictionary,
                             AuthorizationRef authRef,
                             NSError *__autoreleasing *error) {
    BOOL success = NO;

    if ((success = AHJobSubmit(domain, dictionary, authRef, error))) {
        success =
            AHCreatePrivilegedLaunchdPlist(domain, dictionary, authRef, error);
    }
    return success;
}

BOOL AHJobRemove(AHLaunchDomain domain,
                 NSString *label,
                 AuthorizationRef authRef,
                 NSError *__autoreleasing *error) {
    CFErrorRef cfError;
    if (domain == 0) return NO;
    cfError = NULL;

    BOOL rc = SMJobRemove((__bridge CFStringRef)(SMDomain(domain)),
                          (__bridge CFStringRef)(label),
                          authRef,
                          YES,
                          &cfError);

    if (!rc) {
        NSError *err = CFBridgingRelease(cfError);
        if (error) *error = err;
    }
    return rc;
}

extern BOOL AHJobRemoveIncludingFile(AHLaunchDomain domain,
                                     NSString *label,
                                     AuthorizationRef authRef,
                                     NSError **error) {
    BOOL success = NO;

    if ((success = AHJobRemove(domain, label, authRef, error))) {
        success = AHRemovePrivilegedFile(
            domain, launchdJobFile(label, domain), authRef, error);
    }
    return success;
}

BOOL AHJobBless(AHLaunchDomain domain,
                NSString *label,
                AuthorizationRef authRef,
                NSError *__autoreleasing *error) {
    if (domain == 0) return NO;

    CFErrorRef cfError = NULL;
    BOOL rc = NO;

    if (jobIsRunning(label, domain)) {
        AHJobUnbless(domain, label, authRef, error);
    }

    rc = SMJobBless(kSMDomainSystemLaunchd,
                    (__bridge CFStringRef)(label),
                    authRef,
                    &cfError);
    if (!rc) {
        NSError *err = CFBridgingRelease(cfError);
        if (error) *error = err;
    }
    return rc;
}

BOOL AHJobUnbless(AHLaunchDomain domain,
                  NSString *label,
                  AuthorizationRef authRef,
                  NSError *__autoreleasing *error) {
    if (domain == 0) return NO;

    CFErrorRef cfError = NULL;
    BOOL success = NO;

    success = AHJobRemove(domain, label, authRef, error);

    // Remove the launchd plist
    NSString *const launchJobFile = launchdJobFile(label, domain);
    if(!AHRemovePrivilegedFile(domain, launchJobFile, authRef, error)){
        NSLog(@"There was a problem removing the launchd.plist of the helper tool.");
    }

    // Remove the helper tool binary
    NSString *const priviledgedToolBinary = [@"/Library/PrivilegedHelperTools/"
        stringByAppendingPathComponent:label];

    if(!AHRemovePrivilegedFile(domain, priviledgedToolBinary, authRef, error)){
        NSLog(@"There was a problem removing binary file of the helper tool.");
    }

    if (!success) {
        NSError *err = CFBridgingRelease(cfError);
        if (error) *error = err;
    }
    return success;
}

NSArray *AHCopyAllJobDictionaries(AHLaunchDomain domain) {
    return CFBridgingRelease(
        SMCopyAllJobDictionaries((__bridge CFStringRef)(SMDomain(domain))));
}

#pragma mark Private
BOOL AHCreatePrivilegedLaunchdPlist(AHLaunchDomain domain,
                                    NSDictionary *dictionary,
                                    AuthorizationRef authRef,
                                    NSError *__autoreleasing *error) {
    BOOL success = NO;

    AHLaunchJob *copyJob;
    AHLaunchJob *chownJob;

    // File path to for the launchd.plist
    NSString *filePath;

    // tmp file path the current under privileged user has access to
    NSString *tmpFilePath;

    NSString *label = dictionary[@"Label"];
    if (label && label.length) {
        filePath = launchdJobFile(label, domain);

        tmpFilePath =
            [@"/tmp" stringByAppendingPathComponent:
                         [[NSProcessInfo processInfo] globallyUniqueString]];

        if ([dictionary writeToFile:tmpFilePath atomically:YES]) {
            [[NSFileManager defaultManager] setAttributes:@{
                NSFilePosixPermissions : [NSNumber numberWithShort:0755]
            } ofItemAtPath:tmpFilePath error:nil];

            copyJob = [AHLaunchJob new];
            copyJob.Label = [@"com.eeaapps.ahlaunchctl.copy"
                stringByAppendingPathExtension:label];
            copyJob.ProgramArguments =
                @[ @"/bin/mv", @"-f", tmpFilePath, filePath ];
            copyJob.RunAtLoad = YES;
            copyJob.LaunchOnlyOnce = YES;

            if ((success = AHJobSubmit(kAHGlobalLaunchDaemon,
                                       copyJob.dictionary,
                                       authRef,
                                       error))) {
                sleep(0.1);

                // This should exit fast. If it's still alive unload it.
                if (jobIsRunning(copyJob.Label, kAHGlobalLaunchDaemon)) {
                    AHJobRemove(
                        kAHGlobalLaunchDaemon, copyJob.Label, authRef, nil);
                }

                chownJob = [AHLaunchJob new];
                chownJob.Label = [@"com.eeaapps.ahlaunchctl.chown"
                    stringByAppendingPathExtension:label];
                chownJob.ProgramArguments =
                    @[ @"/usr/sbin/chown", @"root:wheel", filePath ];
                chownJob.RunAtLoad = YES;
                chownJob.LaunchOnlyOnce = YES;

                success = AHJobSubmit(
                    kAHGlobalLaunchDaemon, chownJob.dictionary, authRef, error);
                // This should exit fast. If it's still alive unload it.
                if (jobIsRunning(chownJob.Label, kAHGlobalLaunchDaemon)) {
                    AHJobRemove(
                        kAHGlobalLaunchDaemon, chownJob.Label, authRef, nil);
                }
            }
        }
    }
    return success;
}

BOOL AHRemovePrivilegedFile(AHLaunchDomain domain,
                            NSString *filePath,
                            AuthorizationRef authRef,
                            NSError *__autoreleasing *error) {
    BOOL success = YES;
    NSFileManager *fm = [NSFileManager defaultManager];

    if ([fm fileExistsAtPath:filePath]) {
        NSString *const label = [@"com.eeaapps.ahlaunchctl.remove"
            stringByAppendingPathExtension:[filePath lastPathComponent]];

        AHLaunchJob *removeJob = [AHLaunchJob new];
        removeJob.Label = label;
        removeJob.ProgramArguments = @[ @"/bin/rm", filePath ];
        removeJob.RunAtLoad = YES;
        removeJob.LaunchOnlyOnce = YES;

        if ((success = AHJobSubmit(kAHGlobalLaunchDaemon,
                                   removeJob.dictionary,
                                   authRef,
                                   error))) {
            sleep(0.5);
        }

        // This should exit fast. If it's still alive unload it.
        if (jobIsRunning(removeJob.Label, kAHGlobalLaunchDaemon)) {
            AHJobRemove(kAHGlobalLaunchDaemon, label, authRef, nil);
        }
    }
    return success;
}

NSString *launchdJobFileDirectory(AHLaunchDomain domain) {
    NSString *type;
    switch (domain) {
        case kAHGlobalLaunchAgent:
            type = @"/Library/LaunchAgents/";
            break;
        case kAHGlobalLaunchDaemon:
            type = @"/Library/LaunchDaemons/";
            break;
        case kAHSystemLaunchAgent:
            type = @"/System/Library/LaunchAgents/";
            break;
        case kAHSystemLaunchDaemon:
            type = @"/System/Library/LaunchDaemons/";
            break;
        case kAHUserLaunchAgent:
        default:
            type = [@"~/Library/LaunchAgents/" stringByExpandingTildeInPath];
            break;
    }
    return type;
}

NSString *launchdJobFile(NSString *label, AHLaunchDomain domain) {
    NSString *file;
    if (domain == 0 || !label) return nil;
    file = [launchdJobFileDirectory(domain) stringByAppendingPathComponent:[label stringByAppendingPathExtension:@"plist"]];

    return file;
}

NSString *SMDomain(AHLaunchDomain domain) {
    if (domain > kAHGlobalLaunchAgent) {
        return (__bridge NSString *)kSMDomainSystemLaunchd;
    } else {
        return (__bridge NSString *)kSMDomainUserLaunchd;
    }
}