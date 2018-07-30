//
//  XXDownloaderConfiguration.h
//  iPhoneAPP
//
//  Created by xuejian on 2017/8/3.
//  Copyright © 2017年 oo. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface XXDownloaderConfiguration : NSObject
@property (nonatomic, copy) NSString *downloaderFolder; // 下载文件根目录,默认为com.xx.downloader
@property (nonatomic, assign) BOOL allowWWANDownloader; // 是否允许非wifi环境下载，默认NO
@property (nonatomic, assign) NSInteger maxConcurrentOperationCount;    // 并发数，默认为1

+ (instancetype)defaultDownloaderConfiguration;
@end
