//
//  ViewController.m
//  IMSign
//
//  Created by iMokhles on 16/05/16.
//  Copyright © 2016 iMokhles. All rights reserved.
//

#import "ViewController.h"
#import "DragView.h"
#import <sys/sysctl.h>
#include <spawn.h>
#import "GCDTask.h"
#import "DJProgressHUD.h"
#import "IMSProfilesManager.h"

@interface ViewController () {
    
    NSArray *certsArray;
    NSArray *profilesArray;
    
    NSString *appName;
    NSString *appID;
    NSString *appIPAFile;
    NSString *appProfile;
    NSString *certificateName;
    NSString *additionalPath;
    
    BOOL isDylib;
    BOOL isTweak;
    BOOL isDylibsDir;
    BOOL isSupportIPAD;
    
    BOOL isAppAlreadyTweaked;
}
@property (strong) IBOutlet NSTextField *loadingLabel;
@property (strong) IBOutlet NSTableView *profilesTableView;
@property (strong) IBOutlet NSTextField *appNameField;
@property (strong) IBOutlet NSTextField *appIDField;
@property (strong) IBOutlet NSTextField *appProfileField;
@property (strong) IBOutlet NSTextField *ipaFileField;
@property (strong) IBOutlet NSTextField *additionalField;
@property (strong) IBOutlet DragView *dragView;
@property (strong) IBOutlet NSTableView *mainTableView;
@property (strong) IBOutlet NSButton *tweakButton;
@property (strong) IBOutlet NSButton *dylibButton;
@property (strong) IBOutlet NSProgressIndicator *progressIndicator;
@property (strong) IBOutlet NSButton *ipadButton;
@end


@implementation ViewController

