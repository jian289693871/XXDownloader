//
//  XXDownloaderTask.h
//  DownloaderManager
//
//  Created by xuejian on 2017/7/24.
//  Copyright © 2017年 xuejian. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XXDownloaderOperation.h"

// 下载状态
typedef NS_ENUM(NSUInteger, XXDownloadState) {
    XXDownloadStateNone         = 0,        // 未下载
    XXDownloadStateReadying     = 1 << 0,   // 等待下载
    XXDownloadStateRunning      = 1 << 1,   // 正在下载
    XXDownloadStateNormalPaused = 1 << 2,   // 普通下载暂停，只能手动恢复
    XXDownloadStateWWANPaused   = 1 << 3,   // WWAN下载暂停，非wifi下的自动暂停，切换至wifi下自动恢复，也可手动恢复
    XXDownloadStateCompleted    = 1 << 4,   // 下载完成
    XXDownloadStateFailed       = 1 << 5,   // 下载失败
    XXDownloadStateFileError    = 1 << 6,   // 下载文件错误，如下载文件被删除，调用restart重新开始或者重新添加该任务
};

@interface XXDownloaderTask : NSObject <NSCoding>
/*
 example:
 urlString : http://dldir1.qq.com/qqfile/QQforMac/QQ_V6.0.1.dmg
 fileName : md5(http://dldir1.qq.com/qqfile/QQforMac/QQ_V6.0.1.dmg).dmg
 fileRelativePath : xxx/xxx.dmg
 */
@property (nonatomic, copy, readonly) NSString *urlString;    // 下载地址，唯一
@property (nonatomic, copy, readonly) NSString *fileName;     // 下载文件名称,默认md5(urlString).extension
@property (nonatomic, copy, readonly) NSString *fileRelativePath; // 下载文件相对路径
@property (nonatomic, strong, readonly) id <NSCoding> meta;     // 额外的关联对象，如关联到pdf模型对象

@property (nonatomic, assign) XXDownloadState state;    // 下载状态
@property (nonatomic, assign) int64_t totalBytesWritten;    // 已下载字节数
@property (nonatomic, assign) int64_t totalBytesExpected;   // 需要总下载字节数

@property (nonatomic, weak) XXDownloaderOperation *operation;


/* 下载回调 */
@property (nonatomic, copy) void (^downProgress)(XXDownloaderTask *task, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite);
@property (nonatomic, copy) void (^downCompleted)(XXDownloaderTask *task);
@property (nonatomic, copy) void (^downFailed)(XXDownloaderTask *task, NSError *error);

/**
 创建一个任务

 @param urlString 下载地址,不能为空
 @param fileName 下载文件名称，当为nil时，默认为md5(urlString).extension
 @param relativeFolder 下载文件保存的文件夹，当为nil时，，默认为根下载目录
 @param meta 额外的关联对象，如关联到pdf模型对象，视频模型对象
 */
- (instancetype)initWithUrl:(NSString *)urlString fileName:(NSString *)fileName relativeFolder:(NSString *)relativeFolder meta:(id <NSCoding>)meta;
- (instancetype)initWithUrl:(NSString *)urlString fileName:(NSString *)fileName relativeFolder:(NSString *)relativeFolder;
- (instancetype)initWithUrl:(NSString *)urlString relativeFolder:(NSString *)relativeFolder;
- (instancetype)initWithUrl:(NSString *)urlString;
@end
