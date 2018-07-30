//
//  XXDownloaderTask.m
//  DownloaderManager
//
//  Created by xuejian on 2017/7/24.
//  Copyright © 2017年 xuejian. All rights reserved.
//

#import "XXDownloaderTask.h"
#import "XXDownloaderTools.h"

@interface XXDownloaderTask ()
@property (nonatomic, copy) NSString *urlString;    // 下载地址，唯一
@property (nonatomic, copy) NSString *fileName;     // 下载文件名称
@property (nonatomic, copy) NSString *fileRelativePath; // 下载文件所在文件夹相对路径
@property (nonatomic, strong) id <NSCoding> meta;
@end

@implementation XXDownloaderTask
- (instancetype)initWithUrl:(NSString *)urlString {
    return [self initWithUrl:urlString fileName:nil relativeFolder:nil];
}

- (instancetype)initWithUrl:(NSString *)urlString relativeFolder:(NSString *)relativeFolder {
    return [self initWithUrl:urlString fileName:nil relativeFolder:relativeFolder];
}


- (instancetype)initWithUrl:(NSString *)urlString fileName:(NSString *)fileName relativeFolder:(NSString *)relativeFolder {
    return [self initWithUrl:urlString fileName:fileName relativeFolder:relativeFolder meta:nil];
}

- (instancetype)initWithUrl:(NSString *)urlString fileName:(NSString *)fileName relativeFolder:(NSString *)relativeFolder meta:(id <NSCoding>)meta {
    self = [super init];
    if (self) {
        NSParameterAssert(urlString);
        self.meta = meta;
        self.urlString = urlString;
        
        // 下载文件名
        self.fileName = fileName;
        if (!self.fileName) {
            NSString *pathExtension = [self.urlString.pathExtension isEqualToString:@""] ? @"" : [NSString stringWithFormat:@".%@", self.urlString.pathExtension];
            self.fileName = [NSString stringWithFormat:@"%@%@",[XXDownloaderTools md5:self.urlString], pathExtension];
        }

        // 下载文件的相对路径
        if (relativeFolder) {
            self.fileRelativePath = [relativeFolder stringByAppendingPathComponent:self.fileName];
        } else {
            self.fileRelativePath = self.fileName;
        }
        
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        self.urlString = [aDecoder decodeObjectForKey:@"urlString"];
        self.fileName = [aDecoder decodeObjectForKey:@"fileName"];
        self.fileRelativePath = [aDecoder decodeObjectForKey:@"fileRelativePath"];
        self.state = [[aDecoder decodeObjectForKey:@"state"] integerValue];
        self.totalBytesWritten = [[aDecoder decodeObjectForKey:@"totalBytesWritten"] longLongValue];
        self.totalBytesExpected = [[aDecoder decodeObjectForKey:@"totalBytesExpected"] longLongValue];
        self.meta = [aDecoder decodeObjectForKey:@"meta"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.urlString forKey:@"urlString"];
    [aCoder encodeObject:self.fileName forKey:@"fileName"];
    [aCoder encodeObject:self.fileRelativePath forKey:@"fileRelativePath"];
    [aCoder encodeObject:@(self.state) forKey:@"state"];
    [aCoder encodeObject:@(self.totalBytesWritten) forKey:@"totalBytesWritten"];
    [aCoder encodeObject:@(self.totalBytesExpected) forKey:@"totalBytesExpected"];
    [aCoder encodeObject:self.meta forKey:@"meta"];
}
@end