- (void)viewWillAppear {
    [super viewWillAppear];
    
    isDylib = NO;
    isTweak = NO;
    isSupportIPAD = NO;
    
    _additionalField.enabled = NO;
    _dylibButton.enabled = NO;
    _ipadButton.enabled = YES;
    
    _ipadButton.state = NSOffState;
    _tweakButton.state = NSOffState;
    _dylibButton.state = NSOffState;
    self.loadingLabel.stringValue = @"";
    
    certsArray = [self getCertifications];
    profilesArray = [self getProfiles];
    if (certsArray.count > 0) {
        [_mainTableView reloadData];
    }
    if (profilesArray.count > 0) {
        [_profilesTableView reloadData];
    }
    
    [self cleanAppMainPath];
    [self excuteCommandWithLaunchPath:@"/bin/cp" andArguments:@[[self insertDylibPathInBundle], [self insertDylibPath]] andCompleteBlock:^(BOOL exited) {
        if (exited) {
            // copied well
        }
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

#pragma mark - DragView
- (void)draggedFileAtPath:(NSURL *)url {
    if ([url.path.pathExtension isEqualToString:@"ipa"]) {
        appIPAFile = url.path;
        _ipaFileField.stringValue = url.path;
    } else if ([url.path.pathExtension isEqualToString:@"dylib"]) {
        isDylibsDir = NO;
        additionalPath = url.path;
        _additionalField.stringValue = url.path;
    } else if ([url.path.pathExtension isEqualToString:@"mobileprovision"]) {
        appProfile = url.path;
        _appProfileField.stringValue = url.path;
        [self configureAppInfoFieldsFromProfile];
    } else {
        NSNumber *isDirectory;
        BOOL success = [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (success && [isDirectory boolValue]) {
            isDylibsDir = YES;
            additionalPath = url.path;
            _additionalField.stringValue = url.path;
        }
    }
}

- (BOOL)checkFields {
    if (isTweak) {
        if (_appNameField.stringValue.length == 0 || _appIDField.stringValue.length == 0 || _appProfileField.stringValue.length == 0 || _ipaFileField.stringValue.length == 0 || _additionalField.stringValue.length == 0 || certificateName.length == 0) {
            
            [self showAlertWithMessage:@"Your fields isn't complete :("];
            return NO;
        }
    } else {
        if (_appNameField.stringValue.length == 0 || _appIDField.stringValue.length == 0 || _appProfileField.stringValue.length == 0 || _ipaFileField.stringValue.length == 0 || certificateName.length == 0) {
            
            [self showAlertWithMessage:@"Your fields isn't complete :("];
            return NO;
        }
    }
    return YES;
}

- (void)startProcesses {
    self.loadingLabel.stringValue = @"Preparing....";
    [self updateProgress:5];
    if ([self checkFields] == NO) {
        return;
    }
    
    [self excuteCommandWithLaunchPath:@"/usr/bin/unzip" andArguments:@[@"-oqq", _ipaFileField.stringValue, @"-d", [self extractedPath]] andCompleteBlock:^(BOOL exited) {
        if (exited) {
            [self deleteFileAtPath:[self appCodeSignaturePath]];
            [self checkIfTheAppAlreadyTweakedWithBlock:^(BOOL isTweaked, NSArray *allDylibs) {
                if (isTweaked && allDylibs.count > 0) {
//                    if (isTweak) {
//                        [self startAlreadyTweakedProcess];
//                    } else {
//                        [self startNotTweakedProcess];
//                    }
                    [self startAlreadyTweakedProcess];
                } else if (!isTweaked && allDylibs.count == 0) {
                    [self startNotTweakedProcess];
                }
            }];
        }
    }];
}

/************
 
 ********
 START PROCESS FOR TWEAKED APP
 ********
 
 ************/
#pragma mark - App Tweaked Already
- (void)startAlreadyTweakedProcess {
    isAppAlreadyTweaked = YES;
    if (isTweak) {
        [self showAlertWithMessage:@"We don't support tweaking already tweaked app ( for now )"];
    } else {
        [self startJustResignProcess];
    }
    
}

/************
 
 ********
 START PROCESS FOR NO TWEAKED APP
 ********
 
************/
#pragma mark - App Not Tweaked
- (void)startNotTweakedProcess {
    isAppAlreadyTweaked = NO;
    if (isTweak) {
        [self startTweakProcess];
    } else {
        [self startJustResignProcess];
    }
}

#pragma mark - tweak not tweaked app
- (void)startTweakProcess {
    self.loadingLabel.stringValue = @"Preparing....";
    [self updateProgress:8];
    if (isDylib) {
        if (!isDylibsDir) {
            [self tweakAppWithOneDylib];
        }
    } else {
        if (isDylibsDir) {
            [self tweakAppWithTweakFolder];
        }
    }
}

- (void)tweakAppWithOneDylib {
    [self updateProgress:10];
    [self excuteCommandWithLaunchPath:@"/bin/cp" andArguments:@[[NSString stringWithFormat:@"%@", _additionalField.stringValue], [NSString stringWithFormat:@"%@/", [self libsPath]]] andCompleteBlock:^(BOOL exited) {
        if (exited) {
            [self updateProgress:12];
            [self excuteCommandWithLaunchPath:@"/bin/cp" andArguments:@[@"-rf", [NSString stringWithFormat:@"%@/", [self libsPath]], [NSString stringWithFormat:@"%@", [self extractedAppBundlePath]]] andCompleteBlock:^(BOOL exited) {
                if (exited) {
                    [self updateProgress:17];
                    NSString *appBinary = [[self extractedAppBundlePath] stringByAppendingPathComponent:[self appInfoPlistDictionary][@"CFBundleExecutable"]];
                    if (![self isFileExecutable:appBinary]) {
                        [self excuteCommandWithLaunchPath:@"/bin/chmod" andArguments:@[@"+x", appBinary] andCompleteBlock:^(BOOL exited) {
                            if (exited) {
                                [self updateProgress:22];
                                if (isSupportIPAD) {
                                    [self configureAppForIPADifEnabled];
                                } else {
                                    [self configureAppInfoPlistFile];
                                }
                            }
                        }];
                    } else {
                        [self updateProgress:22];
                        if (isSupportIPAD) {
                            [self configureAppForIPADifEnabled];
                        } else {
                            [self configureAppInfoPlistFile];
                        }
                    }
                }
            }];
        }
    }];
}

- (void)tweakAppWithTweakFolder {
    [self updateProgress:10];
    [self excuteCommandWithLaunchPath:@"/bin/cp" andArguments:@[@"-rf", [NSString stringWithFormat:@"%@/", _additionalField.stringValue], [NSString stringWithFormat:@"%@/", [self libsPath]]] andCompleteBlock:^(BOOL exited) {
        if (exited) {
            [self updateProgress:12];
            [self excuteCommandWithLaunchPath:@"/bin/cp" andArguments:@[@"-rf", [NSString stringWithFormat:@"%@/", [self libsPath]], [NSString stringWithFormat:@"%@", [self extractedAppBundlePath]]] andCompleteBlock:^(BOOL exited) {
                if (exited) {
                    [self updateProgress:17];
                    NSString *appBinary = [[self extractedAppBundlePath] stringByAppendingPathComponent:[self appInfoPlistDictionary][@"CFBundleExecutable"]];
                    if (![self isFileExecutable:appBinary]) {
                        [self excuteCommandWithLaunchPath:@"/bin/chmod" andArguments:@[@"+x", appBinary] andCompleteBlock:^(BOOL exited) {
                            if (exited) {
                                [self updateProgress:22];
                                if (isSupportIPAD) {
                                    [self configureAppForIPADifEnabled];
                                } else {
                                    [self configureAppInfoPlistFile];
                                }
                                
                            }
                        }];
                    } else {
                        [self updateProgress:22];
                        if (isSupportIPAD) {
                            [self configureAppForIPADifEnabled];
                        } else {
                            [self configureAppInfoPlistFile];
                        }
                    }
                }
            }];
        }
    }];
}

- (void)configureAppInfoPlistFile {
    [self updateProgress:33];
    if (!isAppAlreadyTweaked) {
        [self excuteCommandWithLaunchPath:@"/usr/libexec/PlistBuddy" andArguments:@[@"-c", [NSString stringWithFormat:@"Set :CFBundleDisplayName %@", _appNameField.stringValue], [[self extractedAppBundlePath] stringByAppendingPathComponent:@"Info.plist"]] andCompleteBlock:^(BOOL exited) {
            if (exited) {
                [self excuteCommandWithLaunchPath:@"/usr/libexec/PlistBuddy" andArguments:@[@"-c", [NSString stringWithFormat:@"Set :CFBundleIdentifier %@", _appIDField.stringValue], [[self extractedAppBundlePath] stringByAppendingPathComponent:@"Info.plist"]] andCompleteBlock:^(BOOL exited) {
                    if (exited) {
                        if (isTweak) {
                            [self checkTweakAndLoadThemCorrectly];
                        } else {
                            [self startEntitlementsProcess];
                        }
                        
                    }
                }];
            }
        }];
    } else {
        [self excuteCommandWithLaunchPath:@"/usr/libexec/PlistBuddy" andArguments:@[@"-c", [NSString stringWithFormat:@"Set :CFBundleDisplayName %@", _appNameField.stringValue], [[self extractedAppBundlePath] stringByAppendingPathComponent:@"Info.plist"]] andCompleteBlock:^(BOOL exited) {
            if (exited) {
                [self excuteCommandWithLaunchPath:@"/usr/libexec/PlistBuddy" andArguments:@[@"-c", [NSString stringWithFormat:@"Set :CFBundleIdentifier %@", _appIDField.stringValue], [[self extractedAppBundlePath] stringByAppendingPathComponent:@"Info.plist"]] andCompleteBlock:^(BOOL exited) {
                    if (exited) {
                        if (isTweak) {
                            [self checkTweakAndLoadThemCorrectly];
                        } else {
                            [self startEntitlementsProcess];
                        }
                        
                    }
                }];
            }
        }];
    }
}

- (void)configureAppForIPADifEnabled {
    [self updateProgress:27];
    NSString *appPackageID = [self appInfoPlistDictionary][@"CFBundleIdentifier"];
    if ([appPackageID isEqualToString:@"net.whatsapp.WhatsApp"]) {
        [self excuteCommandWithLaunchPath:@"/usr/libexec/PlistBuddy" andArguments:@[@"-c", [NSString stringWithFormat:@"Delete :UIRequiredDeviceCapabilities"], [[self extractedAppBundlePath] stringByAppendingPathComponent:@"Info.plist"]] andCompleteBlock:^(BOOL exited) {
            if (exited) {
                [self updateProgress:30];
                [self excuteCommandWithLaunchPath:@"/usr/libexec/PlistBuddy" andArguments:@[@"-c", [NSString stringWithFormat:@"Add ::UIDeviceFamily:1 integer 2"], [[self extractedAppBundlePath] stringByAppendingPathComponent:@"Info.plist"]] andCompleteBlock:^(BOOL exited) {
                    if (exited) {
                        [self configureAppInfoPlistFile];
                    }
                }];
            }
        }];
    } else {
        [self updateProgress:30];
        [self excuteCommandWithLaunchPath:@"/usr/libexec/PlistBuddy" andArguments:@[@"-c", [NSString stringWithFormat:@"Add ::UIDeviceFamily:1 integer 2"], [[self extractedAppBundlePath] stringByAppendingPathComponent:@"Info.plist"]] andCompleteBlock:^(BOOL exited) {
            if (exited) {
                [self configureAppInfoPlistFile];
            }
        }];
    }
}

- (void)checkTweakAndLoadThemCorrectly {
    [self updateProgress:37];
    if (isDylib) {
        if (!isDylibsDir) {
            [self loadOnlyOneTweak];
        }
    } else {
        if (isDylibsDir) {
            [self loadSpecificTweakFile];
        }
    }
}

- (void)loadOnlyOneTweak {
    self.loadingLabel.stringValue = @"Loading Dylibs....";
    NSString *appBinary = [[self extractedAppBundlePath] stringByAppendingPathComponent:[self appInfoPlistDictionary][@"CFBundleExecutable"]];
    NSString *dylibPath = _additionalField.stringValue;
    NSString *dylibName = dylibPath.lastPathComponent;
    NSString *exe_path = [NSString stringWithFormat:@"@executable_path/%@", dylibName];
    [self excuteCommandWithLaunchPath:[self insertDylibPath] andArguments:@[@"--all-yes", @"--inplace", @"--overwrite", exe_path, appBinary] andCompleteBlock:^(BOOL exited) {
        if (exited) {
            [self updateProgress:40];
            double delayInSeconds = 1.5;
            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
            dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                // start entitlemens process
                [self startEntitlementsProcess];
            });
        }
    }];
    
}

- (void)loadSpecificTweakFile {
    self.loadingLabel.stringValue = @"Loading Dylibs....";
    NSString *appBinary = [[self extractedAppBundlePath] stringByAppendingPathComponent:[self appInfoPlistDictionary][@"CFBundleExecutable"]];
    NSError *error = nil;
    NSArray *tweaksFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_additionalField.stringValue error:&error];
    NSMutableArray *dylibsArray = [[NSMutableArray alloc] init];
    if (error == nil) {
        for (NSString *file in tweaksFiles) {
            if ([file.pathExtension containsString:@"dylib"] || [file.pathExtension containsString:@"Dylib"]) {
                [dylibsArray addObject:file];
            }
        }
        if (dylibsArray.count > 1) {
            if ([dylibsArray containsObject:@"pptweak.dylib"]) {
                NSString *exe_path = [NSString stringWithFormat:@"@executable_path/pptweak.dylib"];
                [self excuteCommandWithLaunchPath:[self insertDylibPath] andArguments:@[@"--all-yes", @"--inplace", @"--overwrite", exe_path, appBinary] andCompleteBlock:^(BOOL exited) {
                    if (exited) {
                        [self updateProgress:40];
                        double delayInSeconds = 1.5;
                        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
                        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                            // start entitlemens process
                            [self startEntitlementsProcess];
                        });
                    }
                }];
            } else if ([dylibsArray containsObject:@"WindInjector.dylib"]) {
                NSString *exe_path = [NSString stringWithFormat:@"@executable_path/WindInjector.dylib"];
                [self excuteCommandWithLaunchPath:[self insertDylibPath] andArguments:@[@"--all-yes", @"--inplace", @"--overwrite", exe_path, appBinary] andCompleteBlock:^(BOOL exited) {
                    if (exited) {
                        [self updateProgress:40];
                        double delayInSeconds = 1.5;
                        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
                        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                            // start entitlemens process
                            [self startEntitlementsProcess];
                        });
                    }
                }];
            }
        } else if (dylibsArray.count == 1) {
            NSString *exe_path = [NSString stringWithFormat:@"@executable_path/%@", [dylibsArray objectAtIndex:0]];
            [self excuteCommandWithLaunchPath:[self insertDylibPath] andArguments:@[@"--all-yes", @"--inplace", @"--overwrite", exe_path, appBinary] andCompleteBlock:^(BOOL exited) {
                if (exited) {
                    [self updateProgress:40];
                    double delayInSeconds = 1.5;
                    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
                    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                        // start entitlemens process
                        [self startEntitlementsProcess];
                    });
                }
            }];
        }
    }
}

