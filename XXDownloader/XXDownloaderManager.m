//
//  XXDownloaderManager.m
//  DownloaderManager
//
//  Created by xuejian on 2017/7/24.
//  Copyright © 2017年 xuejian. All rights reserved.
//

#import "XXDownloaderManager.h"
#import "XXDownloaderOperation.h"
#import "XXDownloaderTools.h"
#import "Reachability.h"

NSString *const XXDownloaderCompletedNotification = @"XXDownloaderCompletedNotification";

@interface XXDownloaderManager () <NSURLSessionDelegate>
@property (nonatomic, strong) NSOperationQueue *downloadQueue;
@property (nonatomic, strong) NSMutableArray *tasks;
@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, copy) NSString *downloaderFolder;
@property (nonatomic, assign) BOOL allowWWANDownloader; // 是否允许非wifi环境下载，默认NO
@property (nonatomic, strong) XXDownloaderConfiguration *configureation;
@end

@implementation XXDownloaderManager

+ (instancetype)defaultManager {
    static XXDownloaderManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[XXDownloaderManager alloc] initWithDownloaderConfiguration:[XXDownloaderConfiguration defaultDownloaderConfiguration]];
    });
    return manager;
}


- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init {
    return [self initWithDownloaderConfiguration:[XXDownloaderConfiguration defaultDownloaderConfiguration]];
}

- (instancetype)initWithDownloaderConfiguration:(XXDownloaderConfiguration *)configuration {
    self = [super init];
    if (self) {
        NSParameterAssert(configuration);

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate) name:UIApplicationWillTerminateNotification object:nil];
        
        self.configureation = configuration;
        self.allowWWANDownloader = configuration.allowWWANDownloader;
        self.downloaderFolder = configuration.downloaderFolder;
        self.tasks = [[NSMutableArray alloc] initWithArray:[self restoreDownloaderTasksCaches]];
        self.downloadQueue = [[NSOperationQueue alloc] init];
        self.downloadQueue.maxConcurrentOperationCount = configuration.maxConcurrentOperationCount;
        
        [self addNetworkReachabilityObserver];
    }
    return self;
}

- (NSArray<XXDownloaderTask *> *)getAllTasks {
    return self.tasks;
}

- (XXDownloaderTask *)downloaderTaskWithUrlString:(NSString *)urlString {
    for (XXDownloaderTask *t in self.tasks) {
        if ([t.urlString isEqualToString:urlString]) {
            return t;
        }
    }
    return nil;
}

- (XXDownloaderTask *)downloaderTaskWithTask:(XXDownloaderTask *)task {
    for (XXDownloaderTask *t in self.tasks) {
        if ([t.urlString isEqualToString:task.urlString]) {
            return t;
        }
    }
    return task;
}

- (XXDownloaderAddTaskState)addDownloaderTask:(XXDownloaderTask *)task {
    for (XXDownloaderTask *t in self.tasks) {
        if ([t.urlString isEqualToString:task.urlString]) {
            if (t.state == XXDownloadStateCompleted) {
                NSString *path = [self.downloaderFolder stringByAppendingPathComponent:task.fileRelativePath];
                if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                    // 如果下载文件不存在，修改任务状态
                    t.state = XXDownloadStateNone;
                }
            } else {
                t.state = XXDownloadStateNone;
            }
            [self startDownloaderTask:t];
            return XXDownloaderAddTaskStateExisting;
        }
    }
    
    [self.tasks insertObject:task atIndex:0];
    [self setupOperationWithTask:task];
    return XXDownloaderAddTaskStateSucceed;
}

- (void)startDownloaderTask:(XXDownloaderTask *)task {
    XXDownloaderTask *currentTask = [self downloaderTaskWithTask:task];
    if (currentTask.state == XXDownloadStateNone ||
        currentTask.state == XXDownloadStateNormalPaused ||
        currentTask.state == XXDownloadStateWWANPaused ||
        currentTask.state == XXDownloadStateFailed) {
        [self setupOperationWithTask:currentTask];
    }
}

- (void)startAllDownloaderTask {
    for (NSInteger i = self.tasks.count - 1; i >= 0; i--) {
        XXDownloaderTask *task = self.tasks[i];
        [self startDownloaderTask:task];
    }
}

