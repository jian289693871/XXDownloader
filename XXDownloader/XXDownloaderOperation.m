//
//  XXDownloaderOperation.m
//  DownloaderManager
//
//  Created by xuejian on 2017/7/24.
//  Copyright © 2017年 xuejian. All rights reserved.
//

#import "XXDownloaderOperation.h"
#import "XXDownloaderTools.h"
#import "NSError+CMIRetryLevel.h"

typedef NS_ENUM(NSInteger, XXOperationState) {
    XXOperationPausedState      = -1,
    XXOperationReadyState       = 1,
    XXOperationExecutingState   = 2,
    XXOperationFinishedState    = 3,
};

static inline NSString * XXKeyPathFromOperationState(XXOperationState state) {
    switch (state) {
        case XXOperationReadyState:
            return @"isReady";
        case XXOperationExecutingState:
            return @"isExecuting";
        case XXOperationFinishedState:
            return @"isFinished";
        case XXOperationPausedState:
            return @"isPaused";
        default: {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
            return @"state";
#pragma clang diagnostic pop
        }
    }
}

static inline BOOL XXStateTransitionIsValid(XXOperationState fromState, XXOperationState toState, BOOL isCancelled) {
    switch (fromState) {
        case XXOperationReadyState:
            switch (toState) {
                case XXOperationPausedState:
                case XXOperationExecutingState:
                    return YES;
                case XXOperationFinishedState:
                    return isCancelled;
                default:
                    return NO;
            }
        case XXOperationExecutingState:
            switch (toState) {
                case XXOperationPausedState:
                case XXOperationFinishedState:
                    return YES;
                default:
                    return NO;
            }
        case XXOperationFinishedState:
            return NO;
        case XXOperationPausedState:
            return toState == XXOperationReadyState;
        default: {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
            switch (toState) {
                case XXOperationPausedState:
                case XXOperationReadyState:
                case XXOperationExecutingState:
                case XXOperationFinishedState:
                    return YES;
                default:
                    return NO;
            }
        }
#pragma clang diagnostic pop
    }
}


static inline dispatch_source_t xx_dispatch_after(NSTimeInterval t, dispatch_queue_t queue, void (^block)(void)) {
    @autoreleasepool {
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, t * NSEC_PER_SEC), UINT32_MAX * NSEC_PER_SEC, 0 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{
            block();
            dispatch_source_cancel(timer);
        });
        dispatch_resume(timer);
        return timer;
    }
}