#pragma mark - resign not tweaked app
- (void)startJustResignProcess {
    self.loadingLabel.stringValue = @"Preparing....";
    [self updateProgress:8];
    if (!isTweak) {
        if (isSupportIPAD) {
            [self configureAppForIPADifEnabled];
        } else {
            [self configureAppInfoPlistFile];
        }
    }
}


#pragma mark - General methods

- (void)configureAppInfoFieldsFromProfile {
    
    NSDictionary *profileInfo = [IMSProfilesManager getMobileProvisionbyPath:_appProfileField.stringValue];
    NSDictionary *entitlementsDict = profileInfo[@"Entitlements"];
    
    NSString *appIDString = [entitlementsDict objectForKey:@"application-identifier"];
    NSString *teamID = [entitlementsDict objectForKey:@"com.apple.developer.team-identifier"];
    
    NSArray *appIDArray = [appIDString componentsSeparatedByString:[NSString stringWithFormat:@"%@.", teamID]];
    _appNameField.stringValue = [profileInfo objectForKey:@"AppIDName"];
    _appIDField.stringValue = [appIDArray objectAtIndex:1];
    
}

- (void)startEntitlementsProcess {
    self.loadingLabel.stringValue = @"Saving Entitlements....";
    [self updateProgress:43];
    [self excuteCommandWithLaunchPath:@"/usr/bin/security" andArguments:@[@"cms",@"-D",@"-i", _appProfileField.stringValue, @"-o", [self entitlementsTempPlist]] andCompleteBlock:^(BOOL exited) {
        if (exited) {
            double delayInSeconds = 2.0;
            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
            dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                NSString *entitlementsCommand = [NSString stringWithFormat:@"/usr/libexec/PlistBuddy -c \"Print Entitlements\" \"%@\" -x > \"%@\"", [self entitlementsTempPlist], [self appEntitlementsFile]];
                system([entitlementsCommand UTF8String]);
                [self updateProgress:47];
                // start siging all dylibs process
                [self startSignAllDylibProcess];
                
            });
        }
    }];
}