// 开始所有XXDownloadStateWWANPaused暂停的任务
- (void)startWWANDownloaderTasks {
    for (NSInteger i = self.tasks.count - 1; i >= 0; i--) {
        XXDownloaderTask *task = self.tasks[i];
        if (task.state == XXDownloadStateWWANPaused)
            [self startDownloaderTask:task];
    }
}

- (void)restartDownloaderTask:(XXDownloaderTask *)task {
    XXDownloaderTask *currentTask = [self downloaderTaskWithTask:task];
    if (currentTask.state == XXDownloadStateNone ||
        currentTask.state == XXDownloadStateNormalPaused ||
        currentTask.state == XXDownloadStateWWANPaused ||
        currentTask.state == XXDownloadStateFailed ||
        currentTask.state == XXDownloadStateFileError) {
        // 删除已经存在的下载文件
        [[NSFileManager defaultManager] removeItemAtPath:[self downloaderTmpFilePath:currentTask] error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[self downloaderFilePath:currentTask] error:nil];
        [self setupOperationWithTask:currentTask];
    }
}

- (void)pauseDownloaderTask:(XXDownloaderTask *)task {
    XXDownloaderTask *currentTask = [self downloaderTaskWithTask:task];
    if (currentTask.operation) {
        if (currentTask.state == XXDownloadStateReadying ||
            currentTask.state == XXDownloadStateRunning) {
            [currentTask.operation cancel];
        }
    }
}

- (void)pauseAllDownloaderTask {
    for (XXDownloaderTask *t in self.tasks) {
        [self pauseDownloaderTask:t];
    }
}

// 切换到wwan，暂停所有任务
- (void)pauseWWANDownloaderTasks {
    for (XXDownloaderTask *task in self.tasks) {
        if (task.operation) {
            if (task.state == XXDownloadStateReadying ||
                task.state == XXDownloadStateRunning) {
                [self changeTaskState:task state:XXDownloadStateWWANPaused];
                [task.operation cancel];
            }
        }
    }
}

- (void)deleteDownloaderTask:(XXDownloaderTask *)task {
    [self.tasks enumerateObjectsUsingBlock:^(XXDownloaderTask *t, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([t.urlString isEqualToString:task.urlString]) {
            [self pauseDownloaderTask:t];
            [self.tasks removeObject:t];
            
            // 删除文件
            [[NSFileManager defaultManager] removeItemAtPath:[self downloaderTmpFilePath:t] error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:[self downloaderFilePath:t] error:nil];
            *stop = YES;
        }
    }];
    [self storeDownloaderTasksCaches];
}

- (void)deleteAllDownloaderTask {
    for (XXDownloaderTask *t in self.tasks) {
        [self pauseDownloaderTask:t];
        // 删除文件
        [[NSFileManager defaultManager] removeItemAtPath:[self downloaderTmpFilePath:t] error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[self downloaderFilePath:t] error:nil];
    }
    [self.tasks removeAllObjects];
    [self storeDownloaderTasksCaches];
}

- (void)deleteInvalidDownloaders {
    [self.tasks enumerateObjectsUsingBlock:^(XXDownloaderTask *t, NSUInteger idx, BOOL * _Nonnull stop) {
        BOOL needDelete = NO;
        if (t.state == XXDownloadStateFileError) {
            needDelete = YES;
        } else if (t.state == XXDownloadStateCompleted) {
            NSString *path = [self.downloaderFolder stringByAppendingPathComponent:t.fileRelativePath];
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                needDelete = YES;
            }
        }
        if (needDelete) {
            [self.tasks removeObject:t];
            [[NSFileManager defaultManager] removeItemAtPath:[self downloaderTmpFilePath:t] error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:[self downloaderFilePath:t] error:nil];
        }
    }];
    [self storeDownloaderTasksCaches];
}