static inline void xx_dispatch_main_async_safe(void(^block)(void)){
    if ([NSThread isMainThread]) {
        block();
    }
    else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

static inline void  xx_dispatch_main_sync_safe(void(^block)(void)){
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

@interface XXDownloaderOperation ()
@property (nonatomic, strong) NSURLSession *session;
@property (readwrite, nonatomic, assign) XXOperationState state;
@property (nonatomic, strong) NSURLSessionDataTask *dataTask;
@property (nonatomic, strong) NSRecursiveLock *lock;

@property (nonatomic, strong) NSURLRequest *request;
@property (nonatomic, copy  ) NSString *targetPath;
@property (nonatomic, assign) BOOL shouldResume;
@property (nonatomic, assign) BOOL needRetry;
@property (nonatomic, strong) NSOutputStream *outputStream;

@property (nonatomic, assign) uint64_t totalBytesWritten;   // 已经下载文件长度
@property (nonatomic, assign) uint64_t totalBytesExpectedToWrite;   // 期望下载文件长度
@end

@implementation XXDownloaderOperation

@synthesize executing = _executing;
@synthesize finished = _finished;

- (void)dealloc {
    [self.session invalidateAndCancel];
}

- (instancetype)initWithRequest:(NSURLRequest *)request targetPath:(NSString *)targetPath shouldResume:(BOOL)shouldResume needRetry:(BOOL)needRetry{
    self = [super init];
    if (self) {
        _state = XXOperationReadyState;
        
        self.lock = [[NSRecursiveLock alloc] init];
        self.lock.name = @"com.xx.downloader.lock";
        
        NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        self.session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:nil];
        
        self.request = request;
        self.needRetry = needRetry;
        self.shouldResume = shouldResume;
        
        // 创建对应文件夹
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL isDir = FALSE;
        BOOL isFilePathExit = [fileManager fileExistsAtPath:targetPath.stringByDeletingLastPathComponent isDirectory:&isDir];
        if (!(isFilePathExit && isDir)) {
            NSError *error = nil;
            BOOL isSuccess = [[NSFileManager defaultManager] createDirectoryAtPath:targetPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error];
            NSLog(@"Creat director success:%d, error:%@", isSuccess, error);
            NSAssert(isSuccess, error.description);
        }
        
        self.targetPath = targetPath;
        NSString *tempPath = [self tempPath];
        BOOL isResuming = [self updateByteStartRangeForRequest];
        if (!isResuming) {
            int fileDescriptor = open([tempPath UTF8String], O_CREAT | O_EXCL | O_RDWR, 0666);
            if (fileDescriptor > 0) close(fileDescriptor);
        }
        
        self.outputStream = [NSOutputStream outputStreamToFileAtPath:tempPath append:isResuming];
        [self.outputStream open];
        if (!self.outputStream) return nil;
    }
    return self;
}

- (NSString *)tempPath {
    return [self.targetPath.pathExtension isEqualToString:@""] ? [NSString stringWithFormat:@"%@.tmp", self.targetPath] : [self.targetPath.stringByDeletingPathExtension stringByAppendingString:@".tmp"];
}

- (BOOL)updateByteStartRangeForRequest {
    BOOL isResuming = NO;
    self.totalBytesWritten = 0;
    if (self.shouldResume) {
        unsigned long long downloadedBytes = [XXDownloaderTools fileSizeForPath:[self tempPath]];
        if (downloadedBytes > 1) {
            downloadedBytes--;
            
            NSMutableURLRequest *mutableURLRequest = [self.request mutableCopy];
            NSString *requestRange = [NSString stringWithFormat:@"bytes=%@-", @(downloadedBytes)];
            [mutableURLRequest setValue:requestRange forHTTPHeaderField:@"Range"];
            self.request = mutableURLRequest;
            isResuming = YES;
            
            NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:[self tempPath]];
            [file truncateFileAtOffset:downloadedBytes];
            [file closeFile];
            
            self.totalBytesWritten = downloadedBytes;
        }
    }
    return isResuming;
}

- (BOOL)isReady {
    return self.state == XXOperationReadyState && [super isReady];
}

- (BOOL)isExecuting {
    return self.state == XXOperationExecutingState;
}

- (BOOL)isFinished {
    return self.state == XXOperationFinishedState;
}

- (BOOL)isAsynchronous {
    return YES;
}

- (void)finish {
    [self.lock lock];
    [self.session finishTasksAndInvalidate];
    self.state = XXOperationFinishedState;
    [self.lock unlock];
}

- (void)cancel {
    [self.lock lock];
    if (![self isFinished] && ![self isCancelled]) {
        [super cancel];
        
        if ([self isExecuting]) {
            [self cancelConnection];
        }
    }
    [self.lock unlock];
}

- (void)setState:(XXOperationState)state {
    if (!XXStateTransitionIsValid(self.state, state, [self isCancelled])) {
        return;
    }
    
    [self.lock lock];
    NSString *oldStateKey = XXKeyPathFromOperationState(self.state);
    NSString *newStateKey = XXKeyPathFromOperationState(state);
    
    [self willChangeValueForKey:newStateKey];
    [self willChangeValueForKey:oldStateKey];
    _state = state;
    [self didChangeValueForKey:oldStateKey];
    [self didChangeValueForKey:newStateKey];
    [self.lock unlock];
}

- (void)start {
    [self.lock lock];
    if ([self isCancelled]) {
        [self cancelConnection];
    } else if ([self isReady]) {
        [self operationDidStart];
    }
    [self.lock unlock];
}

- (void)operationDidStart {
    [self.lock lock];
    if (![self isCancelled]) {
        self.state = XXOperationExecutingState;
        [self updateByteStartRangeForRequest];
        self.dataTask = [self.session dataTaskWithRequest:self.request];
        [self.dataTask resume];
    }
    [self.lock unlock];
}