- (void)startSignAllDylibProcess {
    self.loadingLabel.stringValue = @"Sign All Dylibs....";
    [self updateProgress:50];
    [self checkIfTheAppAlreadyTweakedWithBlock:^(BOOL isTweaked, NSArray *allDylibs) {
        if (isTweaked && allDylibs.count > 0) {
            for (NSUInteger index = 0; index < [allDylibs count] ; ++index) {
                if (index == [allDylibs count]-1) {
                    [self updateProgress:53];
                    // sign all plugins
                    double delayInSeconds = 1.5;
                    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
                    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                        // exited
                        [self signAllAppPlugins];
                    });
                }
                NSString *dylibFullPath = [[self extractedAppBundlePath] stringByAppendingPathComponent:[allDylibs objectAtIndex:index]];
                [self excuteCommandWithLaunchPath:@"/usr/bin/codesign" andArguments:@[@"-fs", certificateName, dylibFullPath] andCompleteBlock:^(BOOL exited) {
                    
                }];
                
            }
        } else if (!isTweaked && allDylibs.count == 0) {
            [self updateProgress:53];
            // sign all plugins
            double delayInSeconds = 1.5;
            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
            dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                // exited
                [self signAllAppPlugins];
            });
            
        }
    }];
}

- (void)signAllAppPlugins {
    self.loadingLabel.stringValue = @"Remove All Plugins....";
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self appPluginPath]]) {
        [self updateProgress:57];
        // remove it for now
        [self deleteFileAtPath:[self appPluginPath]];
        double delayInSeconds = 1.5;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            // exited
            [self signAllAppFrameworks];
        });
    } else {
        [self updateProgress:57];
        double delayInSeconds = 1.5;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            // exited
            [self signAllAppFrameworks];
        });
        
    }
}

