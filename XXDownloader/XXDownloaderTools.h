//
//  XXDownloaderTools.h
//  DownloaderManager
//
//  Created by xuejian on 2017/7/27.
//  Copyright © 2017年 xuejian. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface XXDownloaderTools : NSObject

+ (NSString *)md5:(NSString *)str;
+ (unsigned long long)fileSizeForPath:(NSString *)path; // 文件的大小

@end