- (void)setupOperationWithTask:(XXDownloaderTask *)task {
    [self changeTaskState:task state:XXDownloadStateReadying];
    if (task.operation) {
        [task.operation cancel];
    }
    
    XXDownloaderOperation *operation = nil;
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:task.urlString]];
    operation = [[XXDownloaderOperation alloc] initWithRequest:request targetPath:[self downloaderFilePath:task] shouldResume:YES needRetry:YES];
    __weak typeof(task) weakTask = task;
    __weak typeof(self) weakSelf = self;
    operation.operationDidStartBlock = ^(XXDownloaderOperation *operation, NSURLSessionTask *task) {
        [weakSelf changeTaskState:weakTask state:XXDownloadStateRunning];
    };
    operation.operationProgressBlock = ^(XXDownloaderOperation *operation, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
        weakTask.totalBytesWritten = totalBytesWritten;
        weakTask.totalBytesExpected = totalBytesExpectedToWrite;
        if (weakTask.downProgress) {
            weakTask.downProgress(weakTask, totalBytesWritten, totalBytesExpectedToWrite);
        }
    };
    operation.operationCompletionBlock = ^(XXDownloaderOperation *operation, NSString *fileLocation) {
        [weakSelf changeTaskState:weakTask state:XXDownloadStateCompleted];
        if (weakTask.downCompleted) {
            weakTask.downCompleted(weakTask);
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:XXDownloaderCompletedNotification object:weakTask];
    };
    operation.operationFailerBlock = ^(XXDownloaderOperation *operation, NSError *error) {
        [weakSelf changeTaskState:weakTask state:(error.code == NSURLErrorCancelled ? XXDownloadStateNormalPaused : XXDownloadStateFailed)];
        if (weakTask.downFailed) {
            weakTask.downFailed(task, error);
        }
    };
    task.operation = operation;
    [self.downloadQueue addOperation:operation];
}

- (void)applicationWillTerminate {
    [self storeDownloaderTasksCaches];
}

- (void)changeTaskState:(XXDownloaderTask *)task state:(XXDownloadState)state {
    if (task.state != state &&
        (task.state | state) != (XXDownloadStateNormalPaused | XXDownloadStateWWANPaused)) {
        task.state = state;
    }
    
    [self storeDownloaderTasksCaches];
}

#pragma mark - 任务缓存
#pragma mark -- 读取缓存
- (NSArray *)restoreDownloaderTasksCaches {
    NSArray *taskArray = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tasksCachesPath = [self downloaderTasksCachesPath];
    if ([fm fileExistsAtPath:tasksCachesPath]) {
        taskArray = [NSKeyedUnarchiver unarchiveObjectWithFile:tasksCachesPath];
        for (XXDownloaderTask *task in taskArray) {
            if (task.state != XXDownloadStateCompleted) {
                if (task.state != XXDownloadStateFileError) {
                    task.state = XXDownloadStateNormalPaused;
                }
            } else {
                NSString *path = [self.downloaderFolder stringByAppendingPathComponent:task.fileRelativePath];
                if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                    task.state = XXDownloadStateFileError;
                }
            }
        }
    }
    return taskArray;
}

#pragma mark -- 保存缓存
- (void)storeDownloaderTasksCaches {
    [NSKeyedArchiver archiveRootObject:self.tasks toFile:[self downloaderTasksCachesPath]];
}

#pragma mark - 文件路径相关
// 下载任务列表缓存路径
- (NSString *)downloaderTasksCachesPath {
    return [NSString stringWithFormat:@"%@/tasksListCache", self.downloaderFolder];
}

// 下载文件绝对路径
- (NSString *)downloaderFilePath:(XXDownloaderTask *)task {
    return [self.downloaderFolder stringByAppendingPathComponent:task.fileRelativePath];
}

// 下载缓存文件路径
- (NSString *)downloaderTmpFilePath:(XXDownloaderTask *)task {
    return [[self downloaderFilePath:task].stringByDeletingPathExtension stringByAppendingString:@".tmp"];
}

#pragma mark - 检测网络
- (void)addNetworkReachabilityObserver {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChanged:) name:kReachabilityChangedNotification object:nil];
    self.reachability = [Reachability reachabilityForInternetConnection];
    [self taskWithNetworkStatus:[self.reachability currentReachabilityStatus]];
    [self.reachability startNotifier];
}

- (void)reachabilityChanged:(NSNotification *)notification {
    Reachability *reachability = notification.object;
    NetworkStatus status = [reachability currentReachabilityStatus];
    [self taskWithNetworkStatus:status];
}

- (void)taskWithNetworkStatus:(NetworkStatus)status {
    switch (status) {
        case ReachableViaWiFi:
            [self startWWANDownloaderTasks];
            break;
        case ReachableViaWWAN:
            if (!self.allowWWANDownloader) {
                [self pauseWWANDownloaderTasks];
            }
            break;
        default:
            break;
    }
}
@end
