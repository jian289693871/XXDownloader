//
//  XXDownloaderOperation.h
//  DownloaderManager
//
//  Created by xuejian on 2017/7/24.
//  Copyright © 2017年 xuejian. All rights reserved.
//

#import <Foundation/Foundation.h>
@class XXDownloaderOperation;


@interface XXDownloaderOperation : NSOperation <NSURLSessionDelegate, NSURLSessionDataDelegate>

/*下载回调*/
@property (nonatomic, copy) void (^operationDidStartBlock)(XXDownloaderOperation *operation, NSURLSessionTask *task);
@property (nonatomic, copy) void (^operationProgressBlock)(XXDownloaderOperation *operation, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite);
@property (nonatomic, copy) void (^operationCompletionBlock)(XXDownloaderOperation *operation, NSString *fileLocation);
@property (nonatomic, copy) void (^operationFailerBlock)(XXDownloaderOperation *operation, NSError *error);

/**
 初始化
 
 @param request 下载请求
 @param targetPath 下载文件保存地址
 @param shouldResume 是否恢复， 默认NO
 @param needRetry 是否重试，默认NO
 @return 返回operation
 */
- (instancetype)initWithRequest:(NSURLRequest *)request targetPath:(NSString *)targetPath shouldResume:(BOOL)shouldResume needRetry:(BOOL)needRetry;

/// 暂停
- (void)pause;

/// 恢复
- (void)resume;
@end