- (void)signAllAppFrameworks {
    self.loadingLabel.stringValue = @"Sign All Frameworks....";
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self appFrameworksPath]]) {
        NSError *error = nil;
        NSArray *frameworksContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self appFrameworksPath] error:&error];
        for (NSUInteger index = 0; index < [frameworksContents count] ; ++index) {
            if (index == [frameworksContents count]-1) {
                [self updateProgress:60];
                // sign all plugins
                double delayInSeconds = 1.5;
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
                dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                    // exited
                    [self signTheMainAppNow];
                });
            }
            NSString *frameworkFullPath = [[self appFrameworksPath] stringByAppendingPathComponent:[frameworksContents objectAtIndex:index]];
            [self excuteCommandWithLaunchPath:@"/usr/bin/codesign" andArguments:@[@"-fs", certificateName, frameworkFullPath] andCompleteBlock:^(BOOL exited) {
                
            }];
        }
    } else {
        [self updateProgress:60];
        // sign all plugins
        double delayInSeconds = 1.5;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            // exited
            [self signTheMainAppNow];
        });
        
    }
}

- (void)signTheMainAppNow {
    if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/embedded.mobileprovision", [self extractedAppBundlePath]]]) {
        [self deleteFileAtPath:[NSString stringWithFormat:@"%@/embedded.mobileprovision", [self extractedAppBundlePath]]];
    }
    NSString *appBinary = [[self extractedAppBundlePath] stringByAppendingPathComponent:[self appInfoPlistDictionary][@"CFBundleExecutable"]];
    [self excuteCommandWithLaunchPath:@"/bin/cp" andArguments:@[[NSString stringWithFormat:@"%@", _appProfileField.stringValue], [NSString stringWithFormat:@"%@/embedded.mobileprovision", [self extractedAppBundlePath]]] andCompleteBlock:^(BOOL exited) {
        if (exited) {
            [self excuteCommandWithLaunchPath:@"/usr/bin/codesign" andArguments:@[@"-fs", certificateName, @"--entitlements", [self appEntitlementsFile], @"--timestamp=none", appBinary] andCompleteBlock:^(BOOL exited) {
                if (exited) {
                    // create ipa
                    [self updateProgress:70];
                    [self makeIPAFile];
                }
            }];
        }
    }];
}

