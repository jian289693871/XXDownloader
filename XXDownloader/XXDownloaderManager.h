//
//  XXDownloaderManager.h
//  DownloaderManager
//
//  Created by xuejian on 2017/7/24.
//  Copyright © 2017年 xuejian. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "XXDownloaderTask.h"
#import "XXDownloaderConfiguration.h"

// 任务完成通知
extern NSString *const XXDownloaderCompletedNotification;

// 添加下载任务状态
typedef NS_ENUM(NSUInteger, XXDownloaderAddTaskState) {
    XXDownloaderAddTaskStateFailed,   // 失败
    XXDownloaderAddTaskStateSucceed,  // 成功
    XXDownloaderAddTaskStateExisting, // 已经存在
};

@interface XXDownloaderManager : NSObject

+ (instancetype)defaultManager;
- (instancetype)initWithDownloaderConfiguration:(XXDownloaderConfiguration *)configuration;

@property (nonatomic, strong, readonly) XXDownloaderConfiguration *configureation;

// 获取下载文件路径
- (NSString *)downloaderFilePath:(XXDownloaderTask *)task;

// 获取所有下载任务
- (NSArray <XXDownloaderTask *> *)getAllTasks;

// 通过url获取相应的下载任务
- (XXDownloaderTask *)downloaderTaskWithUrlString:(NSString *)urlString;

// 添加下载任务
- (XXDownloaderAddTaskState)addDownloaderTask:(XXDownloaderTask *)task;

// 开始下载任务
- (void)startDownloaderTask:(XXDownloaderTask *)task;
// 开始所有下载任务
- (void)startAllDownloaderTask;
// 开始所有XXDownloadStateWWANPaused暂停的任务
- (void)startWWANDownloaderTasks;

// 重新开始下载任务
- (void)restartDownloaderTask:(XXDownloaderTask *)task;

// 暂停任务
- (void)pauseDownloaderTask:(XXDownloaderTask *)task;
// 暂停所有下载任务
- (void)pauseAllDownloaderTask;
// 切换到wwan，暂停所有任务
- (void)pauseWWANDownloaderTasks;

// 删除下载任务
- (void)deleteDownloaderTask:(XXDownloaderTask *)task;
// 删除所有下载任务及其缓存
- (void)deleteAllDownloaderTask;
// 删除无效任务,即下载文件不存在等等情况
- (void)deleteInvalidDownloaders;
@end
