//
//  XXDownloaderConfiguration.m
//  iPhoneAPP
//
//  Created by xuejian on 2017/8/3.
//  Copyright © 2017年 oo. All rights reserved.
//

#import "XXDownloaderConfiguration.h"

@implementation XXDownloaderConfiguration

+ (NSString *)defaultDownloaderFolder {
    static NSString *defaultDirector = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *libraryDirector = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES)firstObject];
        defaultDirector = [NSString stringWithFormat:@"%@/%@", libraryDirector, @"com.xx.downloader"];
    });
    return defaultDirector;
}


+ (instancetype)defaultDownloaderConfiguration {
    static XXDownloaderConfiguration *defaultConfiguration = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultConfiguration = [[XXDownloaderConfiguration alloc] init];
        
    });
    return defaultConfiguration;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.downloaderFolder = [[self class] defaultDownloaderFolder];
        self.maxConcurrentOperationCount = 1;
        self.allowWWANDownloader = NO;
    }
    return self;
}
@end