- (void)makeIPAFile{
    self.loadingLabel.stringValue = @"Sign Main Bundle....";
    [self updateProgress:80];
    double delayInSeconds = 1.5;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        // exited
        [self updateProgress:100];
        self.loadingLabel.stringValue = @"Zip Main Bundle....";
        NSString *command = [NSString stringWithFormat:@"cd %@; zip -r %@ -r Payload/", [self extractedPath], [NSString stringWithFormat:@"~/Desktop/%@.ipa",[self appInfoPlistDictionary][@"CFBundleDisplayName"]]];
        system([command UTF8String]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            self.loadingLabel.stringValue = @"Cleaning Files....";
            [DJProgressHUD dismiss];
            [self cleanAppMainPath];
            [self excuteCommandWithLaunchPath:@"/bin/cp" andArguments:@[[self insertDylibPathInBundle], [self insertDylibPath]] andCompleteBlock:^(BOOL exited) {
                if (exited) {
                    // copied well
                    self.loadingLabel.stringValue = @"Done Saved....";
                }
            }];
        });
        
    });
}

- (IBAction)signButtonTapped:(NSButton *)sender {
    [self startProcesses];
}
#pragma mark - NSTableViewDelegate/DataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == _mainTableView) {
        return certsArray.count;
    }
    return profilesArray.count;
}

- (nullable id)tableView:(NSTableView *)tableView objectValueForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == _mainTableView) {
        return certsArray[row];
    }
    NSString *profilePath = profilesArray[row];
    NSDictionary *profile = [IMSProfilesManager getMobileProvisionbyPath:profilePath];
    return profile[@"Name"];
    
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *table = [notification object];
    if (table == _mainTableView) {
        certificateName = [certsArray objectAtIndex:[table selectedRow]];
        NSLog(@"******* %@", certificateName);
    } else {
        NSString *profilePath = [profilesArray objectAtIndex:[table selectedRow]];
        appProfile = profilePath;
        _appProfileField.stringValue = profilePath;
//        NSLog(@"********* %@", [IMSProfilesManager getMobileProvisionbyPath:profilePath]);
        [self configureAppInfoFieldsFromProfile];
    }
    
}


- (IBAction)tweakButtonSwitched:(NSButton *)sender {
    if (sender.state == NSOnState) {
        isTweak = YES;
        [self showOneSecAlertWithMessage:@"Tweaking mode enabled"];
    } else {
        isTweak = NO;
        [self showOneSecAlertWithMessage:@"Tweaking mode disabled"];
    }
    _dylibButton.enabled = isTweak;
    _additionalField.enabled = isTweak;
}
- (IBAction)dylibFolderSwitched:(NSButton *)sender {
    if (sender.state == NSOnState) {
        isDylib = YES;
        [self showOneSecAlertWithMessage:@"One Dylib mode enabled"];
    } else {
        isDylib = NO;
        [self showOneSecAlertWithMessage:@"Tweak Folder mode enabled"];
    }
}
- (IBAction)ipadSupportSwitched:(NSButton *)sender {
    if (sender.state == NSOnState) {
        isSupportIPAD = YES;
        [self showOneSecAlertWithMessage:@"IPAD mode enabled"];
    } else {
        isSupportIPAD = NO;
        [self showOneSecAlertWithMessage:@"IPAD mode disabled"];
    }
    
}