- (void)cancelConnection {
    [self.lock lock];
    NSDictionary *userInfo = nil;
    if ([self.request URL]) {
        userInfo = @{NSURLErrorFailingURLErrorKey : [self.request URL]};
    }
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:userInfo];
    
    if (![self isFinished]) {
        if (self.dataTask) {
            [self.dataTask cancel];
            [self performSelector:@selector(URLSession:task:didCompleteWithError:) withObject:self.dataTask withObject:error];
        } else {
            [self finish];
        }
    }
    [self.lock unlock];
}

- (void)pause {
    if ([self isPaused] || [self isFinished] || [self isCancelled]) {
        return;
    }
    
    [self.lock lock];
    if ([self isExecuting]) {
        [self operationDidPause];
    }
    
    self.state = XXOperationPausedState;
    [self.lock unlock];
}

- (void)operationDidPause {
    [self.lock lock];
    [self.dataTask cancel];
    [self.lock unlock];
}

- (BOOL)isPaused {
    return self.state == XXOperationPausedState;
}
- (void)resume {
    if (![self isPaused]) {
        return;
    }
    
    [self.lock lock];
    self.state = XXOperationReadyState;
    [self start];
    [self.lock unlock];
}


#pragma mark - Delegate
#pragma mark - NSURLSession Delegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(nonnull NSURLResponse *)response completionHandler:(nonnull void (^)(NSURLSessionResponseDisposition))completionHandler {
    [self.outputStream open];
    self.totalBytesExpectedToWrite = response.expectedContentLength + self.totalBytesWritten;
    
    __weak typeof(self) weakSelf = self;
    xx_dispatch_main_async_safe(^{
        __strong typeof(weakSelf) storngSelf = weakSelf;
        if (storngSelf.operationDidStartBlock) {
            storngSelf.operationDidStartBlock(storngSelf, dataTask);
        }
    });
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if (self.outputStream) {
        self.totalBytesWritten +=  data.length;
        [self.outputStream write:data.bytes maxLength:data.length];
        __weak typeof(self) weakSelf = self;
        xx_dispatch_main_async_safe(^{
            __strong typeof(weakSelf) storngSelf = weakSelf;
            if (storngSelf.operationProgressBlock) {
                storngSelf.operationProgressBlock(storngSelf, storngSelf.totalBytesWritten, storngSelf.totalBytesExpectedToWrite);
            }
        });
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error {
    __weak typeof(self) weakSelf = self;
    if (!error) {
        [self.outputStream close];
        NSError *err = nil;
        [[NSFileManager defaultManager] moveItemAtPath:[self tempPath] toPath:self.targetPath error:&err];
        if (error) {
            xx_dispatch_main_sync_safe(^{
                __strong typeof(weakSelf) storngSelf = weakSelf;
                if (storngSelf.operationFailerBlock) {
                    storngSelf.operationFailerBlock(storngSelf, err);
                }
            });
        } else {
            xx_dispatch_main_sync_safe(^{
                __strong typeof(weakSelf) storngSelf = weakSelf;
                if (storngSelf.operationCompletionBlock) {
                    storngSelf.operationCompletionBlock(storngSelf, storngSelf.targetPath);
                }
            });
        }
        [self finish];
    } else {
        CMIRetryLevel level = CMIRetryLevelNever;
        if (self.needRetry) level = [error cmi_retryLevel];
        
        if (level == CMIRetryLevelNever) {
            [self.outputStream close];
            [self.session finishTasksAndInvalidate];
            xx_dispatch_main_sync_safe(^{
                __strong typeof(weakSelf) storngSelf = weakSelf;
                if (storngSelf.operationFailerBlock) {
                    storngSelf.operationFailerBlock(storngSelf, error);
                }
            });
            [self finish];
        } else {
            UInt64 timeout = level;
            xx_dispatch_after(timeout, dispatch_get_main_queue(), ^{
                [weakSelf updateByteStartRangeForRequest];
                weakSelf.dataTask = [weakSelf.session dataTaskWithRequest:weakSelf.request];
                [weakSelf.dataTask resume];
            });
        }
    }
}

@end