- (void)updateProgress:(CGFloat)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_progressIndicator setDoubleValue:progress];
    });
    
}

#pragma mark -Helper Methods

- (void)excuteCommandWithLaunchPath:(NSString *)launchPath
                       andArguments:(NSArray *)args
                    andCompleteBlock:(void (^)(BOOL exited))existeBlock{
    GCDTask *task = [[GCDTask alloc] init];
    [task setArguments:args];
    [task setWorkPath:[self extractedPath]];
    [task setLaunchPath:launchPath];
    [task launchWithOutputBlock:^(NSData *stdOutData) {
        // output
        NSString *output = [[NSString alloc] initWithData:stdOutData encoding:NSUTF8StringEncoding];
        NSLog(@"****** %@", output);
    } andErrorBlock:^(NSData *stdErrData) {
        // error
        NSString *errorOutput = [[NSString alloc] initWithData:stdErrData encoding:NSUTF8StringEncoding];
        NSLog(@"****** %@", errorOutput);
    } onLaunch:^{
        // launched
        existeBlock(NO);
    } onExit:^{
       // exited
        existeBlock(YES);
    }];
}
- (NSArray *)getCertifications
{
    NSTask *getCerTask = [[NSTask alloc] init];
    NSPipe *pie = [NSPipe pipe];
    [getCerTask setLaunchPath:@"/usr/bin/security"];
    [getCerTask setArguments:@[@"find-identity", @"-v", @"-p", @"codesigning"]];
    [getCerTask setStandardOutput:pie];
    [getCerTask setStandardError:pie];
    [getCerTask launch];
    
    NSFileHandle *fileHandle = [pie fileHandleForReading];
    NSString *securityResult = [[NSString alloc] initWithData:[fileHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
    NSArray *rawResult = [securityResult componentsSeparatedByString:@"\""];
    NSMutableArray *tempGetCertsResult = [NSMutableArray arrayWithCapacity:20];
    for (int i = 0; i <= rawResult.count - 2; i+=2) {
        if (rawResult.count - 1 < i + 1) {
            
        } else {
            [tempGetCertsResult addObject:[rawResult objectAtIndex:i+1]];
        }
    }
    return tempGetCertsResult;
}

- (NSArray *)getProfiles {
    NSMutableArray *profilesArray = [NSMutableArray new];
    NSURL *libraryDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask] firstObject];
    NSString *libraryPath = libraryDirectory.path;
    NSString *provisioningProfilesPath = [libraryPath stringByAppendingPathComponent:@"MobileDevice/Provisioning Profiles"];
    NSArray *provisioningProfiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:provisioningProfilesPath error:nil];
    for (NSString *profileFile in provisioningProfiles) {
        if ([profileFile.pathExtension isEqualToString:@"mobileprovision"]) {
            NSString *profilePathFull = [provisioningProfilesPath stringByAppendingPathComponent:profileFile];
            [profilesArray addObject:profilePathFull];
        }
    }
    return [profilesArray copy];
}
- (void)ensurePathAt:(NSString *)path
{
    NSError *error;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ( [fm fileExistsAtPath:path] == false ) {
        [fm createDirectoryAtPath:path
      withIntermediateDirectories:YES
                       attributes:nil
                            error:&error];
        if (error) {
            NSLog(@"Ensure Error: %@", error);
        }
        NSLog(@"Creating the missed path");
    }
}

- (BOOL)deleteFileAtPath:(NSString *)filePath {
    BOOL deleted = NO;
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
    if (error) {
        deleted = NO;
        NSLog(@"Error while deleting file : %@", error.localizedDescription);
    } else {
        deleted = YES;
    }
    return deleted;
}

- (BOOL)isFileExecutable:(NSString *)file {
    return [[NSFileManager defaultManager] isExecutableFileAtPath:file];
}

- (NSString *)docPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    return documentsDirectory;
}


- (NSString *)appMainPath {
    NSString *appPath = [[self docPath] stringByAppendingPathComponent:@"IMSign"];
    [self ensurePathAt:appPath];
    return appPath;
}

- (NSString *)tempPath {
    NSString *appTempPath = [[self appMainPath] stringByAppendingPathComponent:@"Temp"];
    [self ensurePathAt:appTempPath];
    return appTempPath;
}

- (NSString *)entitlementsTempPlist {
    
    return [[self tempPath] stringByAppendingPathComponent:@"temp.plist"];
}

- (NSString *)appEntitlementsFile {
    
    return [[self tempPath] stringByAppendingPathComponent:@"app.plist"];
}

- (NSString *)extractedPath {
    NSString *appTempPath = [[self tempPath] stringByAppendingPathComponent:@"ExtractedPath"];
    [self ensurePathAt:appTempPath];
    return appTempPath;
}

- (NSString *)libsPath {
    NSString *appLibsPath = [[self appMainPath] stringByAppendingPathComponent:@"Libs"];
    [self ensurePathAt:appLibsPath];
    return appLibsPath;
}

- (NSString *)payloadAppPath {
    NSString *appTempPayloadExtractedPath = [[self extractedPath] stringByAppendingPathComponent:@"Payload"];
    [self ensurePathAt:appTempPayloadExtractedPath];
    return appTempPayloadExtractedPath;
}

- (NSString *)extractedAppBundlePath {
    NSError *error = nil;
    NSArray *appBundlePath = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self payloadAppPath] error:&error];
    NSMutableArray * dirContents = [[NSMutableArray alloc] initWithArray:appBundlePath];
    if([appBundlePath containsObject:@".DS_Store"]) {
        [dirContents removeObject:@".DS_Store"];
    }
    return [[self payloadAppPath] stringByAppendingPathComponent:[dirContents objectAtIndex:0]];
}

- (NSString *)appPluginPath {
    return [[self extractedAppBundlePath] stringByAppendingPathComponent:@"PlugIns"];
}

- (NSString *)appFrameworksPath {
    return [[self extractedAppBundlePath] stringByAppendingPathComponent:@"Frameworks"];
}

- (NSString *)appCodeSignaturePath {
    return [[self extractedAppBundlePath] stringByAppendingPathComponent:@"_CodeSignature"];
}

- (NSDictionary *)appInfoPlistDictionary {
    NSDictionary *appInfoDict = [NSDictionary dictionaryWithContentsOfFile:[[self extractedAppBundlePath] stringByAppendingPathComponent:@"Info.plist"]];
    return appInfoDict;
}

- (NSString *)insertTempPath {
    NSString *insertPath = [[self appMainPath] stringByAppendingPathComponent:@"Insert"];
    [self ensurePathAt:insertPath];
    return insertPath;
}

- (NSString *)insertDylibPath {
    NSString *insertDylibFilePath = [[self insertTempPath] stringByAppendingPathComponent:@"insert_dylib"];
    return insertDylibFilePath;
}

- (NSString *)insertDylibPathInBundle {
    NSString *insertDylibInBundlePath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"insert_dylib"];
    return insertDylibInBundlePath;
}

- (void)checkIfTheAppAlreadyTweakedWithBlock:(void (^)(BOOL isTweaked, NSArray *allDylibs))tweakedBlock {
    NSError *error = nil;
    NSArray *appContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self extractedAppBundlePath] error:&error];
    NSMutableArray *dylibsArray = [[NSMutableArray alloc] init];
    if (error == nil) {
        for (NSString *file in appContents) {
            if ([file.pathExtension containsString:@"dylib"] || [file.pathExtension containsString:@"Dylib"]) {
                [dylibsArray addObject:file];
            }
        }
        if (dylibsArray.count > 0) {
            tweakedBlock(YES, [dylibsArray copy]);
        } else if (dylibsArray.count == 0) {
            tweakedBlock(NO, nil);
        }
        
    } else {
        tweakedBlock(NO, nil);
    }
}

- (void)showAlertWithMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [DJProgressHUD showStatus:message FromView:[[NSApplication sharedApplication] keyWindow].contentView];
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [DJProgressHUD dismiss];
    });
}

- (void)showOneSecAlertWithMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [DJProgressHUD showStatus:message FromView:[[NSApplication sharedApplication] keyWindow].contentView];
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.7 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [DJProgressHUD dismiss];
    });
}

- (void)cleanAppMainPath {
//    NSError *error = nil;
//    NSArray *appPathContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self appMainPath] error:&error];
//    NSMutableArray * dirContents = [[NSMutableArray alloc] initWithArray:appPathContents];
//    if([appPathContents containsObject:@".DS_Store"])
//    {
//        [dirContents removeObject:@".DS_Store"];
//    }
//    if (error == nil) {
//        for (NSString *file in dirContents) {
//            [self deleteFileAtPath:file];
            [self deleteFileAtPath:[self appMainPath]];
//        }
//    }
}

@end









